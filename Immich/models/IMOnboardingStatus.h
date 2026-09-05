#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMOnboardingStatus : NSObject

@property (nonatomic, readonly, getter=isOnboarded) BOOL onboarded;

+ (nullable instancetype)statusWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
