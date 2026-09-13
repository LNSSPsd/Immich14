#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPhotoLibrary : NSObject

+ (instancetype)shared;

- (void)requestAuthorizationWithCompletion:(void (^)(BOOL granted))completion;

- (NSInteger)totalAssetCount;

- (NSArray<PHAsset *> *)allAssets;

- (PHFetchResult<PHAsset *> *)fetchAllAssets;

- (void)prepareForRequests;

- (void)cancelOutstandingRequests;

- (void)checksumsForAsset:(PHAsset *)asset
                completion:(void (^)(NSArray<NSString *> *_Nullable checksums,
                                      NSString *_Nullable filename,
                                      NSError *_Nullable error))completion;

- (nullable PHAssetResource *)uploadResourceForAsset:(PHAsset *)asset;

- (nullable PHAssetResource *)pairedVideoResourceForAsset:(PHAsset *)asset;

- (void)streamResource:(PHAssetResource *)resource
          chunkHandler:(void (^)(NSData *chunk))chunkHandler
            completion:(void (^)(NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
