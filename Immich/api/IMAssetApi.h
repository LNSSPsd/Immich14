#import <Foundation/Foundation.h>
#import "IMAsset.h"
#import "IMAssetDetail.h"
#import "IMOcrLine.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMAssetMediaSizeThumbnail;
extern NSString *const IMAssetMediaSizePreview;

@interface IMAssetApi : NSObject

+ (void)timeBucketsWithCompletion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                            NSArray<NSNumber *> *_Nullable counts,
                                            NSError *_Nullable error))completion;

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)thumbnailDataForAssetId:(NSString *)assetId
                                                    size:(NSString *)size
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)originalDataForAssetId:(NSString *)assetId
                                            completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)videoPlaybackDataForAssetId:(NSString *)assetId
                                                 completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (void)assetDetailForAssetId:(NSString *)assetId
                    completion:(void (^)(IMAssetDetail *_Nullable detail, NSError *_Nullable error))completion;

+ (void)ocrLinesForAssetId:(NSString *)assetId
                 completion:(void (^)(NSArray<IMOcrLine *> *_Nullable lines, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
