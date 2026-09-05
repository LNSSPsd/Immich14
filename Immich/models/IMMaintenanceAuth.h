#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMaintenanceLoginRequest : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *token;

+ (nullable instancetype)requestWithToken:(nullable NSString *)token;
+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary<NSString *, id> *)requestDictionary;

@end

@interface IMMaintenanceAuth : NSObject

@property (nonatomic, copy, readonly) NSString *username;

+ (nullable instancetype)authWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
