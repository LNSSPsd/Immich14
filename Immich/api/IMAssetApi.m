#import "IMAssetApi.h"
#import "IMApiClient.h"
#import "common.h"
#import <math.h>

NSString *const IMAssetMediaSizeThumbnail = @"thumbnail";
NSString *const IMAssetMediaSizePreview = @"preview";

static NSError *IMAssetAPIError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:0
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The asset server returned an invalid response.") }];
}

static NSError *IMAssetMalformedResponse(void) {
	return IMAssetAPIError(_(@"The server returned an invalid asset response."));
}

static BOOL IMAssetIdentifierIsValid(NSString *assetId) {
	return [assetId isKindOfClass:[NSString class]] && assetId.length > 0;
}

static BOOL IMAssetUUIDv4IsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	return canonical.length == 36 && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static NSString *IMAssetPathComponent(NSString *value) {
	NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
	[allowed addCharactersInString:@"-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static BOOL IMAssetIDsAreValid(NSArray<NSString *> *assetIds) {
	if (![assetIds isKindOfClass:[NSArray class]] || assetIds.count == 0) {
		return NO;
	}
	for (id value in assetIds) {
		if (!IMAssetIdentifierIsValid(value)) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMAssetMetadataItemsAreValid(NSArray<NSDictionary<NSString *, id> *> *items) {
	if (![items isKindOfClass:[NSArray class]] || items.count == 0 ||
	    ![NSJSONSerialization isValidJSONObject:items]) {
		return NO;
	}
	for (id rawItem in items) {
		if (![rawItem isKindOfClass:[NSDictionary class]]) {
			return NO;
		}
		id key = rawItem[@"key"];
		id value = rawItem[@"value"];
		if (![key isKindOfClass:[NSString class]] || [key length] == 0 ||
		    ![value isKindOfClass:[NSDictionary class]]) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMAssetBulkMetadataDeleteItemsAreValid(NSArray<NSDictionary<NSString *, id> *> *items) {
	if (![items isKindOfClass:[NSArray class]] || items.count == 0 || ![NSJSONSerialization isValidJSONObject:items]) return NO;
	for (id rawItem in items) {
		if (![rawItem isKindOfClass:[NSDictionary class]]) return NO;
		id assetId = rawItem[@"assetId"];
		id key = rawItem[@"key"];
		if (!IMAssetIdentifierIsValid(assetId) || ![key isKindOfClass:[NSString class]] || [(NSString *)key length] == 0) return NO;
	}
	return YES;
}

static BOOL IMAssetBulkMetadataUpsertItemsAreValid(NSArray<NSDictionary<NSString *, id> *> *items) {
	if (![items isKindOfClass:[NSArray class]] || items.count == 0 || ![NSJSONSerialization isValidJSONObject:items]) return NO;
	for (id rawItem in items) {
		if (![rawItem isKindOfClass:[NSDictionary class]]) return NO;
		id assetId = rawItem[@"assetId"];
		id key = rawItem[@"key"];
		id value = rawItem[@"value"];
		if (!IMAssetIdentifierIsValid(assetId) || ![key isKindOfClass:[NSString class]] || [(NSString *)key length] == 0 ||
		    ![value isKindOfClass:[NSDictionary class]]) return NO;
	}
	return YES;
}

static BOOL IMAssetBulkMetadataResponseIsValid(id raw) {
	if (![raw isKindOfClass:[NSDictionary class]]) return NO;
	NSDictionary *item = (NSDictionary *)raw;
	return IMAssetIdentifierIsValid(item[@"assetId"]) &&
	       [item[@"key"] isKindOfClass:[NSString class]] && [(NSString *)item[@"key"] length] > 0 &&
	       [item[@"updatedAt"] isKindOfClass:[NSString class]] && [(NSString *)item[@"updatedAt"] length] > 0 &&
	       [item[@"value"] isKindOfClass:[NSDictionary class]];
}

static BOOL IMAssetMetadataResponseIsValid(id raw) {
	if (![raw isKindOfClass:[NSDictionary class]]) return NO;
	NSDictionary *item = (NSDictionary *)raw;
	return [item[@"key"] isKindOfClass:[NSString class]] && [(NSString *)item[@"key"] length] > 0 &&
	       [item[@"updatedAt"] isKindOfClass:[NSString class]] && [(NSString *)item[@"updatedAt"] length] > 0 &&
	       [item[@"value"] isKindOfClass:[NSDictionary class]];
}

static BOOL IMAssetBulkCheckItemsAreValid(NSArray<NSDictionary<NSString *, NSString *> *> *items) {
	if (![items isKindOfClass:[NSArray class]] || items.count == 0 ||
	    ![NSJSONSerialization isValidJSONObject:items]) {
		return NO;
	}
	for (id rawItem in items) {
		if (![rawItem isKindOfClass:[NSDictionary class]]) {
			return NO;
		}
		id itemId = rawItem[@"id"];
		id checksum = rawItem[@"checksum"];
		if (![itemId isKindOfClass:[NSString class]] || [itemId length] == 0 ||
		    ![checksum isKindOfClass:[NSString class]] || [checksum length] == 0) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMAssetNullOrString(id value) {
	return value == nil || [value isKindOfClass:[NSNull class]] || [value isKindOfClass:[NSString class]];
}

static BOOL IMAssetNullOrNumber(id value) {
	return value == nil || [value isKindOfClass:[NSNull class]] || [value isKindOfClass:[NSNumber class]];
}

static BOOL IMAssetDurationValueIsValid(id value) {
	if (value == nil || [value isKindOfClass:[NSNull class]]) {
		return YES;
	}
	if ([value isKindOfClass:[NSNumber class]]) {
		double number = [value doubleValue];
		return isfinite(number) && number >= 0 && floor(number) == number;
	}
	if (![value isKindOfClass:[NSString class]]) {
		return NO;
	}
	NSArray<NSString *> *parts = [(NSString *)value componentsSeparatedByString:@":"];
	if (parts.count != 3 || [parts[0] length] == 0 || [parts[1] length] == 0 || [parts[2] length] == 0) {
		return NO;
	}
	NSScanner *scanner = [NSScanner scannerWithString:parts[0]];
	NSInteger hours = 0;
	if (![scanner scanInteger:&hours] || !scanner.isAtEnd || hours < 0) {
		return NO;
	}
	scanner = [NSScanner scannerWithString:parts[1]];
	NSInteger minutes = 0;
	if (![scanner scanInteger:&minutes] || !scanner.isAtEnd || minutes < 0 || minutes >= 60) {
		return NO;
	}
	scanner = [NSScanner scannerWithString:parts[2]];
	double seconds = 0;
	if (![scanner scanDouble:&seconds] || !scanner.isAtEnd || !isfinite(seconds) || seconds < 0 || seconds >= 60) {
		return NO;
	}
	return YES;
}

static BOOL IMAssetStackTupleIsValid(id value) {
	if (value == nil || [value isKindOfClass:[NSNull class]]) {
		return YES;
	}
	if (![value isKindOfClass:[NSArray class]] || [(NSArray *)value count] != 2) {
		return NO;
	}
	id stackId = [(NSArray *)value objectAtIndex:0];
	id count = [(NSArray *)value objectAtIndex:1];
	if (![stackId isKindOfClass:[NSString class]] || [stackId length] == 0) {
		return NO;
	}
	if ([count isKindOfClass:[NSNumber class]]) {
		double number = [count doubleValue];
		return isfinite(number) && number >= 0 && floor(number) == number;
	}
	if (![count isKindOfClass:[NSString class]] || [count length] == 0) {
		return NO;
	}
	NSScanner *scanner = [NSScanner scannerWithString:count];
	NSInteger integerCount = 0;
	return [scanner scanInteger:&integerCount] && scanner.isAtEnd && integerCount >= 0;
}

static BOOL IMAssetTimeBucketResponseIsValid(NSDictionary *json) {
	if (![json isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSArray *ids = json[@"id"];
	if (![ids isKindOfClass:[NSArray class]]) {
		return NO;
	}
	NSArray<NSString *> *columnKeys = @[
		@"fileCreatedAt", @"isFavorite", @"isImage", @"duration", @"ratio",
		@"city", @"country", @"livePhotoVideoId", @"stack"
	];
	for (NSString *key in columnKeys) {
		id column = json[key];
		if (column != nil && ![column isKindOfClass:[NSArray class]]) {
			return NO;
		}
		if ([column isKindOfClass:[NSArray class]] && [column count] != ids.count) {
			return NO;
		}
	}
	for (id value in ids) {
		if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
			return NO;
		}
	}
	NSArray *fileCreatedAt = json[@"fileCreatedAt"];
	NSArray *favorite = json[@"isFavorite"];
	NSArray *image = json[@"isImage"];
	NSArray *duration = json[@"duration"];
	NSArray *ratio = json[@"ratio"];
	NSArray *city = json[@"city"];
	NSArray *country = json[@"country"];
	NSArray *livePhotoVideoId = json[@"livePhotoVideoId"];
	NSArray *stack = json[@"stack"];
	for (NSUInteger index = 0; index < ids.count; index++) {
		id created = index < fileCreatedAt.count ? fileCreatedAt[index] : nil;
		if (!IMAssetNullOrString(created)) {
			return NO;
		}
		id favoriteValue = index < favorite.count ? favorite[index] : nil;
		if (!IMAssetNullOrNumber(favoriteValue)) {
			return NO;
		}
		id imageValue = index < image.count ? image[index] : nil;
		if (!IMAssetNullOrNumber(imageValue)) {
			return NO;
		}
		id durationValue = index < duration.count ? duration[index] : nil;
		if (!IMAssetDurationValueIsValid(durationValue)) {
			return NO;
		}
		id ratioValue = index < ratio.count ? ratio[index] : nil;
		if (ratioValue != nil && ![ratioValue isKindOfClass:[NSNull class]]) {
			if (![ratioValue isKindOfClass:[NSNumber class]]) {
				return NO;
			}
			double ratioNumber = [ratioValue doubleValue];
			if (!isfinite(ratioNumber) || ratioNumber <= 0) {
				return NO;
			}
		}
		id cityValue = index < city.count ? city[index] : nil;
		if (!IMAssetNullOrString(cityValue)) {
			return NO;
		}
		id countryValue = index < country.count ? country[index] : nil;
		if (!IMAssetNullOrString(countryValue)) {
			return NO;
		}
		id liveValue = index < livePhotoVideoId.count ? livePhotoVideoId[index] : nil;
		if (!IMAssetNullOrString(liveValue)) {
			return NO;
		}
		id stackValue = index < stack.count ? stack[index] : nil;
		if (!IMAssetStackTupleIsValid(stackValue)) {
			return NO;
		}
	}
	return YES;
}

@interface IMAssetApi ()
+ (void)timeBucketsWithVisibility:(nullable NSString *)visibility
                         isTrashed:(BOOL)isTrashed
                            userId:(nullable NSString *)userId
                      withPartners:(BOOL)withPartners
                        completion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                             NSArray<NSNumber *> *_Nullable counts,
                                             NSError *_Nullable error))completion;
+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 visibility:(nullable NSString *)visibility
                  isTrashed:(BOOL)isTrashed
                     userId:(nullable NSString *)userId
               withPartners:(BOOL)withPartners
                 completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                       NSError *_Nullable error))completion;
@end

@implementation IMAssetApi

+ (void)timeBucketsWithCompletion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                            NSArray<NSNumber *> *_Nullable counts,
                                            NSError *_Nullable error))completion {
	[self timeBucketsWithVisibility:@"timeline" completion:completion];
}

+ (void)timeBucketsWithVisibility:(nullable NSString *)visibility
                       completion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                             NSArray<NSNumber *> *_Nullable counts,
                                             NSError *_Nullable error))completion {
	[self timeBucketsWithVisibility:visibility isTrashed:NO completion:completion];
}

+ (void)timeBucketsWithVisibility:(nullable NSString *)visibility
                          isTrashed:(BOOL)isTrashed
                         completion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                               NSArray<NSNumber *> *_Nullable counts,
                                               NSError *_Nullable error))completion {
	[self timeBucketsWithVisibility:visibility
	                      isTrashed:isTrashed
	                         userId:nil
	                   withPartners:NO
	                     completion:completion];
}

+ (void)timeBucketsForUserId:(NSString *)userId
                withPartners:(BOOL)withPartners
                  completion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                        NSArray<NSNumber *> *_Nullable counts,
                                        NSError *_Nullable error))completion {
	if (!IMAssetUUIDv4IsValid(userId)) {
		completion(nil, nil, IMAssetAPIError(_(@"A valid user ID is required.")));
		return;
	}
	[self timeBucketsWithVisibility:@"timeline"
	                      isTrashed:NO
	                         userId:userId
	                   withPartners:withPartners
	                     completion:completion];
}

+ (void)timeBucketsWithVisibility:(nullable NSString *)visibility
                         isTrashed:(BOOL)isTrashed
                            userId:(nullable NSString *)userId
                      withPartners:(BOOL)withPartners
                        completion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                             NSArray<NSNumber *> *_Nullable counts,
                                             NSError *_Nullable error))completion {
	if (visibility != nil && (![visibility isKindOfClass:[NSString class]] || visibility.length == 0)) {
		completion(nil, nil, IMAssetAPIError(_(@"An asset visibility is required.")));
		return;
	}
	if (userId != nil && !IMAssetUUIDv4IsValid(userId)) {
		completion(nil, nil, IMAssetAPIError(_(@"A valid user ID is required.")));
		return;
	}
	NSMutableDictionary<NSString *, NSString *> *query = [@{
		@"order": @"desc",
		@"orderBy": @"takenAt",
		@"isTrashed": isTrashed ? @"true" : @"false",
	} mutableCopy];
	if (visibility.length > 0) {
		query[@"visibility"] = visibility;
	}
	if (userId.length > 0) {
		query[@"userId"] = userId;
	}
	if (withPartners) {
		query[@"withPartners"] = @"true";
	}
	[[IMApiClient shared] GET:@"/timeline/buckets"
	                     query:query
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, nil, error);
			    return;
		    }
		    if (![json isKindOfClass:[NSArray class]]) {
			    completion(nil, nil, IMAssetMalformedResponse());
			    return;
		    }
		    NSArray *buckets = (NSArray *)json;
		    NSMutableArray<NSString *> *dates = [NSMutableArray arrayWithCapacity:buckets.count];
		    NSMutableArray<NSNumber *> *counts = [NSMutableArray arrayWithCapacity:buckets.count];
		    for (NSDictionary *bucket in buckets) {
			    if (![bucket isKindOfClass:[NSDictionary class]]) {
				    completion(nil, nil, IMAssetMalformedResponse());
				    return;
			    }
			    NSString *timeBucket = bucket[@"timeBucket"];
			    NSNumber *count = bucket[@"count"];
			    if (![timeBucket isKindOfClass:[NSString class]] || ![count isKindOfClass:[NSNumber class]]) {
				    completion(nil, nil, IMAssetMalformedResponse());
				    return;
			    }
			    [dates addObject:timeBucket];
			    [counts addObject:count];
		    }
		    completion(dates, counts, nil);
	    }];
}

+ (void)assetStatisticsWithCompletion:(void (^)(NSInteger images, NSInteger videos, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/assets/statistics"
	                     query:@{ @"visibility": @"timeline", @"isTrashed": @"false" }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(0, 0, error);
			    return;
		    }
		    if (![json isKindOfClass:[NSDictionary class]]) {
			    completion(0, 0, IMAssetMalformedResponse());
			    return;
		    }
		    NSDictionary *stats = (NSDictionary *)json;
		    NSNumber *images = stats[@"images"];
		    NSNumber *videos = stats[@"videos"];
		    NSNumber *total = stats[@"total"];
		    if (![images isKindOfClass:[NSNumber class]] ||
		        ![videos isKindOfClass:[NSNumber class]] ||
		        ![total isKindOfClass:[NSNumber class]]) {
			    completion(0, 0, IMAssetMalformedResponse());
			    return;
		    }
		    completion(images.integerValue, videos.integerValue, nil);
	    }];
}

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	[self assetsInTimeBucket:timeBucket visibility:@"timeline" completion:completion];
}

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                visibility:(nullable NSString *)visibility
                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	[self assetsInTimeBucket:timeBucket visibility:visibility isTrashed:NO completion:completion];
}

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 visibility:(nullable NSString *)visibility
                 isTrashed:(BOOL)isTrashed
                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	[self assetsInTimeBucket:timeBucket
	               visibility:visibility
	               isTrashed:isTrashed
	                  userId:nil
	            withPartners:NO
	              completion:completion];
}

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 forUserId:(NSString *)userId
              withPartners:(BOOL)withPartners
                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                      NSError *_Nullable error))completion {
	if (!IMAssetUUIDv4IsValid(userId)) {
		completion(nil, IMAssetAPIError(_(@"A valid user ID is required.")));
		return;
	}
	[self assetsInTimeBucket:timeBucket
	               visibility:@"timeline"
	               isTrashed:NO
	                  userId:userId
	            withPartners:withPartners
	              completion:completion];
}

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 visibility:(nullable NSString *)visibility
                  isTrashed:(BOOL)isTrashed
                     userId:(nullable NSString *)userId
               withPartners:(BOOL)withPartners
                 completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                       NSError *_Nullable error))completion {
	if (![timeBucket isKindOfClass:[NSString class]] || timeBucket.length == 0 ||
	    (visibility != nil && (![visibility isKindOfClass:[NSString class]] || visibility.length == 0))) {
		completion(nil, IMAssetAPIError(visibility ? _(@"A time bucket and asset visibility are required.") : _(@"A time bucket is required.")));
		return;
	}
	if (userId != nil && !IMAssetUUIDv4IsValid(userId)) {
		completion(nil, IMAssetAPIError(_(@"A valid user ID is required.")));
		return;
	}
	NSMutableDictionary<NSString *, NSString *> *query = [@{
		@"timeBucket": timeBucket,
		@"order": @"desc",
		@"orderBy": @"takenAt",
		@"isTrashed": isTrashed ? @"true" : @"false",
	} mutableCopy];
	if (visibility.length > 0) {
		query[@"visibility"] = visibility;
	}
	if (userId.length > 0) {
		query[@"userId"] = userId;
	}
	if (withPartners) {
		query[@"withPartners"] = @"true";
	}
	[[IMApiClient shared] GET:@"/timeline/bucket"
	                     query:query
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    if (!IMAssetTimeBucketResponseIsValid(json)) {
			    completion(nil, IMAssetMalformedResponse());
			    return;
		    }
		    completion([IMAsset assetsFromTimeBucketJSON:(NSDictionary *)json], nil);
	    }];
}

+ (nullable NSURLSessionTask *)thumbnailDataForAssetId:(NSString *)assetId
                                                    size:(NSString *)size
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	return [self thumbnailDataForAssetId:assetId size:size edited:NO completion:completion];
}

+ (nullable NSURLSessionTask *)thumbnailDataForAssetId:(NSString *)assetId
                                                    size:(NSString *)size
                                                   edited:(BOOL)edited
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId) || ![size isKindOfClass:[NSString class]] || size.length == 0) {
		completion(nil, IMAssetAPIError(_(@"An asset ID and thumbnail size are required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/thumbnail", IMAssetPathComponent(assetId)];
	NSDictionary *query = edited ? @{ @"size": size, @"edited": @"true" } : @{ @"size": size };
	return [[IMApiClient shared] getData:path query:query completion:completion];
}

+ (nullable NSURLSessionTask *)originalDataForAssetId:(NSString *)assetId
                                            completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	return [self originalDataForAssetId:assetId edited:NO completion:completion];
}

+ (nullable NSURLSessionTask *)originalDataForAssetId:(NSString *)assetId
                                               edited:(BOOL)edited
                                          completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/original", IMAssetPathComponent(assetId)];
	return [[IMApiClient shared] getData:path query:edited ? @{ @"edited": @"true" } : nil completion:completion];
}

+ (nullable NSURLSessionTask *)originalFileForAssetId:(NSString *)assetId
                                                edited:(BOOL)edited
                                       destinationURL:(NSURL *)destinationURL
                                           completion:(void (^)(NSURL *_Nullable fileURL, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/original", IMAssetPathComponent(assetId)];
	return [[IMApiClient shared] downloadFile:path
	                                      query:edited ? @{ @"edited": @"true" } : nil
	                             destinationURL:destinationURL
	                                  completion:completion];
}

+ (nullable NSURLSessionTask *)videoPlaybackDataForAssetId:(NSString *)assetId
                                                 completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/video/playback", IMAssetPathComponent(assetId)];
	return [[IMApiClient shared] getData:path query:nil completion:completion];
}

+ (nullable NSURLSessionTask *)videoPlaybackFileForAssetId:(NSString *)assetId
                                             destinationURL:(NSURL *)destinationURL
                                                 completion:(void (^)(NSURL *_Nullable fileURL, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/video/playback", IMAssetPathComponent(assetId)];
	return [[IMApiClient shared] downloadFile:path query:nil destinationURL:destinationURL completion:completion];
}

+ (void)assetDetailForAssetId:(NSString *)assetId
                    completion:(void (^)(IMAssetDetail *_Nullable detail, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] GET:path
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    if (![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, IMAssetMalformedResponse());
			    return;
		    }
		    IMAssetDetail *detail = [[IMAssetDetail alloc] initWithDictionary:(NSDictionary *)json];
		    if (!IMAssetIdentifierIsValid(detail.assetId)) {
			    completion(nil, IMAssetMalformedResponse());
			    return;
		    }
		    completion(detail, nil);
	    }];
}

+ (void)assetForAssetId:(NSString *)assetId
             completion:(void (^)(IMAsset *_Nullable asset, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] GET:path
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		IMAsset *asset = [IMAsset assetWithResponseDictionary:(NSDictionary *)json];
		completion(asset, asset ? nil : IMAssetMalformedResponse());
	}];
}

+ (void)updateAssetId:(NSString *)assetId
                fields:(NSDictionary<NSString *,id> *)fields
	           completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAssetIdentifierIsValid(assetId) || ![fields isKindOfClass:[NSDictionary class]] || fields.count == 0 ||
	    ![NSJSONSerialization isValidJSONObject:fields]) {
		completion(NO, IMAssetAPIError(_(@"An asset ID and at least one valid metadata field are required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] PUT:path body:fields completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]] || !IMAssetIdentifierIsValid(json[@"id"])) {
			completion(NO, IMAssetMalformedResponse());
			return;
		}
		completion(YES, nil);
	}];
}

+ (void)assetEditsForAssetId:(NSString *)assetId
                  completion:(void (^)(NSArray<IMAssetEdit *> *_Nullable edits,
                                        NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/edits", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] GET:path query:nil completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		if (!IMAssetIdentifierIsValid(((NSDictionary *)json)[@"assetId"])) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		id rawEdits = ((NSDictionary *)json)[@"edits"];
		if (![rawEdits isKindOfClass:[NSArray class]]) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		NSMutableArray<IMAssetEdit *> *parsed = [NSMutableArray arrayWithCapacity:[rawEdits count]];
		for (id raw in (NSArray *)rawEdits) {
			IMAssetEdit *edit = [IMAssetEdit editWithResponseDictionary:raw];
			if (!edit) {
				completion(nil, IMAssetMalformedResponse());
				return;
			}
			[parsed addObject:edit];
		}
		completion(parsed, nil);
	}];
}

+ (void)applyAssetEdits:(NSArray<IMAssetEdit *> *)edits
             forAssetId:(NSString *)assetId
             completion:(void (^)(NSArray<IMAssetEdit *> *_Nullable edits,
                                  NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId) || ![edits isKindOfClass:[NSArray class]] || edits.count == 0) {
		completion(nil, IMAssetAPIError(_(@"An asset ID and at least one image edit are required.")));
		return;
	}
	NSMutableArray<NSDictionary<NSString *, id> *> *items = [NSMutableArray arrayWithCapacity:edits.count];
	for (IMAssetEdit *edit in edits) {
		if (![edit isKindOfClass:[IMAssetEdit class]]) {
			completion(nil, IMAssetAPIError(_(@"The image edit is invalid.")));
			return;
		}
		[items addObject:edit.requestDictionary];
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/edits", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] PUT:path body:@{ @"edits": items } completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		if (!IMAssetIdentifierIsValid(((NSDictionary *)json)[@"assetId"])) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		id rawEdits = ((NSDictionary *)json)[@"edits"];
		if (![rawEdits isKindOfClass:[NSArray class]]) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		NSMutableArray<IMAssetEdit *> *parsed = [NSMutableArray array];
		for (id raw in (NSArray *)rawEdits) {
			IMAssetEdit *edit = [IMAssetEdit editWithResponseDictionary:raw];
			if (!edit) {
				completion(nil, IMAssetMalformedResponse());
				return;
			}
			[parsed addObject:edit];
		}
		completion(parsed, nil);
	}];
}

+ (void)removeAssetEditsForAssetId:(NSString *)assetId
                        completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(NO, IMAssetAPIError(_(@"An asset ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/edits", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] DELETE:path body:nil completion:^(id _Nullable json, NSError *_Nullable error) {
		(void)json;
		completion(error == nil, error);
	}];
}

+ (void)metadataForAssetId:(NSString *)assetId
                completion:(void (^)(NSArray<NSDictionary *> *_Nullable, NSError *_Nullable))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/metadata", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] GET:path query:nil completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
		for (id value in (NSArray *)json) {
			if (![value isKindOfClass:[NSDictionary class]] ||
			    ![value[@"key"] isKindOfClass:[NSString class]] ||
			    [value[@"key"] length] == 0 ||
			    ![value[@"value"] isKindOfClass:[NSDictionary class]] ||
			    ![value[@"updatedAt"] isKindOfClass:[NSString class]]) {
				completion(nil, IMAssetMalformedResponse());
				return;
			}
			[items addObject:value];
		}
		completion(items, nil);
	}];
}

+ (void)metadataKey:(NSString *)key
         forAssetId:(NSString *)assetId
         completion:(void (^)(NSDictionary *_Nullable metadata, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId) || ![key isKindOfClass:[NSString class]] ||
	    [(NSString *)key length] == 0 || [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
		completion(nil, IMAssetAPIError(_(@"An asset ID and metadata key are required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/metadata/%@",
	                  IMAssetPathComponent(assetId), IMAssetPathComponent(key)];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (!IMAssetMetadataResponseIsValid(json)) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		completion((NSDictionary *)json, nil);
	}];
}

+ (void)upsertMetadataForAssetId:(NSString *)assetId
                            items:(NSArray<NSDictionary<NSString *,id> *> *)items
                       completion:(void (^)(NSArray<NSDictionary *> *_Nullable, NSError *_Nullable))completion {
	if (!IMAssetIdentifierIsValid(assetId) || !IMAssetMetadataItemsAreValid(items)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID and valid metadata items are required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/metadata", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] PUT:path body:@{ @"items": items } completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		for (id value in (NSArray *)json) {
			if (![value isKindOfClass:[NSDictionary class]] ||
			    ![value[@"key"] isKindOfClass:[NSString class]] ||
			    [value[@"key"] length] == 0 ||
			    ![value[@"value"] isKindOfClass:[NSDictionary class]] ||
			    ![value[@"updatedAt"] isKindOfClass:[NSString class]]) {
				completion(nil, IMAssetMalformedResponse());
				return;
			}
		}
		completion((NSArray<NSDictionary *> *)json, nil);
	}];
}

+ (void)deleteMetadataKey:(NSString *)key
                forAssetId:(NSString *)assetId
                completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAssetIdentifierIsValid(assetId) || ![key isKindOfClass:[NSString class]] || key.length == 0) {
		completion(NO, IMAssetAPIError(_(@"An asset ID and metadata key are required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/metadata/%@",
	                  IMAssetPathComponent(assetId), IMAssetPathComponent(key)];
	[[IMApiClient shared] DELETE:path body:nil completion:^(id _Nullable json, NSError *_Nullable error) {
		(void)json;
		completion(error == nil, error);
	}];
}

+ (void)upsertBulkMetadataItems:(NSArray<NSDictionary<NSString *,id> *> *)items
                      completion:(void (^)(NSArray<NSDictionary *> *_Nullable metadata,
                                            NSError *_Nullable error))completion {
	if (!IMAssetBulkMetadataUpsertItemsAreValid(items)) {
		completion(nil, IMAssetAPIError(_(@"Choose at least one asset and valid metadata value.")));
		return;
	}
	[[IMApiClient shared] PUT:@"/assets/metadata"
	                      body:@{ @"items": items }
	                completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMAssetMalformedResponse());
			return;
		}
		NSMutableArray<NSDictionary *> *parsed = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (id value in (NSArray *)json) {
			if (!IMAssetBulkMetadataResponseIsValid(value)) {
				completion(nil, IMAssetMalformedResponse());
				return;
			}
			[parsed addObject:value];
		}
		completion([parsed copy], nil);
	}];
}

+ (void)deleteBulkMetadataItems:(NSArray<NSDictionary<NSString *,id> *> *)items
                      completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (!IMAssetBulkMetadataDeleteItemsAreValid(items)) {
		completion(NO, IMAssetAPIError(_(@"Choose at least one asset and metadata key.")));
		return;
	}
	[[IMApiClient shared] DELETE:@"/assets/metadata"
	                         body:@{ @"items": items }
	                   completion:^(id json, NSError *error) {
		(void)json;
		completion(error == nil, error);
	}];
}

+ (void)ocrLinesForAssetId:(NSString *)assetId
                 completion:(void (^)(NSArray<IMOcrLine *> *_Nullable lines, NSError *_Nullable error))completion {
	if (!IMAssetIdentifierIsValid(assetId)) {
		completion(nil, IMAssetAPIError(_(@"An asset ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@/ocr", IMAssetPathComponent(assetId)];
	[[IMApiClient shared] GET:path
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    if (![json isKindOfClass:[NSArray class]]) {
			    completion(nil, IMAssetMalformedResponse());
			    return;
		    }
		    NSMutableArray<IMOcrLine *> *lines = [NSMutableArray array];
		    for (id value in (NSArray *)json) {
			    if (![value isKindOfClass:[NSDictionary class]]) {
				    completion(nil, IMAssetMalformedResponse());
				    return;
			    }
			    NSDictionary *dict = (NSDictionary *)value;
			    IMOcrLine *line = [IMOcrLine lineWithDictionary:dict];
			    if (!line) {
				    completion(nil, IMAssetMalformedResponse());
				    return;
			    }
			    [lines addObject:line];
		    }
		    completion(lines, nil);
	    }];
}

+ (void)bulkUploadCheckWithItems:(NSArray<NSDictionary<NSString *, NSString *> *> *)items
                       completion:(void (^)(NSDictionary<NSString *, NSString *> *_Nullable actionsById,
                                             NSDictionary<NSString *, NSString *> *_Nullable matchedAssetIdsById,
                                             NSError *_Nullable error))completion {
	if (!IMAssetBulkCheckItemsAreValid(items)) {
		completion(nil, nil, IMAssetAPIError(_(@"At least one valid upload-check item is required.")));
		return;
	}
	[[IMApiClient shared] POST:@"/assets/bulk-upload-check"
	                       body:@{ @"assets": items }
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, nil, error);
			    return;
		    }
		    if (![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, nil, IMAssetMalformedResponse());
			    return;
		    }
		    NSArray *results = ((NSDictionary *)json)[@"results"];
		    if (![results isKindOfClass:[NSArray class]]) {
			    completion(nil, nil, IMAssetMalformedResponse());
			    return;
		    }
		    NSMutableDictionary<NSString *, NSString *> *actions = [NSMutableDictionary dictionaryWithCapacity:results.count];
		    NSMutableDictionary<NSString *, NSString *> *matchedIds = [NSMutableDictionary dictionary];
		    NSMutableSet<NSString *> *expectedIds = [NSMutableSet setWithCapacity:items.count];
		    for (NSDictionary *item in items) {
			    [expectedIds addObject:item[@"id"]];
		    }
		    for (id rawEntry in results) {
			    if (![rawEntry isKindOfClass:[NSDictionary class]]) {
				    completion(nil, nil, IMAssetMalformedResponse());
				    return;
			    }
			    NSDictionary *entry = (NSDictionary *)rawEntry;
			    NSString *itemId = entry[@"id"];
			    NSString *action = entry[@"action"];
			    if (![itemId isKindOfClass:[NSString class]] || ![action isKindOfClass:[NSString class]]) {
				    completion(nil, nil, IMAssetMalformedResponse());
				    return;
			    }
			    if (![expectedIds containsObject:itemId] || actions[itemId] != nil ||
			        (![action isEqualToString:@"accept"] && ![action isEqualToString:@"reject"])) {
				    completion(nil, nil, IMAssetMalformedResponse());
				    return;
			    }
			    actions[itemId] = action;
			    NSString *assetId = entry[@"assetId"];
			    if (assetId != nil && (![assetId isKindOfClass:[NSString class]] || assetId.length == 0)) {
				    completion(nil, nil, IMAssetMalformedResponse());
				    return;
			    }
			    if ([assetId isKindOfClass:[NSString class]]) {
				    matchedIds[itemId] = assetId;
			    }
		    }
		    if (actions.count != expectedIds.count ||
		        ![expectedIds isEqualToSet:[NSSet setWithArray:actions.allKeys]]) {
			    completion(nil, nil, IMAssetMalformedResponse());
			    return;
		    }
		    completion(actions, matchedIds, nil);
	    }];
}

+ (nullable NSURLSessionTask *)uploadAssetData:(NSData *)fileData
                                       filename:(NSString *)filename
                                  fileCreatedAt:(NSString *)fileCreatedAtISO8601
                                 fileModifiedAt:(NSString *)fileModifiedAtISO8601
                                     completion:(void (^)(NSString *_Nullable assetId, NSError *_Nullable error))completion {
	return [self uploadAssetData:fileData
	                     filename:filename
	                fileCreatedAt:fileCreatedAtISO8601
	               fileModifiedAt:fileModifiedAtISO8601
	             livePhotoVideoId:nil
	                   completion:completion];
}

+ (nullable NSURLSessionTask *)uploadAssetData:(NSData *)fileData
                                       filename:(NSString *)filename
                                  fileCreatedAt:(NSString *)fileCreatedAtISO8601
                               fileModifiedAt:(NSString *)fileModifiedAtISO8601
                               livePhotoVideoId:(nullable NSString *)livePhotoVideoId
	                             completion:(void (^)(NSString *_Nullable assetId, NSError *_Nullable error))completion {
	if (![fileData isKindOfClass:[NSData class]] || fileData.length == 0 ||
	    ![filename isKindOfClass:[NSString class]] || filename.length == 0 ||
	    ![fileCreatedAtISO8601 isKindOfClass:[NSString class]] || fileCreatedAtISO8601.length == 0 ||
	    ![fileModifiedAtISO8601 isKindOfClass:[NSString class]] || fileModifiedAtISO8601.length == 0 ||
	    (livePhotoVideoId != nil && (![livePhotoVideoId isKindOfClass:[NSString class]] || livePhotoVideoId.length == 0))) {
		completion(nil, IMAssetAPIError(_(@"Upload data, filename, and creation/modification dates are required.")));
		return nil;
	}
	NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionaryWithDictionary:@{
		@"filename": filename,
		@"fileCreatedAt": fileCreatedAtISO8601,
		@"fileModifiedAt": fileModifiedAtISO8601,
	}];
	if (livePhotoVideoId) {
		fields[@"livePhotoVideoId"] = livePhotoVideoId;
	}
	return [[IMApiClient shared] multipartPOST:@"/assets"
	                                     fields:fields
	                                  fileField:@"assetData"
	                                   filename:filename
	                                   fileData:fileData
	                                 completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    if (![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, IMAssetMalformedResponse());
			    return;
		    }
		    NSString *assetId = ((NSDictionary *)json)[@"id"];
		    NSString *status = ((NSDictionary *)json)[@"status"];
		    if (!IMAssetIdentifierIsValid(assetId) || ![status isKindOfClass:[NSString class]] || status.length == 0) {
			    completion(nil, IMAssetMalformedResponse());
			    return;
		    }
		    completion(assetId, nil);
	    }];
}

+ (void)setFavorite:(BOOL)favorite
       forAssetIds:(NSArray<NSString *> *)assetIds
        completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (!IMAssetIDsAreValid(assetIds)) {
		completion(NO, IMAssetAPIError(_(@"At least one valid asset ID is required.")));
		return;
	}
	[[IMApiClient shared] PUT:@"/assets"
	                      body:@{ @"ids": assetIds, @"isFavorite": @(favorite) }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    (void)json;
		    completion(error == nil, error);
	    }];
}

+ (void)deleteAssetIds:(NSArray<NSString *> *)assetIds
                  force:(BOOL)force
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (!IMAssetIDsAreValid(assetIds)) {
		completion(NO, IMAssetAPIError(_(@"At least one valid asset ID is required.")));
		return;
	}
	[[IMApiClient shared] DELETE:@"/assets"
	                         body:@{ @"ids": assetIds, @"force": @(force) }
	                   completion:^(id _Nullable json, NSError *_Nullable error) {
			    (void)json;
			    completion(error == nil, error);
	    }];
}

@end
