#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSessionInfo : NSObject
@property (nonatomic, copy, readonly) NSString *sessionId;
@property (nonatomic, copy, readonly) NSString *deviceOS;
@property (nonatomic, copy, readonly) NSString *deviceType;
@property (nonatomic, copy, readonly, nullable) NSString *appVersion;
@property (nonatomic, copy, readonly) NSString *createdAt;
@property (nonatomic, copy, readonly) NSString *updatedAt;
@property (nonatomic, copy, readonly, nullable) NSString *expiresAt;
@property (nonatomic, copy, readonly, nullable) NSString *token;
@property (nonatomic, readonly, getter=isCurrent) BOOL current;
@property (nonatomic, readonly) BOOL pendingSyncReset;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMSessionInfo *> *)sessionsWithArray:(NSArray *)array;

+ (nullable instancetype)sessionWithResponseDictionary:(NSDictionary *)dictionary;
+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
