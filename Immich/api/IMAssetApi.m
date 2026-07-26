#import "IMAssetApi.h"
#import "IMApiClient.h"

NSString *const IMAssetMediaSizeThumbnail = @"thumbnail";
NSString *const IMAssetMediaSizePreview = @"preview";

@implementation IMAssetApi

+ (void)timeBucketsWithCompletion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                            NSArray<NSNumber *> *_Nullable counts,
                                            NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/timeline/buckets"
	                     query:@{ @"order": @"desc", @"orderBy": @"takenAt" }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSArray class]]) {
			    completion(nil, nil, error);
			    return;
		    }
		    NSArray *buckets = (NSArray *)json;
		    NSMutableArray<NSString *> *dates = [NSMutableArray arrayWithCapacity:buckets.count];
		    NSMutableArray<NSNumber *> *counts = [NSMutableArray arrayWithCapacity:buckets.count];
		    for (NSDictionary *bucket in buckets) {
			    if (![bucket isKindOfClass:[NSDictionary class]]) {
				    continue;
			    }
			    NSString *timeBucket = bucket[@"timeBucket"];
			    NSNumber *count = bucket[@"count"];
			    if (![timeBucket isKindOfClass:[NSString class]] || ![count isKindOfClass:[NSNumber class]]) {
				    continue;
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
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(0, 0, error);
			    return;
		    }
		    NSDictionary *stats = (NSDictionary *)json;
		    NSNumber *images = stats[@"images"];
		    NSNumber *videos = stats[@"videos"];
		    completion([images isKindOfClass:[NSNumber class]] ? images.integerValue : 0,
		               [videos isKindOfClass:[NSNumber class]] ? videos.integerValue : 0,
		               nil);
	    }];
}

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/timeline/bucket"
	                     query:@{ @"timeBucket": timeBucket, @"order": @"desc", @"orderBy": @"takenAt" }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    completion([IMAsset assetsFromTimeBucketJSON:(NSDictionary *)json], nil);
	    }];
}

+ (nullable NSURLSessionTask *)thumbnailDataForAssetId:(NSString *)assetId
                                                    size:(NSString *)size
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/assets/%@/thumbnail", assetId];
	return [[IMApiClient shared] getData:path query:@{ @"size": size } completion:completion];
}

+ (nullable NSURLSessionTask *)originalDataForAssetId:(NSString *)assetId
                                            completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/assets/%@/original", assetId];
	return [[IMApiClient shared] getData:path query:nil completion:completion];
}

+ (nullable NSURLSessionTask *)videoPlaybackDataForAssetId:(NSString *)assetId
                                                 completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/assets/%@/video/playback", assetId];
	return [[IMApiClient shared] getData:path query:nil completion:completion];
}

+ (void)assetDetailForAssetId:(NSString *)assetId
                    completion:(void (^)(IMAssetDetail *_Nullable detail, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/assets/%@", assetId];
	[[IMApiClient shared] GET:path
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    completion([[IMAssetDetail alloc] initWithDictionary:(NSDictionary *)json], nil);
	    }];
}

+ (void)ocrLinesForAssetId:(NSString *)assetId
                 completion:(void (^)(NSArray<IMOcrLine *> *_Nullable lines, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/assets/%@/ocr", assetId];
	[[IMApiClient shared] GET:path
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSArray class]]) {
			    completion(nil, error);
			    return;
		    }
		    NSMutableArray<IMOcrLine *> *lines = [NSMutableArray array];
		    for (NSDictionary *dict in (NSArray *)json) {
			    IMOcrLine *line = [IMOcrLine lineWithDictionary:dict];
			    if (line) {
				    [lines addObject:line];
			    }
		    }
		    completion(lines, nil);
	    }];
}

+ (void)bulkUploadCheckWithItems:(NSArray<NSDictionary<NSString *, NSString *> *> *)items
                       completion:(void (^)(NSDictionary<NSString *, NSString *> *_Nullable actionsById,
                                             NSDictionary<NSString *, NSString *> *_Nullable matchedAssetIdsById,
                                             NSError *_Nullable error))completion {
	[[IMApiClient shared] POST:@"/assets/bulk-upload-check"
	                       body:@{ @"assets": items }
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, nil, error);
			    return;
		    }
		    NSArray *results = ((NSDictionary *)json)[@"results"];
		    if (![results isKindOfClass:[NSArray class]]) {
			    completion(nil, nil, error);
			    return;
		    }
		    NSMutableDictionary<NSString *, NSString *> *actions = [NSMutableDictionary dictionaryWithCapacity:results.count];
		    NSMutableDictionary<NSString *, NSString *> *matchedIds = [NSMutableDictionary dictionary];
		    for (NSDictionary *entry in results) {
			    if (![entry isKindOfClass:[NSDictionary class]]) {
				    continue;
			    }
			    NSString *itemId = entry[@"id"];
			    NSString *action = entry[@"action"];
			    if (![itemId isKindOfClass:[NSString class]] || ![action isKindOfClass:[NSString class]]) {
				    continue;
			    }
			    actions[itemId] = action;
			    NSString *assetId = entry[@"assetId"];
			    if ([assetId isKindOfClass:[NSString class]]) {
				    matchedIds[itemId] = assetId;
			    }
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
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    NSString *assetId = ((NSDictionary *)json)[@"id"];
		    completion([assetId isKindOfClass:[NSString class]] ? assetId : nil, nil);
	    }];
}

+ (void)setFavorite:(BOOL)favorite
       forAssetIds:(NSArray<NSString *> *)assetIds
        completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	[[IMApiClient shared] PUT:@"/assets"
	                      body:@{ @"ids": assetIds, @"isFavorite": @(favorite) }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    completion(error == nil, error);
	    }];
}

+ (void)deleteAssetIds:(NSArray<NSString *> *)assetIds
                  force:(BOOL)force
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	[[IMApiClient shared] DELETE:@"/assets"
	                         body:@{ @"ids": assetIds, @"force": @(force) }
	                   completion:^(id _Nullable json, NSError *_Nullable error) {
		    completion(error == nil, error);
	    }];
}

@end
