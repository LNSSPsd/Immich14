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

@end
