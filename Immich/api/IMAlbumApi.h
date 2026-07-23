#import <Foundation/Foundation.h>
#import "IMAlbum.h"
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbumApi : NSObject

+ (void)allAlbumsWithCompletion:(void (^)(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error))completion;

+ (void)createAlbumWithName:(NSString *)name
                   completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion;

+ (void)renameAlbumId:(NSString *)albumId
                   name:(NSString *)name
             completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion;

+ (void)deleteAlbumId:(NSString *)albumId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)assetsInAlbumId:(NSString *)albumId
                                    completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
          toAlbumId:(NSString *)albumId
         completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)removeAssetIds:(NSArray<NSString *> *)assetIds
          fromAlbumId:(NSString *)albumId
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
