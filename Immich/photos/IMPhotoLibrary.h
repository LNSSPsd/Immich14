#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPhotoLibrary : NSObject

+ (instancetype)shared;

- (void)requestAuthorizationWithCompletion:(void (^)(BOOL granted))completion;

- (NSInteger)totalAssetCount;

- (NSArray<PHAsset *> *)allAssets;

- (void)checksumsForAsset:(PHAsset *)asset
                completion:(void (^)(NSArray<NSString *> *_Nullable checksums,
                                      NSString *_Nullable filename,
                                      NSError *_Nullable error))completion;

- (void)originalDataForAsset:(PHAsset *)asset
                   completion:(void (^)(NSData *_Nullable data,
                                         NSString *_Nullable filename,
                                         NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
