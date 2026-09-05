#import "IMAlbumApi.h"
#import "IMApiClient.h"
#import "common.h"
#include <limits.h>
#include <math.h>
#include <string.h>

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static NSError *IMAlbumMalformedResponse(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The server returned an invalid album response.")}];
}

static NSError *IMAlbumValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The album request is invalid.")}];
}

static BOOL IMAlbumIdentifierIsValid(id value) {
	if (![value isKindOfClass:[NSString class]]) {
		return NO;
	}
	NSString *identifier = (NSString *)value;
	return [identifier stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

static BOOL IMAlbumOrderIsValid(id value) {
	if (value == nil) {
		return YES;
	}
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
		return NO;
	}
	return [(NSString *)value isEqualToString:@"asc"] || [(NSString *)value isEqualToString:@"desc"];
}

static NSArray<NSString *> *_Nullable IMAlbumValidatedAssetIds(id value) {
	if (![value isKindOfClass:[NSArray class]] || [(NSArray *)value count] == 0) {
		return nil;
	}
	NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
	for (id raw in (NSArray *)value) {
		if (!IMAlbumIdentifierIsValid(raw)) {
			return nil;
		}
		NSString *identifier = [(NSString *)raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		[ids addObject:identifier];
	}
	return [ids copy];
}

static NSString *IMAlbumPathComponent(NSString *value) {
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
	    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static BOOL IMAlbumParseNextPage(id rawValue, NSInteger *nextPage, BOOL *hasNextPage) {
	if (nextPage) *nextPage = 0;
	if (hasNextPage) *hasNextPage = NO;
	if (rawValue == nil || [rawValue isKindOfClass:[NSNull class]]) {
		return YES;
	}
	if ([rawValue isKindOfClass:[NSString class]]) {
		NSString *token = (NSString *)rawValue;
		if (token.length == 0) {
			return YES;
		}
		NSScanner *scanner = [NSScanner scannerWithString:token];
		scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@""];
		unsigned long long value = 0;
		if (![scanner scanUnsignedLongLong:&value] || !scanner.isAtEnd || value == 0 || value > (unsigned long long)NSIntegerMax) {
			return NO;
		}
		if (nextPage) *nextPage = (NSInteger)value;
		if (hasNextPage) *hasNextPage = YES;
		return YES;
	}
	if (![rawValue isKindOfClass:[NSNumber class]]) {
		return NO;
	}
	const char *type = [(NSNumber *)rawValue objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) {
		return NO;
	}
	double numeric = [(NSNumber *)rawValue doubleValue];
	if (!isfinite(numeric) || numeric < 1.0 || floor(numeric) != numeric || numeric > (double)NSIntegerMax) {
		return NO;
	}
	if (nextPage) *nextPage = [(NSNumber *)rawValue integerValue];
	if (hasNextPage) *hasNextPage = YES;
	return YES;
}

static NSError *IMAlbumBulkResponseShapeError(id json, NSArray<NSString *> *requestedIds) {
	if (![json isKindOfClass:[NSArray class]] || ![requestedIds isKindOfClass:[NSArray class]] ||
	    [(NSArray *)json count] != requestedIds.count) {
		return IMAlbumMalformedResponse(_(@"The server returned an invalid album update response."));
	}
	NSMutableDictionary<NSString *, NSNumber *> *expectedCounts = [NSMutableDictionary dictionaryWithCapacity:requestedIds.count];
	for (NSString *requestedId in requestedIds) {
		NSUInteger count = [expectedCounts[requestedId] unsignedIntegerValue];
		expectedCounts[requestedId] = @(count + 1);
	}
	for (id raw in (NSArray *)json) {
		if (![raw isKindOfClass:[NSDictionary class]]) {
			return IMAlbumMalformedResponse(_(@"The server returned an invalid album update response."));
		}
		NSDictionary *entry = (NSDictionary *)raw;
		id identifier = entry[@"id"];
		if (![identifier isKindOfClass:[NSString class]] || [identifier length] == 0 ||
		    ![entry[@"success"] isKindOfClass:[NSNumber class]] || expectedCounts[identifier] == nil) {
			return IMAlbumMalformedResponse(_(@"The server returned an invalid album update response."));
		}
		NSUInteger remaining = [expectedCounts[identifier] unsignedIntegerValue];
		if (remaining == 0) {
			return IMAlbumMalformedResponse(_(@"The server returned an invalid album update response."));
		}
		if (remaining == 1) {
			[expectedCounts removeObjectForKey:identifier];
		} else {
			expectedCounts[identifier] = @(remaining - 1);
		}
	}
	return expectedCounts.count == 0 ? nil : IMAlbumMalformedResponse(_(@"The server returned an incomplete album update response."));
}

static BOOL IMAllBulkIdsSucceeded(id json, NSArray<NSString *> *requestedIds) {
	if (IMAlbumBulkResponseShapeError(json, requestedIds) != nil) {
		return NO;
	}
	for (NSDictionary *entry in (NSArray *)json) {
		if (![entry[@"success"] boolValue]) {
			return NO;
		}
	}
	return YES;
}

@interface IMAlbumAssetsTask ()
@property (atomic) BOOL cancelled;
@property (atomic, strong, nullable) NSURLSessionTask *currentTask;
@end

@implementation IMAlbumAssetsTask

- (void)cancel {
	self.cancelled = YES;
	[self.currentTask cancel];
}

@end

@implementation IMAlbumApi

static NSArray<IMAlbum *> *sCachedAlbums;

#pragma mark - Album CRUD

+ (void)allAlbumsWithCompletion:(void (^)(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/albums"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSArray class]]) {
			    completion(nil, error ?: IMAlbumMalformedResponse(nil));
			    return;
		    }
		    NSArray *rawAlbums = (NSArray *)json;
		    NSArray<IMAlbum *> *albums = [IMAlbum albumsWithArray:rawAlbums];
		    if (albums.count != rawAlbums.count) {
			    completion(nil, IMAlbumMalformedResponse(_(@"The server returned an invalid album list.")));
			    return;
		    }
		    sCachedAlbums = albums;
		    completion(albums, nil);
	    }];
}

+ (NSArray<IMAlbum *> *)cachedAlbums {
	return sCachedAlbums ?: @[];
}

+ (void)statisticsWithCompletion:(void (^)(IMAlbumStatistics *_Nullable statistics,
                                            NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/albums/statistics"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    IMAlbumStatistics *statistics = [IMAlbumStatistics statisticsWithDictionary:json];
		    completion(statistics, statistics ? nil : IMAlbumMalformedResponse(_(@"The server returned invalid album statistics.")));
	}];
}

+ (void)mapMarkersForAlbumId:(NSString *)albumId
	                         key:(nullable NSString *)key
	                        slug:(nullable NSString *)slug
	                  completion:(void (^)(NSArray<IMMapMarker *> *_Nullable markers,
	                                        NSError *_Nullable error))completion {
	if (!IMAlbumIdentifierIsValid(albumId)) {
		completion(nil, IMAlbumValidationError(_(@"An album ID is required.")));
		return;
	}
	for (NSString *value in @[ key ?: @"", slug ?: @""]) {
		if ([value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) {
			completion(nil, IMAlbumValidationError(_(@"The album link contains invalid characters.")));
			return;
		}
	}
	NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
	if (key.length > 0) query[@"key"] = key;
	if (slug.length > 0) query[@"slug"] = slug;
	NSString *path = [NSString stringWithFormat:@"/albums/%@/map-markers", IMAlbumPathComponent(albumId)];
	[[IMApiClient shared] GET:path query:query.count ? query : nil completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMAlbumMalformedResponse(_(@"The server returned an invalid album map.")));
			return;
		}
		NSMutableArray<IMMapMarker *> *markers = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (id raw in (NSArray *)json) {
			IMMapMarker *marker = [IMMapMarker markerWithDictionary:raw];
			if (!marker) {
				completion(nil, IMAlbumMalformedResponse(_(@"The server returned an invalid album map.")));
				return;
			}
			[markers addObject:marker];
		}
		completion([markers copy], nil);
	}];
}

+ (void)albumForId:(NSString *)albumId completion:(void (^)(IMAlbum *, NSError *))completion {
	if (!IMAlbumIdentifierIsValid(albumId)) {
		completion(nil, IMAlbumValidationError(_(@"An album ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/albums/%@", IMAlbumPathComponent(albumId)];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMAlbum *album = [IMAlbum albumWithDictionary:json];
		completion(album, album ? nil : IMAlbumMalformedResponse(nil));
	}];
}

+ (void)createAlbumWithName:(NSString *)name
                   completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion {
	if (![name isKindOfClass:[NSString class]] ||
	    [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
		completion(nil, IMAlbumValidationError(_(@"An album name is required.")));
		return;
	}
	[[IMApiClient shared] POST:@"/albums"
	                       body:@{ @"albumName": name }
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    IMAlbum *album = [IMAlbum albumWithDictionary:json];
		    completion(album, album ? nil : IMAlbumMalformedResponse(nil));
	    }];
}

+ (void)renameAlbumId:(NSString *)albumId
                   name:(NSString *)name
             completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion {
	if (!IMAlbumIdentifierIsValid(albumId) || ![name isKindOfClass:[NSString class]] ||
	    [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
		completion(nil, IMAlbumValidationError(_(@"An album ID and name are required.")));
		return;
	}
	[self updateAlbumId:albumId fields:@{ @"albumName": name ?: @"" } completion:completion];
}

+ (void)updateAlbumId:(NSString *)albumId
               fields:(NSDictionary<NSString *,id> *)fields
           completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion {
	if (!IMAlbumIdentifierIsValid(albumId) || ![fields isKindOfClass:[NSDictionary class]] || fields.count == 0 ||
	    ![NSJSONSerialization isValidJSONObject:fields]) {
		completion(nil, IMAlbumValidationError(_(@"An album ID and valid update fields are required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/albums/%@", IMAlbumPathComponent(albumId)];
	[[IMApiClient shared] PATCH:path
	                        body:fields
	                  completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
			IMAlbum *album = [IMAlbum albumWithDictionary:json];
			completion(album, album ? nil : [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid album.")}]);
	    }];
}

+ (void)deleteAlbumId:(NSString *)albumId completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (!IMAlbumIdentifierIsValid(albumId)) {
		completion(NO, IMAlbumValidationError(_(@"An album ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/albums/%@", IMAlbumPathComponent(albumId)];
	[[IMApiClient shared] DELETE:path
	                         body:nil
	                   completion:^(id _Nullable json, NSError *_Nullable error) {
		    completion(error == nil, error);
	    }];
}

#pragma mark - Contents

static const NSInteger kIMAlbumAssetsPageSize = 1000;
static const NSInteger kIMAlbumAssetsMaxPages = 100;

+ (IMAlbumAssetsTask *)assetsInAlbumId:(NSString *)albumId
                                  order:(nullable NSString *)order
                             completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	IMAlbumAssetsTask *task = [[IMAlbumAssetsTask alloc] init];
	if (!IMAlbumIdentifierIsValid(albumId) || !IMAlbumOrderIsValid(order)) {
		NSError *error = !IMAlbumIdentifierIsValid(albumId)
		    ? IMAlbumValidationError(_(@"An album ID is required."))
		    : IMAlbumValidationError(_(@"Album order must be asc or desc."));
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!task.cancelled) completion(nil, error);
		});
		return task;
	}
	[self fetchAlbumAssetsPage:1
	                   albumId:albumId
	                     order:order
	               accumulated:[NSMutableArray array]
	                      task:task
	                completion:completion];
	return task;
}

+ (void)fetchAlbumAssetsPage:(NSInteger)page
                     albumId:(NSString *)albumId
                       order:(nullable NSString *)order
                 accumulated:(NSMutableArray<IMAsset *> *)accumulated
                        task:(IMAlbumAssetsTask *)task
	                  completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	if (task.cancelled) {
		return;
	}
	if (!IMAlbumIdentifierIsValid(albumId) || page < 1) {
		completion(nil, IMAlbumValidationError(_(@"The album paging request is invalid.")));
		return;
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
		@"albumIds": @[ albumId ],
		@"page": @(page),
		@"size": @(kIMAlbumAssetsPageSize),
	}];
	if (order.length > 0) {
		body[@"order"] = order;
	}
	task.currentTask = [[IMApiClient shared] POST:@"/search/metadata"
	                                          body:body
	                                    completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (task.cancelled) {
			    return;
		    }
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error ?: IMAlbumMalformedResponse(nil));
			    return;
		    }
		    id assetsValue = IMValueOrNil(((NSDictionary *)json)[@"assets"]);
		    NSDictionary *assetsDict = [assetsValue isKindOfClass:[NSDictionary class]] ? assetsValue : nil;
		    id items = IMValueOrNil(assetsDict[@"items"]);
		    if (assetsDict == nil || ![items isKindOfClass:[NSArray class]]) {
			    completion(nil, IMAlbumMalformedResponse(_(@"The server returned invalid album contents.")));
			    return;
		    }
		    NSArray *rawItems = (NSArray *)items;
		    NSArray<IMAsset *> *pageAssets = [IMAsset assetsWithResponseArray:rawItems];
		    if (pageAssets.count != rawItems.count) {
			    completion(nil, IMAlbumMalformedResponse(_(@"The server returned invalid album contents.")));
			    return;
		    }
		    id countValue = IMValueOrNil(assetsDict[@"count"]);
		    if (countValue != nil && (![countValue isKindOfClass:[NSNumber class]] ||
		                              !isfinite([(NSNumber *)countValue doubleValue]) ||
		                              floor([(NSNumber *)countValue doubleValue]) != [(NSNumber *)countValue doubleValue] ||
		                              [(NSNumber *)countValue integerValue] != (NSInteger)rawItems.count ||
		                              [(NSNumber *)countValue integerValue] < 0)) {
			    completion(nil, IMAlbumMalformedResponse(_(@"The server returned invalid album paging data.")));
			    return;
		    }
		    [accumulated addObjectsFromArray:pageAssets];
		    id nextPage = IMValueOrNil(assetsDict[@"nextPage"]);
		    NSInteger next = 0;
		    BOOL hasNext = NO;
		    if (!IMAlbumParseNextPage(nextPage, &next, &hasNext)) {
			    completion(nil, IMAlbumMalformedResponse(_(@"The server returned invalid album paging data.")));
			    return;
		    }
		    if (hasNext && next != page + 1) {
			    completion(nil, IMAlbumMalformedResponse(_(@"The server returned invalid album paging data.")));
			    return;
		    }
		    if (hasNext && (pageAssets.count == 0 || page >= kIMAlbumAssetsMaxPages)) {
			    completion(nil, IMAlbumMalformedResponse(_(@"The server returned invalid album paging data.")));
			    return;
		    }
		    if (hasNext) {
			    [self fetchAlbumAssetsPage:next
			                       albumId:albumId
			                         order:order
			                   accumulated:accumulated
			                          task:task
			                    completion:completion];
			    return;
		    }
		    completion([accumulated copy], nil);
	    }];
}

+ (nullable NSURLSessionTask *)assetsInAlbumId:(NSString *)albumId
                                    completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	[self assetsInAlbumId:albumId order:nil completion:completion];
	return nil;
}

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
          toAlbumId:(NSString *)albumId
         completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSArray<NSString *> *ids = IMAlbumValidatedAssetIds(assetIds);
	if (!IMAlbumIdentifierIsValid(albumId) || ids.count == 0) {
		completion(NO, IMAlbumValidationError(_(@"Choose an album and at least one photo.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/albums/%@/assets", IMAlbumPathComponent(albumId)];
	[[IMApiClient shared] PUT:path
	                      body:@{ @"ids": ids }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    NSError *responseError = error ?: (IMAllBulkIdsSucceeded(json, ids)
		        ? nil
		        : IMAlbumMalformedResponse(_(@"The server returned an invalid album update response.")));
		    completion(responseError == nil, responseError);
	}];
}

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
       toAlbumIds:(NSArray<NSString *> *)albumIds
       completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSArray<NSString *> *assetIDs = IMAlbumValidatedAssetIds(assetIds);
	NSArray<NSString *> *albumIDs = IMAlbumValidatedAssetIds(albumIds);
	if (assetIDs.count == 0 || albumIDs.count == 0) {
		completion(NO, IMAlbumValidationError(_(@"Choose at least one photo and album.")));
		return;
	}
	[[IMApiClient shared] PUT:@"/albums/assets"
	                      body:@{ @"albumIds": albumIDs, @"assetIds": assetIDs }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]] ||
		    ![json[@"success"] isKindOfClass:[NSNumber class]]) {
			completion(NO, IMAlbumMalformedResponse(_(@"The server returned an invalid multi-album response.")));
			return;
		}
		BOOL success = [json[@"success"] boolValue];
		id reason = IMValueOrNil(json[@"error"]);
		if (reason && (![reason isKindOfClass:[NSString class]] ||
		               ![@[ @"duplicate", @"no_permission", @"not_found", @"unknown", @"validation" ] containsObject:reason])) {
			completion(NO, IMAlbumMalformedResponse(_(@"The server returned an invalid multi-album error.")));
			return;
		}
		if (!success) {
			NSString *message = [reason isKindOfClass:[NSString class]] ? reason : _(@"The server could not add the photos to the albums.");
			completion(NO, IMAlbumValidationError(message));
			return;
		}
		completion(YES, nil);
	}];
}

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
          toAlbumId:(NSString *)albumId
 detailedCompletion:(void (^)(NSInteger added, NSInteger duplicates, NSInteger failed, NSError *_Nullable error))completion {
	NSArray<NSString *> *ids = IMAlbumValidatedAssetIds(assetIds);
	NSUInteger inputCount = [assetIds isKindOfClass:[NSArray class]] ? [(NSArray *)assetIds count] : 0;
	if (!IMAlbumIdentifierIsValid(albumId) || ids.count == 0) {
		completion(0, 0, (NSInteger)inputCount, IMAlbumValidationError(_(@"Choose an album and at least one photo.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/albums/%@/assets", IMAlbumPathComponent(albumId)];
	[[IMApiClient shared] PUT:path
	                      body:@{ @"ids": ids }
		                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(0, 0, (NSInteger)ids.count, error ?: IMAlbumMalformedResponse(_(@"The server returned an invalid album update response.")));
			    return;
		    }
		    NSError *shapeError = IMAlbumBulkResponseShapeError(json, ids);
		    if (shapeError) {
			    completion(0, 0, (NSInteger)ids.count, shapeError);
			    return;
		    }
		    NSInteger added = 0, duplicates = 0, failed = 0;
		    for (NSDictionary *entry in (NSArray *)json) {
			    if (![entry isKindOfClass:[NSDictionary class]]) {
				    failed++;
				    continue;
			    }
			    if ([entry[@"success"] isEqual:@YES]) {
				    added++;
				    continue;
			    }
			    id reason = IMValueOrNil(entry[@"error"]);
			    if ([reason isKindOfClass:[NSString class]] && [reason isEqualToString:@"duplicate"]) {
				    duplicates++;
			    } else {
				    failed++;
			    }
		    }
		    if (added > 0) {
			    [self adjustCachedAssetCountForAlbumId:albumId delta:added];
		    }
		    completion(added, duplicates, failed, nil);
	    }];
}

+ (void)removeAssetIds:(NSArray<NSString *> *)assetIds
          fromAlbumId:(NSString *)albumId
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSArray<NSString *> *ids = IMAlbumValidatedAssetIds(assetIds);
	if (!IMAlbumIdentifierIsValid(albumId) || ids.count == 0) {
		completion(NO, IMAlbumValidationError(_(@"Choose an album and at least one photo.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/albums/%@/assets", IMAlbumPathComponent(albumId)];
	[[IMApiClient shared] DELETE:path
	                         body:@{ @"ids": ids }
	                   completion:^(id _Nullable json, NSError *_Nullable error) {
		    NSError *responseError = error ?: (IMAllBulkIdsSucceeded(json, ids)
		        ? nil
		        : IMAlbumMalformedResponse(_(@"The server returned an invalid album update response.")));
		    completion(responseError == nil, responseError);
	    }];
}

#pragma mark - Cache maintenance

+ (void)adjustCachedAssetCountForAlbumId:(NSString *)albumId delta:(NSInteger)delta {
	if (delta == 0 || sCachedAlbums.count == 0) {
		return;
	}
	NSMutableArray<IMAlbum *> *updated = [sCachedAlbums mutableCopy];
	for (NSUInteger i = 0; i < updated.count; i++) {
		if ([updated[i].albumId isEqualToString:albumId]) {
			updated[i] = [updated[i] albumByAdjustingAssetCount:delta];
			break;
		}
	}
	sCachedAlbums = updated;
}

@end
