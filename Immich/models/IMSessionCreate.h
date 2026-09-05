#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSessionCreateRequest : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *deviceOS;
@property (nonatomic, copy, readonly, nullable) NSString *deviceType;
@property (nonatomic, strong, readonly, nullable) NSNumber *duration;

+ (nullable instancetype)requestWithDeviceOS:(nullable NSString *)deviceOS
                                   deviceType:(nullable NSString *)deviceType
                                    duration:(nullable NSNumber *)duration;
+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary<NSString *, id> *)requestDictionary;

@end

NS_ASSUME_NONNULL_END
