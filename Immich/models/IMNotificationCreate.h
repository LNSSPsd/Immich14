#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMNotificationCreate : NSObject

@property (nonatomic, copy, readonly) NSString *userId;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *notificationDescription;
@property (nonatomic, copy, readonly, nullable) NSString *level;
@property (nonatomic, copy, readonly, nullable) NSString *type;
@property (nonatomic, copy, readonly, nullable) NSString *readAt;
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, id> *data;

+ (nullable instancetype)requestWithUserId:(NSString *)userId
                                     title:(NSString *)title
                              description:(nullable NSString *)description
                                     level:(nullable NSString *)level
                                      type:(nullable NSString *)type
                                    readAt:(nullable NSString *)readAt
                                      data:(nullable NSDictionary<NSString *, id> *)data;

+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary;

- (NSDictionary<NSString *, id> *)requestDictionary;

@end

NS_ASSUME_NONNULL_END
