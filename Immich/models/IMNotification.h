#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMNotification : NSObject

@property (nonatomic, copy, readonly) NSString *notificationId;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *notificationDescription;
@property (nonatomic, copy, readonly) NSString *level;
@property (nonatomic, copy, readonly) NSString *type;
@property (nonatomic, strong, readonly) NSDate *createdAt;
@property (nonatomic, strong, readonly, nullable) NSDate *readAt;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *data;
@property (nonatomic, readonly, getter=isRead) BOOL read;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMNotification *> *)notificationsWithArray:(NSArray *)array;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
