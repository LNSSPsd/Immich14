#import <Foundation/Foundation.h>
#import "IMSharedLink.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSharedLinkApi : NSObject
+ (nullable NSURL *)publicURLForLink:(IMSharedLink *)link;

+ (void)createLinkForAssetIds:(NSArray<NSString *> *)assetIds
 completion:(void (^)(NSURL *_Nullable url, NSError *_Nullable error))completion;
+ (void)createAlbumLinkForAlbumId:(NSString *)albumId
                         completion:(void (^)(NSURL *_Nullable url, NSError *_Nullable error))completion;

+ (void)createLinkForAssetIds:(NSArray<NSString *> *)assetIds
                      options:(nullable NSDictionary<NSString *, id> *)options
                  completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion;
+ (void)createAlbumLinkForAlbumId:(NSString *)albumId
                           options:(nullable NSDictionary<NSString *, id> *)options
                       completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion;
+ (void)allLinksWithCompletion:(void (^)(NSArray<IMSharedLink *> *_Nullable links, NSError *_Nullable error))completion;
+ (void)linkForId:(NSString *)linkId
       completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion;
+ (void)removeLinkId:(NSString *)linkId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)updateLinkId:(NSString *)linkId fields:(NSDictionary<NSString *, id> *)fields completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)updateLinkId:(NSString *)linkId
              fields:(NSDictionary<NSString *, id> *)fields
       linkCompletion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion;
+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
          toLinkId:(NSString *)linkId
         completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)removeAssetIds:(NSArray<NSString *> *)assetIds
             fromLinkId:(NSString *)linkId
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)loginWithKey:(nullable NSString *)key
                slug:(nullable NSString *)slug
            password:(NSString *)password
          completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion;
+ (void)linkForKey:(nullable NSString *)key
              slug:(nullable NSString *)slug
        completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion;

+ (void)linkForPublicURL:(NSURL *)publicURL
              completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion;
+ (void)loginForPublicURL:(NSURL *)publicURL
                 password:(NSString *)password
               completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)guestThumbnailDataForAssetId:(NSString *)assetId
                                                  publicURL:(NSURL *)publicURL
                                                       size:(NSString *)size
                                                 completion:(void (^)(NSData *_Nullable data,
                                                                      NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)guestOriginalFileForAssetId:(NSString *)assetId
                                                 publicURL:(NSURL *)publicURL
                                            destinationURL:(NSURL *)destinationURL
                                                completion:(void (^)(NSURL *_Nullable fileURL,
                                                                     NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
