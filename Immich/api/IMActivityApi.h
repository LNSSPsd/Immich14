#import <Foundation/Foundation.h>
#import "IMActivity.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMActivityApi : NSObject

+ (nullable NSURLSessionTask *)activitiesForAlbumId:(NSString *)albumId
                                             assetId:(nullable NSString *)assetId
                                                type:(nullable NSString *)type
                                               level:(nullable NSString *)level
                                              userId:(nullable NSString *)userId
                                          completion:(void (^)(NSArray<IMActivity *> *_Nullable activities,
                                                               NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)statisticsForAlbumId:(NSString *)albumId
                                             assetId:(nullable NSString *)assetId
                                          completion:(void (^)(NSInteger comments,
                                                               NSInteger likes,
                                                               NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)createForAlbumId:(NSString *)albumId
                                         assetId:(nullable NSString *)assetId
                                            type:(NSString *)type
                                         comment:(nullable NSString *)comment
                                      completion:(void (^)(IMActivity *_Nullable activity,
                                                           NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)deleteActivityId:(NSString *)activityId
                                      completion:(void (^)(BOOL success,
                                                           NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
