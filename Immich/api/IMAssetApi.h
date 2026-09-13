#import <Foundation/Foundation.h>
#import "IMAsset.h"
#import "IMAssetDetail.h"
#import "IMAssetEdit.h"
#import "IMOcrLine.h"
#import "IMApiClient.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMAssetMediaSizeThumbnail;
extern NSString *const IMAssetMediaSizePreview;

@interface IMAssetApi : NSObject

+ (void)timeBucketsWithCompletion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                            NSArray<NSNumber *> *_Nullable counts,
                                            NSError *_Nullable error))completion;

+ (void)timeBucketsWithVisibility:(nullable NSString *)visibility
                       completion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                             NSArray<NSNumber *> *_Nullable counts,
                                             NSError *_Nullable error))completion;

+ (void)timeBucketsWithVisibility:(nullable NSString *)visibility
                          isTrashed:(BOOL)isTrashed
                         completion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                               NSArray<NSNumber *> *_Nullable counts,
                                               NSError *_Nullable error))completion;

+ (void)timeBucketsForUserId:(NSString *)userId
                withPartners:(BOOL)withPartners
                  completion:(void (^)(NSArray<NSString *> *_Nullable bucketDates,
                                        NSArray<NSNumber *> *_Nullable counts,
                                        NSError *_Nullable error))completion;

+ (void)assetStatisticsWithCompletion:(void (^)(NSInteger images, NSInteger videos, NSError *_Nullable error))completion;

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                visibility:(nullable NSString *)visibility
                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                visibility:(nullable NSString *)visibility
                 isTrashed:(BOOL)isTrashed
                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (void)assetsInTimeBucket:(NSString *)timeBucket
                 forUserId:(NSString *)userId
              withPartners:(BOOL)withPartners
                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                      NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)thumbnailDataForAssetId:(NSString *)assetId
                                                    size:(NSString *)size
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)thumbnailDataForAssetId:(NSString *)assetId
                                                    size:(NSString *)size
                                                   edited:(BOOL)edited
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)originalDataForAssetId:(NSString *)assetId
                                            completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)originalDataForAssetId:(NSString *)assetId
                                               edited:(BOOL)edited
                                          completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)originalFileForAssetId:(NSString *)assetId
                                                edited:(BOOL)edited
                                       destinationURL:(NSURL *)destinationURL
                                           completion:(void (^)(NSURL *_Nullable fileURL, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)videoPlaybackDataForAssetId:(NSString *)assetId
                                                 completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)videoPlaybackFileForAssetId:(NSString *)assetId
                                             destinationURL:(NSURL *)destinationURL
                                                 completion:(void (^)(NSURL *_Nullable fileURL, NSError *_Nullable error))completion;

+ (void)assetDetailForAssetId:(NSString *)assetId
                    completion:(void (^)(IMAssetDetail *_Nullable detail, NSError *_Nullable error))completion;

+ (void)assetForAssetId:(NSString *)assetId
             completion:(void (^)(IMAsset *_Nullable asset, NSError *_Nullable error))completion;

+ (void)updateAssetId:(NSString *)assetId
                fields:(NSDictionary<NSString *, id> *)fields
            completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)assetEditsForAssetId:(NSString *)assetId
                  completion:(void (^)(NSArray<IMAssetEdit *> *_Nullable edits,
                                        NSError *_Nullable error))completion;
+ (void)applyAssetEdits:(NSArray<IMAssetEdit *> *)edits
             forAssetId:(NSString *)assetId
             completion:(void (^)(NSArray<IMAssetEdit *> *_Nullable edits,
                                  NSError *_Nullable error))completion;
+ (void)removeAssetEditsForAssetId:(NSString *)assetId
                        completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)metadataForAssetId:(NSString *)assetId
                completion:(void (^)(NSArray<NSDictionary *> *_Nullable metadata,
                                      NSError *_Nullable error))completion;
+ (void)metadataKey:(NSString *)key
         forAssetId:(NSString *)assetId
         completion:(void (^)(NSDictionary *_Nullable metadata,
                              NSError *_Nullable error))completion;
+ (void)upsertMetadataForAssetId:(NSString *)assetId
                            items:(NSArray<NSDictionary<NSString *, id> *> *)items
                       completion:(void (^)(NSArray<NSDictionary *> *_Nullable metadata,
                                             NSError *_Nullable error))completion;
+ (void)deleteMetadataKey:(NSString *)key
                forAssetId:(NSString *)assetId
                completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)upsertBulkMetadataItems:(NSArray<NSDictionary<NSString *, id> *> *)items
                      completion:(void (^)(NSArray<NSDictionary *> *_Nullable metadata,
                                            NSError *_Nullable error))completion;

+ (void)deleteBulkMetadataItems:(NSArray<NSDictionary<NSString *, id> *> *)items
                      completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)ocrLinesForAssetId:(NSString *)assetId
                 completion:(void (^)(NSArray<IMOcrLine *> *_Nullable lines, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)bulkUploadCheckWithItems:(NSArray<NSDictionary<NSString *, NSString *> *> *)items
                                              completion:(void (^)(NSDictionary<NSString *, NSString *> *_Nullable actionsById,
                                                                    NSDictionary<NSString *, NSString *> *_Nullable matchedAssetIdsById,
                                                                    NSError *_Nullable error))completion;

+ (nullable IMMultipartBodyFile *)uploadBodyWithFilename:(NSString *)filename
                                           fileCreatedAt:(NSString *)fileCreatedAtISO8601
                                          fileModifiedAt:(NSString *)fileModifiedAtISO8601
                                        livePhotoVideoId:(nullable NSString *)livePhotoVideoId
                                                   error:(NSError **)error;
+ (nullable NSURLSessionTask *)uploadAssetBody:(IMMultipartBodyFile *)body
                                    completion:(void (^)(NSString *_Nullable assetId, NSError *_Nullable error))completion;

+ (void)setFavorite:(BOOL)favorite
       forAssetIds:(NSArray<NSString *> *)assetIds
        completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)deleteAssetIds:(NSArray<NSString *> *)assetIds
                  force:(BOOL)force
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
