#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMAssetJobNameRefreshFaces;
extern NSString *const IMAssetJobNameRefreshMetadata;
extern NSString *const IMAssetJobNameRegenerateThumbnail;
extern NSString *const IMAssetJobNameTranscodeVideo;

@interface IMAssetManagementApi : NSObject

+ (void)setVisibility:(NSString *)visibility
          forAssetIds:(NSArray<NSString *> *)assetIds
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)setVisibility:(NSString *)visibility
           forAssetId:(NSString *)assetId
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)restoreAssetIds:(NSArray<NSString *> *)assetIds
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)restoreAllTrashWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)emptyTrashWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)copyAssetFromId:(NSString *)sourceAssetId
              toAssetId:(NSString *)targetAssetId
                options:(nullable NSDictionary<NSString *, NSNumber *> *)options
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)runAssetJobNamed:(NSString *)jobName
             forAssetIds:(NSArray<NSString *> *)assetIds
              completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
