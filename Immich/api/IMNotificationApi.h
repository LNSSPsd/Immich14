#import <Foundation/Foundation.h>
#import "IMNotification.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const IMNotificationsDidChangeNotification;

@interface IMNotificationApi : NSObject

+ (nullable NSURLSessionTask *)notificationsWithUnreadOnly:(BOOL)unreadOnly
	                                             completion:(void (^)(NSArray<IMNotification *> *_Nullable notifications,
	                                                                  NSError *_Nullable error))completion;
+ (nullable NSArray<IMNotification *> *)cachedNotifications;
+ (NSInteger)cachedUnreadCount;

+ (void)notificationWithId:(NSString *)notificationId
                 completion:(void (^)(IMNotification *_Nullable notification,
                                      NSError *_Nullable error))completion;

+ (void)setNotificationId:(NSString *)notificationId
	                  read:(BOOL)read
	            completion:(void (^)(IMNotification *_Nullable notification, NSError *_Nullable error))completion;
+ (void)setAllNotificationsRead:(BOOL)read
	                    completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)deleteNotificationId:(NSString *)notificationId
	                  completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)deleteNotificationIds:(NSArray<NSString *> *)notificationIds
	                    completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
