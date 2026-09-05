#import <Foundation/Foundation.h>
#import "IMNotification.h"
#import "IMNotificationCreate.h"
#import "IMNotificationTemplate.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAdminNotificationApi : NSObject

+ (nullable NSURLSessionTask *)createNotification:(IMNotificationCreate *)request
                                        completion:(void (^)(IMNotification *_Nullable notification,
                                                             NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)createNotificationForUserId:(NSString *)userId
                                                     title:(NSString *)title
                                              description:(nullable NSString *)description
                                                     level:(nullable NSString *)level
                                                      type:(nullable NSString *)type
                                                    readAt:(nullable NSString *)readAt
                                                      data:(nullable NSDictionary<NSString *, id> *)data
                                                completion:(void (^)(IMNotification *_Nullable notification,
                                                                     NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)renderTemplateNamed:(NSString *)name
                                     customTemplate:(NSString *)customTemplate
                                         completion:(void (^)(IMNotificationTemplateResponse *_Nullable response,
                                                              NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)renderTemplateNamed:(NSString *)name
                                           request:(IMNotificationTemplateRequest *)request
                                         completion:(void (^)(IMNotificationTemplateResponse *_Nullable response,
                                                              NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
