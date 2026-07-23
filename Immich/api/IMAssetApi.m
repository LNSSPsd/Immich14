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

@end
