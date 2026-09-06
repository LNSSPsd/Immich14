#import "IMSearchApi.h"
#import "IMApiClient.h"
#import "common.h"
#import <math.h>

NSNotificationName const IMPeopleDidChangeNotification = @"IMPeopleDidChangeNotification";

NSString *const IMSearchSuggestionTypeCountry = @"country";
NSString *const IMSearchSuggestionTypeState = @"state";
NSString *const IMSearchSuggestionTypeCity = @"city";
NSString *const IMSearchSuggestionTypeCameraMake = @"camera-make";
NSString *const IMSearchSuggestionTypeCameraModel = @"camera-model";
NSString *const IMSearchSuggestionTypeCameraLensModel = @"camera-lens-model";

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static NSError *IMSearchMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid search response.")}];
}

static NSError *IMSearchInvalidInput(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"Invalid search criteria.") }];
}

static BOOL IMSearchNumberInRange(id value, NSInteger minimum, NSInteger maximum) {
	if (![value isKindOfClass:[NSNumber class]]) {
		return NO;
	}
	double number = [value doubleValue];
	return isfinite(number) && floor(number) == number && number >= (double)minimum && number <= (double)maximum;
}

static BOOL IMSearchNonEmptyString(id value) {
	if (![value isKindOfClass:[NSString class]]) {
		return NO;
	}
	NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return trimmed.length > 0;
}

static BOOL IMSearchUUIDString(id value) {
	if (!IMSearchNonEmptyString(value)) {
		return NO;
	}
	return [[NSUUID alloc] initWithUUIDString:value] != nil;
}

static BOOL IMSearchDateString(id value) {
	if (!IMSearchNonEmptyString(value)) {
		return NO;
	}
	return IMDateFromServerTimestamp(value) != nil;
}

static BOOL IMSearchStringKey(NSString *key) {
	return [@[
		@"city", @"state", @"country", @"make", @"model", @"lensModel", @"ocr",
		@"createdBefore", @"createdAfter", @"updatedBefore", @"updatedAfter",
		@"trashedBefore", @"trashedAfter", @"takenBefore", @"takenAfter",
	] containsObject:key];
}

static BOOL IMSearchNullableKey(NSString *key) {
	return [@[
		@"city", @"state", @"country", @"make", @"model", @"lensModel", @"libraryId", @"rating", @"tagIds",
	] containsObject:key];
}

static BOOL IMSearchArrayKey(NSString *key) {
	return [@[@"albumIds", @"personIds", @"tagIds"] containsObject:key];
}

static BOOL IMSearchBooleanKey(NSString *key) {
	return [@[
		@"isEncoded", @"isFavorite", @"isMotion", @"isNotInAlbum", @"isOffline", @"withDeleted", @"withExif",
		@"withPeople", @"withStacked",
	] containsObject:key];
}

static BOOL IMSearchDateKey(NSString *key) {
	return [@[
		@"createdBefore", @"createdAfter", @"updatedBefore", @"updatedAfter",
		@"trashedBefore", @"trashedAfter", @"takenBefore", @"takenAfter",
	] containsObject:key];
}

static NSSet<NSString *> *IMSearchCriteriaKeys(BOOL random, BOOL statistics) {
	NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:@[
		@"libraryId", @"type", @"isEncoded", @"isFavorite", @"isMotion", @"isOffline", @"visibility",
		@"createdBefore", @"createdAfter", @"updatedBefore", @"updatedAfter", @"trashedBefore", @"trashedAfter",
		@"takenBefore", @"takenAfter", @"city", @"state", @"country", @"make", @"model", @"lensModel",
		@"isNotInAlbum", @"personIds", @"tagIds", @"albumIds", @"rating", @"ocr",
	]];
	if (!statistics) {
		[keys addObjectsFromArray:@[@"withDeleted", @"withExif", @"size"]];
		if (!random) {
			[keys addObject:@"minFileSize"];
		}
	}
	if (random) {
		[keys addObjectsFromArray:@[@"withPeople", @"withStacked"]];
	}
	if (statistics) {
		[keys addObject:@"description"];
	}
	return keys.copy;
}

static NSDictionary<NSString *, id> *IMSearchValidatedCriteria(NSDictionary<NSString *, id> *criteria,
	                                                              BOOL random,
	                                                              BOOL statistics,
	                                                              NSError **errorOut) {
	if (!criteria) {
		return @{};
	}
	if (![criteria isKindOfClass:[NSDictionary class]]) {
		if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search criteria must be an object."));
		return nil;
	}
	NSSet<NSString *> *allowed = IMSearchCriteriaKeys(random, statistics);
	for (id rawKey in criteria) {
		if (![rawKey isKindOfClass:[NSString class]] || ![allowed containsObject:rawKey]) {
			if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search criteria contains an unsupported field."));
			return nil;
		}
		NSString *key = (NSString *)rawKey;
		id value = criteria[key];
		if (value == nil) {
			if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search criteria contains a null field."));
			return nil;
		}
		if ([value isKindOfClass:[NSNull class]]) {
			if (!random && !statistics) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Nullable filters are not supported for large-asset queries."));
				return nil;
			}
			if (!IMSearchNullableKey(key)) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"This search field cannot be null."));
				return nil;
			}
			continue;
		}
		if (IMSearchArrayKey(key)) {
			if (![value isKindOfClass:[NSArray class]]) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search ID filters must be arrays."));
				return nil;
			}
			for (id item in (NSArray *)value) {
				if (!IMSearchUUIDString(item)) {
					if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search ID filters must contain valid UUIDs."));
					return nil;
				}
			}
			continue;
		}
		if (IMSearchBooleanKey(key)) {
			if (![value isKindOfClass:[NSNumber class]] ||
			    !isfinite([value doubleValue]) ||
			    ([value doubleValue] != 0.0 && [value doubleValue] != 1.0)) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Boolean search fields must be numbers."));
				return nil;
			}
			continue;
		}
		if ([key isEqualToString:@"size"]) {
			if (!IMSearchNumberInRange(value, 1, 1000)) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search size must be between 1 and 1000."));
				return nil;
			}
			continue;
		}
		if ([key isEqualToString:@"minFileSize"]) {
			if (![value isKindOfClass:[NSNumber class]] ||
			    !isfinite([value doubleValue]) ||
			    floor([value doubleValue]) != [value doubleValue] ||
			    [value doubleValue] < 0.0 || [value doubleValue] > 9007199254740991.0) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Minimum file size must be a non-negative integer."));
				return nil;
			}
			continue;
		}
		if ([key isEqualToString:@"rating"]) {
			if (!IMSearchNumberInRange(value, 1, 5)) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Rating must be between 1 and 5."));
				return nil;
			}
			continue;
		}
		if ([key isEqualToString:@"type"]) {
			if (![value isKindOfClass:[NSString class]] ||
			    ![@[ @"IMAGE", @"VIDEO", @"AUDIO", @"OTHER" ] containsObject:value]) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Asset type is invalid."));
				return nil;
			}
			continue;
		}
		if ([key isEqualToString:@"visibility"]) {
			if (![value isKindOfClass:[NSString class]] ||
			    ![@[ @"timeline", @"archive", @"hidden", @"locked" ] containsObject:value]) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Asset visibility is invalid."));
				return nil;
			}
			continue;
		}
		if ([key isEqualToString:@"libraryId"]) {
			if (!IMSearchUUIDString(value)) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Library ID must be a valid UUID."));
				return nil;
			}
			continue;
		}
		if (IMSearchDateKey(key)) {
			if (!IMSearchDateString(value)) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search dates must be valid ISO-8601 timestamps."));
				return nil;
			}
			continue;
		}
		if (IMSearchStringKey(key) || [key isEqualToString:@"description"]) {
			if (!IMSearchNonEmptyString(value)) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search text fields cannot be empty."));
				return nil;
			}
			continue;
		}
		if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search criteria contains an invalid value."));
		return nil;
	}
	if (! [NSJSONSerialization isValidJSONObject:criteria]) {
		if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search criteria cannot be encoded as JSON."));
		return nil;
	}
	return [criteria copy];
}

static NSArray<NSURLQueryItem *> *IMSearchQueryItemsFromCriteria(NSDictionary<NSString *, id> *criteria) {
	NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
	NSArray<NSString *> *keys = [[criteria allKeys] sortedArrayUsingSelector:@selector(compare:)];
	for (NSString *key in keys) {
		id value = criteria[key];
		if ([value isKindOfClass:[NSNull class]]) {
			continue;
		}
		if ([value isKindOfClass:[NSArray class]]) {
			for (id element in (NSArray *)value) {
				[items addObject:[NSURLQueryItem queryItemWithName:key value:[element description]]];
			}
			continue;
		}
		NSString *stringValue = nil;
		if ([value isKindOfClass:[NSString class]]) {
			stringValue = value;
		} else if ([value isKindOfClass:[NSNumber class]]) {
			stringValue = [value isEqual:@YES] ? @"true" : ([value isEqual:@NO] ? @"false" : [value stringValue]);
		}
		if (stringValue.length > 0) {
			[items addObject:[NSURLQueryItem queryItemWithName:key value:stringValue]];
		}
	}
	return items;
}

static BOOL IMSearchAssetBodyIsValid(NSDictionary *body, NSError **errorOut) {
	if (![body isKindOfClass:[NSDictionary class]]) {
		if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search criteria must be an object."));
		return NO;
	}
	for (NSString *key in @[ @"query", @"ocr", @"originalFileName", @"description", @"city" ]) {
		if (body[key] != nil && !IMSearchNonEmptyString(body[key])) {
			if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search text cannot be empty."));
			return NO;
		}
	}
	for (NSString *key in @[ @"personIds", @"tagIds" ]) {
		id value = body[key];
		if (value == nil) continue;
		if (![value isKindOfClass:[NSArray class]]) {
			if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search ID filters must be arrays."));
			return NO;
		}
		for (id identifier in (NSArray *)value) {
			if (!IMSearchUUIDString(identifier)) {
				if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search ID filters must contain valid UUIDs."));
				return NO;
			}
		}
	}
	if (![NSJSONSerialization isValidJSONObject:body]) {
		if (errorOut) *errorOut = IMSearchInvalidInput(_(@"Search criteria cannot be encoded as JSON."));
		return NO;
	}
	return YES;
}

static NSString *IMSearchEscapedPathComponent(NSString *value) {
	return [value stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]] ?: value;
}

static NSArray<IMAsset *> *IMSearchAssetsFromItems(NSArray *items) {
	if (![items isKindOfClass:[NSArray class]]) {
		return nil;
	}
	NSArray<IMAsset *> *assets = [IMAsset assetsWithResponseArray:items];
	return assets.count == items.count ? assets : nil;
}

@implementation IMSearchApi

static NSArray<IMPerson *> *sCachedPeople;
static NSArray<IMAsset *> *sCachedPlaceAssets;
static NSArray<NSString *> *sCachedPlaceCityNames;

static const NSInteger kIMSearchPageSize = 100;
static const NSInteger kIMPeoplePageSize = 1000;

#pragma mark - Asset search

+ (nullable NSURLSessionTask *)postSearch:(NSString *)path
                                      body:(NSDictionary *)body
                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	NSError *validationError = nil;
	if (!IMSearchAssetBodyIsValid(body, &validationError)) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, validationError ?: IMSearchInvalidInput(_(@"Invalid search criteria."))); });
		return nil;
	}
	return [[IMApiClient shared] POST:path
	                              body:body
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error ?: IMSearchMalformedResponse());
			    return;
		    }
		    id assetsValue = IMValueOrNil(((NSDictionary *)json)[@"assets"]);
		    NSDictionary *assetsDict = [assetsValue isKindOfClass:[NSDictionary class]] ? assetsValue : nil;
		    id items = IMValueOrNil(assetsDict[@"items"]);
		    if (assetsDict == nil || ![items isKindOfClass:[NSArray class]]) {
			    completion(nil, IMSearchMalformedResponse());
			    return;
		    }
		    NSArray<IMAsset *> *assets = IMSearchAssetsFromItems(items);
		    if (!assets) {
			    completion(nil, IMSearchMalformedResponse());
			    return;
		    }
		    completion(assets, nil);
	    }];
}

+ (nullable NSURLSessionTask *)postSearch:(NSString *)path
                                      body:(NSDictionary *)body
                                      page:(NSInteger)page
                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                                     NSString *_Nullable nextPage,
                                                     NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	NSError *validationError = nil;
	if (!IMSearchAssetBodyIsValid(body, &validationError)) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, validationError ?: IMSearchInvalidInput(_(@"Invalid search criteria."))); });
		return nil;
	}
	NSMutableDictionary *pagedBody = [body mutableCopy];
	pagedBody[@"page"] = @(page < 1 ? 1 : page);
	pagedBody[@"size"] = @(kIMSearchPageSize);
	return [[IMApiClient shared] POST:path
	                              body:pagedBody
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, nil, error ?: IMSearchMalformedResponse());
			    return;
		    }
		    id assetsValue = IMValueOrNil(((NSDictionary *)json)[@"assets"]);
		    NSDictionary *assetsDict = [assetsValue isKindOfClass:[NSDictionary class]] ? assetsValue : nil;
		    id items = IMValueOrNil(assetsDict[@"items"]);
		    id nextPage = IMValueOrNil(assetsDict[@"nextPage"]);
		    if (assetsDict == nil || ![items isKindOfClass:[NSArray class]] ||
		        (nextPage != nil && ![nextPage isKindOfClass:[NSString class]])) {
			    completion(nil, nil, IMSearchMalformedResponse());
			    return;
		    }
		    NSArray<IMAsset *> *assets = IMSearchAssetsFromItems(items);
		    if (!assets) {
			    completion(nil, nil, IMSearchMalformedResponse());
			    return;
		    }
		    completion(assets,
		               [nextPage isKindOfClass:[NSString class]] ? nextPage : nil,
		               nil);
	    }];
}

+ (nullable NSURLSessionTask *)smartSearchWithQuery:(NSString *)query
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/smart" body:@{ @"query": query ?: @"" } completion:completion];
}

+ (nullable NSURLSessionTask *)smartSearchWithQuery:(NSString *)query
                                                page:(NSInteger)page
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/smart" body:@{ @"query": query ?: @"" } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithOcr:(NSString *)ocrText
                                           completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"ocr": ocrText ?: @"" } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithOcr:(NSString *)ocrText
                                                 page:(NSInteger)page
                                           completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"ocr": ocrText ?: @"" } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithFilename:(NSString *)filename
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"originalFileName": filename ?: @"" } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithFilename:(NSString *)filename
                                                      page:(NSInteger)page
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"originalFileName": filename ?: @"" } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithDescription:(NSString *)description
                                                   completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"description": description ?: @"" } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithDescription:(NSString *)description
                                                         page:(NSInteger)page
                                                   completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"description": description ?: @"" } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithPersonId:(NSString *)personId
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"personIds": @[ personId ?: @"" ] } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithPersonId:(NSString *)personId
                                                      page:(NSInteger)page
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"personIds": @[ personId ?: @"" ] } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithCity:(NSString *)city
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"city": city ?: @"" } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithCity:(NSString *)city
                                                  page:(NSInteger)page
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"city": city ?: @"" } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithMake:(NSString *)make
                                                  page:(NSInteger)page
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"make": make ?: @"" } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithModel:(NSString *)model
                                                   page:(NSInteger)page
                                             completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"model": model ?: @"" } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithLensModel:(NSString *)lensModel
                                                       page:(NSInteger)page
                                                 completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"lensModel": lensModel ?: @"" } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithTagId:(NSString *)tagId
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"tagIds": @[ tagId ?: @"" ] } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithTagId:(NSString *)tagId
                                                page:(NSInteger)page
                                          completion:(void (^)(NSArray<IMAsset *> *, NSString *, NSError *))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"tagIds": @[ tagId ?: @"" ] } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithFavorite:(BOOL)favorite
                                                      page:(NSInteger)page
                                                completion:(void (^)(NSArray<IMAsset *> *, NSString *, NSError *))completion {
	return [self postSearch:@"/search/metadata"
	                    body:@{ @"isFavorite": @(favorite) }
	                     page:page
	              completion:completion];
}

#pragma mark - People

+ (void)peopleAtPage:(NSInteger)page
          completion:(void (^)(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error))completion {
	[self peopleAtPage:page includeHidden:NO completion:completion];
}

+ (nullable NSURLSessionTask *)peopleAtPage:(NSInteger)page
                              includeHidden:(BOOL)includeHidden
                                 completion:(void (^)(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error))completion {
	NSInteger requestPage = page < 1 ? 1 : page;
	return [[IMApiClient shared] GET:@"/people"
	                     query:@{
		                     @"size": [NSString stringWithFormat:@"%ld", (long)kIMPeoplePageSize],
		                     @"page": [NSString stringWithFormat:@"%ld", (long)requestPage],
		                     @"withHidden": includeHidden ? @"true" : @"false",
	                     }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]] || ![json[@"people"] isKindOfClass:[NSArray class]]) {
			    completion(nil, NO, error ?: IMSearchMalformedResponse());
			    return;
		    }
		    NSDictionary *dict = (NSDictionary *)json;
		    id peopleValue = IMValueOrNil(dict[@"people"]);
		    NSArray<IMPerson *> *people = [IMPerson peopleWithArray:[peopleValue isKindOfClass:[NSArray class]] ? peopleValue : @[]];
		    if (people.count != [(NSArray *)peopleValue count]) {
			    completion(nil, NO, IMSearchMalformedResponse());
			    return;
		    }
		    id hasNextValue = IMValueOrNil(dict[@"hasNextPage"]);
		    BOOL hasNext;
		    if ([hasNextValue isKindOfClass:[NSNumber class]]) {
			    hasNext = [hasNextValue boolValue];
		    } else {
			    id totalValue = IMValueOrNil(dict[@"total"]);
			    NSInteger total = [totalValue isKindOfClass:[NSNumber class]] ? [totalValue integerValue] : 0;
			    hasNext = requestPage * kIMPeoplePageSize < total;
		    }
		    if (requestPage == 1 && !includeHidden) {
			    sCachedPeople = people;
		    }
		    completion(people, hasNext, nil);
	    }];
}

+ (nullable NSURLSessionTask *)searchPeopleNamed:(NSString *)name
                                   includeHidden:(BOOL)includeHidden
                                      completion:(void (^)(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	if (!IMSearchNonEmptyString(name)) {
		NSError *inputError = IMSearchInvalidInput(_(@"A person name is required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, inputError); });
		return nil;
	}
	return [[IMApiClient shared] GET:@"/search/person"
	                          query:@{ @"name": name, @"withHidden": includeHidden ? @"true" : @"false" }
	                     completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMSearchMalformedResponse());
			return;
		}
		NSArray<IMPerson *> *people = [IMPerson peopleWithArray:json];
		if (people.count != [(NSArray *)json count]) {
			completion(nil, IMSearchMalformedResponse());
			return;
		}
		completion(people, nil);
	}];
}

+ (nullable NSURLSessionTask *)updatePersonId:(NSString *)personId
                                        name:(nullable NSString *)name
                                      hidden:(nullable NSNumber *)hidden
                                  completion:(void (^)(IMPerson *_Nullable person, NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	if (!IMSearchUUIDString(personId)) {
		NSError *inputError = IMSearchInvalidInput(_(@"A valid person ID is required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, inputError); });
		return nil;
	}
	if (name != nil && ![name isKindOfClass:[NSString class]]) {
		NSError *inputError = IMSearchInvalidInput(_(@"Person name must be text."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, inputError); });
		return nil;
	}
	if (hidden != nil && (![hidden isKindOfClass:[NSNumber class]] ||
	                     !isfinite(hidden.doubleValue) ||
	                     (hidden.doubleValue != 0.0 && hidden.doubleValue != 1.0))) {
		NSError *inputError = IMSearchInvalidInput(_(@"Person visibility must be a boolean."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, inputError); });
		return nil;
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	if (name != nil) body[@"name"] = name;
	if (hidden != nil) body[@"isHidden"] = hidden;
	NSString *path = [NSString stringWithFormat:@"/people/%@", IMSearchEscapedPathComponent(personId)];
	return [[IMApiClient shared] PUT:path body:body completion:^(id _Nullable json, NSError *_Nullable error) {
		IMPerson *person = error ? nil : [IMPerson personWithDictionary:json];
		if (!person) {
			completion(nil, error ?: [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotParseResponse userInfo:nil]);
			return;
		}
		NSMutableArray<IMPerson *> *people = [sCachedPeople mutableCopy];
		NSUInteger index = [people indexOfObjectPassingTest:^BOOL(IMPerson *candidate, NSUInteger idx, BOOL *stop) {
			return [candidate.personId isEqualToString:person.personId];
		}];
		if (people && index != NSNotFound) {
			if (person.isHidden) [people removeObjectAtIndex:index];
			else people[index] = person;
			sCachedPeople = people;
		}
		[[NSNotificationCenter defaultCenter] postNotificationName:IMPeopleDidChangeNotification object:person];
		completion(person, nil);
	}];
}

+ (void)allPeopleWithCompletion:(void (^)(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error))completion {
	[self peopleAtPage:1 completion:^(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error) {
		completion(people, error);
	}];
}

+ (NSArray<IMPerson *> *)cachedPeople {
	return sCachedPeople ?: @[];
}

+ (nullable NSURLSessionTask *)thumbnailDataForPersonId:(NSString *)personId
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	if (!IMSearchUUIDString(personId)) {
		NSError *inputError = IMSearchInvalidInput(_(@"A valid person ID is required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, inputError); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/people/%@/thumbnail", IMSearchEscapedPathComponent(personId)];
	return [[IMApiClient shared] getData:path query:nil completion:completion];
}

#pragma mark - Places

+ (nullable NSURLSessionTask *)exploreDataWithCompletion:(void (^)(NSArray<IMSearchExploreGroup *> *_Nullable groups,
                                                                    NSError *_Nullable error))completion {
	if (!completion) return nil;
	return [[IMApiClient shared] GET:@"/search/explore"
	                             query:nil
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		NSArray<IMSearchExploreGroup *> *groups = [IMSearchExploreGroup groupsWithResponseArray:json];
		completion(groups, groups ? nil : IMSearchMalformedResponse());
	}];
}

+ (nullable NSURLSessionTask *)placesNamed:(NSString *)name
                                completion:(void (^)(NSArray<IMSearchPlace *> *_Nullable places,
                                                      NSError *_Nullable error))completion {
	if (!completion) return nil;
	if (!IMSearchNonEmptyString(name)) {
		NSError *error = IMSearchInvalidInput(_(@"A place name is required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return [[IMApiClient shared] GET:@"/search/places"
	                             query:@{ @"name": trimmed }
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMSearchMalformedResponse());
			return;
		}
		NSMutableArray<IMSearchPlace *> *places = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (id raw in (NSArray *)json) {
			IMSearchPlace *place = [IMSearchPlace placeWithResponseDictionary:raw];
			if (!place) {
				completion(nil, IMSearchMalformedResponse());
				return;
			}
			[places addObject:place];
		}
		completion([places copy], nil);
	}];
}

+ (void)assetsByCityWithCompletion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                             NSArray<NSString *> *_Nullable cityNames,
                                             NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/search/cities"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSArray class]]) {
			    completion(nil, nil, error ?: IMSearchMalformedResponse());
			    return;
		    }
		    NSMutableArray<IMAsset *> *assets = [NSMutableArray array];
		    NSMutableArray<NSString *> *cities = [NSMutableArray array];
		    for (NSDictionary *dict in (NSArray *)json) {
			    if (![dict isKindOfClass:[NSDictionary class]]) {
				    continue;
			    }
			    id exifValue = IMValueOrNil(dict[@"exifInfo"]);
			    NSDictionary *exif = [exifValue isKindOfClass:[NSDictionary class]] ? exifValue : nil;
			    NSString *city = IMValueOrNil(exif[@"city"]);
			    if (city.length == 0) {
				    continue;
			    }
			    IMAsset *asset = [IMAsset assetWithResponseDictionary:dict];
			    if (!asset) {
				    continue;
			    }
			    [assets addObject:asset];
			    [cities addObject:city];
		    }
		    sCachedPlaceAssets = assets;
		    sCachedPlaceCityNames = cities;
		    completion(assets, cities, nil);
	    }];
}

+ (NSArray<IMAsset *> *)cachedPlaceAssets {
	return sCachedPlaceAssets ?: @[];
}

+ (NSArray<NSString *> *)cachedPlaceCityNames {
	return sCachedPlaceCityNames ?: @[];
}

#pragma mark - Suggestions and filtered discovery

+ (nullable NSURLSessionTask *)searchSuggestionsForType:(NSString *)type
                                               country:(nullable NSString *)country
                                                  state:(nullable NSString *)state
                                                  make:(nullable NSString *)make
                                                 model:(nullable NSString *)model
                                             lensModel:(nullable NSString *)lensModel
                                           includeNull:(BOOL)includeNull
                                            completion:(void (^)(NSArray<NSString *> *_Nullable suggestions,
                                                                  NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	NSSet<NSString *> *validTypes = [NSSet setWithObjects:
		IMSearchSuggestionTypeCountry,
		IMSearchSuggestionTypeState,
		IMSearchSuggestionTypeCity,
		IMSearchSuggestionTypeCameraMake,
		IMSearchSuggestionTypeCameraModel,
		IMSearchSuggestionTypeCameraLensModel,
		nil];
	if (![validTypes containsObject:type]) {
		NSError *error = IMSearchInvalidInput(_(@"A valid search suggestion type is required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	NSArray<NSString *> *filters = @[ country ?: (id)[NSNull null], state ?: (id)[NSNull null],
		make ?: (id)[NSNull null], model ?: (id)[NSNull null], lensModel ?: (id)[NSNull null] ];
	for (id value in filters) {
		if (value != [NSNull null] && !IMSearchNonEmptyString(value)) {
			NSError *error = IMSearchInvalidInput(_(@"Search suggestion filters cannot be empty."));
			dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
			return nil;
		}
	}
	NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithObject:
		[NSURLQueryItem queryItemWithName:@"type" value:type]];
	NSDictionary<NSString *, NSString *> *namedFilters = @{
		@"country": country ?: @"",
		@"state": state ?: @"",
		@"make": make ?: @"",
		@"model": model ?: @"",
		@"lensModel": lensModel ?: @"",
	};
	for (NSString *key in @[ @"country", @"state", @"make", @"model", @"lensModel" ]) {
		NSString *value = namedFilters[key];
		if (value.length > 0) {
			[queryItems addObject:[NSURLQueryItem queryItemWithName:key value:value]];
		}
	}
	[queryItems addObject:[NSURLQueryItem queryItemWithName:@"includeNull" value:includeNull ? @"true" : @"false"]];
	return [[IMApiClient shared] GET:@"/search/suggestions"
	                         queryItems:queryItems
	                         completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMSearchMalformedResponse());
			return;
		}
		NSMutableArray<NSString *> *suggestions = [NSMutableArray array];
		NSMutableSet<NSString *> *seen = [NSMutableSet set];
		for (id value in (NSArray *)json) {
			if ([value isKindOfClass:[NSNull class]]) {
				continue;
			}
			if (!IMSearchNonEmptyString(value)) {
				completion(nil, IMSearchMalformedResponse());
				return;
			}
			if (![seen containsObject:value]) {
				[seen addObject:value];
				[suggestions addObject:value];
			}
		}
		completion(suggestions, nil);
	}];
}

+ (nullable NSURLSessionTask *)randomAssetsWithCriteria:(nullable NSDictionary<NSString *, id> *)criteria
                                             completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                                                   NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	NSError *validationError = nil;
	NSDictionary<NSString *, id> *validated = IMSearchValidatedCriteria(criteria, YES, NO, &validationError);
	if (!validated) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, validationError); });
		return nil;
	}
	return [[IMApiClient shared] POST:@"/search/random"
	                              body:validated
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMSearchMalformedResponse());
			return;
		}
		NSArray<IMAsset *> *assets = IMSearchAssetsFromItems(json);
		completion(assets, assets ? nil : IMSearchMalformedResponse());
	}];
}

+ (nullable NSURLSessionTask *)largeAssetsWithCriteria:(nullable NSDictionary<NSString *, id> *)criteria
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                                                  NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	NSError *validationError = nil;
	NSDictionary<NSString *, id> *validated = IMSearchValidatedCriteria(criteria, NO, NO, &validationError);
	if (!validated) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, validationError); });
		return nil;
	}
	NSArray<NSURLQueryItem *> *queryItems = IMSearchQueryItemsFromCriteria(validated);
	return [[IMApiClient shared] POST:@"/search/large-assets"
	                         queryItems:queryItems
	                               body:nil
	                         completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMSearchMalformedResponse());
			return;
		}
		NSArray<IMAsset *> *assets = IMSearchAssetsFromItems(json);
		completion(assets, assets ? nil : IMSearchMalformedResponse());
	}];
}

+ (nullable NSURLSessionTask *)searchStatisticsWithCriteria:(nullable NSDictionary<NSString *, id> *)criteria
                                                  completion:(void (^)(IMSearchStatistics *_Nullable statistics,
                                                                        NSError *_Nullable error))completion {
	if (!completion) {
		return nil;
	}
	NSError *validationError = nil;
	NSDictionary<NSString *, id> *validated = IMSearchValidatedCriteria(criteria, NO, YES, &validationError);
	if (!validated) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, validationError); });
		return nil;
	}
	return [[IMApiClient shared] POST:@"/search/statistics"
	                              body:validated
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMSearchStatistics *statistics = [IMSearchStatistics statisticsWithDictionary:json];
		completion(statistics, statistics ? nil : IMSearchMalformedResponse());
	}];
}

@end
