
#import "IMLockedPINStore.h"
#import <Security/Security.h>

NSString *const IMLockedPINKeychainService = @"com.lns.immich-ios-14.locked-photos";

@implementation IMLockedPINStore

+ (void)deleteAllRememberedPINs {
	NSDictionary *query = @{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: IMLockedPINKeychainService,
	};
	SecItemDelete((__bridge CFDictionaryRef)query);
}

@end
