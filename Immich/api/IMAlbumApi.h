#import <Foundation/Foundation.h>
#import "IMAlbum.h"
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbumAssetsTask : NSObject
- (void)cancel;
@end

@interface IMAlbumApi : NSObject

+ (void)allAlbumsWithCompletion:(void (^)(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error))completion;

+ (NSArray<IMAlbum *> *)cachedAlbums;

+ (void)createAlbumWithName:(NSString *)name
                   completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion;

+ (void)renameAlbumId:(NSString *)albumId
                   name:(NSString *)name
             completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion;

+ (void)deleteAlbumId:(NSString *)albumId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (IMAlbumAssetsTask *)assetsInAlbumId:(NSString *)albumId
                                  order:(nullable NSString *)order
                             completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)assetsInAlbumId:(NSString *)albumId
                                    completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
          toAlbumId:(NSString *)albumId
         completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
          toAlbumId:(NSString *)albumId
 detailedCompletion:(void (^)(NSInteger added, NSInteger duplicates, NSInteger failed, NSError *_Nullable error))completion;

+ (void)removeAssetIds:(NSArray<NSString *> *)assetIds
          fromAlbumId:(NSString *)albumId
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)adjustCachedAssetCountForAlbumId:(NSString *)albumId delta:(NSInteger)delta;

@end

NS_ASSUME_NONNULL_END
