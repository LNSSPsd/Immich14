#import <Foundation/Foundation.h>
#import "IMAlbum.h"
#import "IMAsset.h"
#import "IMAlbumStatistics.h"
#import "IMMapMarker.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbumAssetsTask : NSObject
- (void)cancel;
@end

@interface IMAlbumApi : NSObject

+ (void)allAlbumsWithCompletion:(void (^)(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error))completion;

+ (NSArray<IMAlbum *> *)cachedAlbums;
+ (void)albumForId:(NSString *)albumId completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion;

+ (void)statisticsWithCompletion:(void (^)(IMAlbumStatistics *_Nullable statistics,
                                            NSError *_Nullable error))completion;

+ (void)mapMarkersForAlbumId:(NSString *)albumId
                         key:(nullable NSString *)key
                        slug:(nullable NSString *)slug
                  completion:(void (^)(NSArray<IMMapMarker *> *_Nullable markers,
                                        NSError *_Nullable error))completion;

+ (void)createAlbumWithName:(NSString *)name
                   completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion;

+ (void)renameAlbumId:(NSString *)albumId
                   name:(NSString *)name
             completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion;

+ (void)updateAlbumId:(NSString *)albumId
               fields:(NSDictionary<NSString *, id> *)fields
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
       toAlbumIds:(NSArray<NSString *> *)albumIds
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
