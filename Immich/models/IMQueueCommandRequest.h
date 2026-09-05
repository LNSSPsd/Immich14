#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSArray<NSString *> *IMQueueNames(void);
FOUNDATION_EXPORT BOOL IMQueueNameIsKnown(NSString *_Nullable name);
FOUNDATION_EXPORT NSArray<NSString *> *IMQueueCommands(void);
FOUNDATION_EXPORT BOOL IMQueueCommandIsKnown(NSString *_Nullable command);

@interface IMQueueCommandRequest : NSObject

@property (nonatomic, copy, readonly) NSString *command;
@property (nonatomic, strong, readonly, nullable) NSNumber *force;

+ (nullable instancetype)requestWithCommand:(NSString *)command
                                      force:(nullable NSNumber *)force;

+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary;

- (NSDictionary<NSString *, id> *)requestDictionary;

@end

NS_ASSUME_NONNULL_END
