#import <Foundation/Foundation.h>
#import "IMDownloadResponseDto.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMDownloadApi : NSObject

+ (nullable NSURLSessionTask *)downloadInfoForAssetIds:(NSArray<NSString *> *)assetIds
                                          archiveSize:(nullable NSNumber *)archiveSize
                                           completion:(void (^)(IMDownloadResponseDto *_Nullable response,
                                                                NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)downloadInfoForAlbumId:(NSString *)albumId
                                         archiveSize:(nullable NSNumber *)archiveSize
                                          completion:(void (^)(IMDownloadResponseDto *_Nullable response,
                                                               NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)downloadInfoForUserId:(NSString *)userId
                                         archiveSize:(nullable NSNumber *)archiveSize
                                          completion:(void (^)(IMDownloadResponseDto *_Nullable response,
                                                               NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)downloadArchiveForAssetIds:(NSArray<NSString *> *)assetIds
                                                   edited:(BOOL)edited
                                                      key:(nullable NSString *)key
                                                     slug:(nullable NSString *)slug
                                           destinationURL:(NSURL *)destinationURL
                                               completion:(void (^)(NSURL *_Nullable fileURL,
                                                                    NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
