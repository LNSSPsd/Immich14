
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const IMLockedPINKeychainService;

@interface IMLockedPINStore : NSObject

+ (void)deleteAllRememberedPINs;

@end

NS_ASSUME_NONNULL_END
