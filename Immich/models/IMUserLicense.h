#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMUserLicense : NSObject

@property (nonatomic, copy, readonly) NSString *activationKey;
@property (nonatomic, copy, readonly) NSString *licenseKey;
@property (nonatomic, copy, readonly) NSString *activatedAt;

+ (nullable instancetype)licenseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
