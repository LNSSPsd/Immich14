#import "IMSession.h"
#import "common.h"
#import <Security/Security.h>

static NSString *const kKeychainService = @"com.lns.immich-ios-14.session";
static NSString *const kKeychainAccount = @"accessToken";

static NSString *const kDefaultsBaseURL = @"IMSessionBaseURL";
static NSString *const kDefaultsUserId  = @"IMSessionUserId";

@interface IMSession ()
@property (nonatomic, copy, nullable) NSURL *baseURL;
@property (nonatomic, copy, nullable) NSString *accessToken;
@property (nonatomic, copy, nullable) NSString *userId;
@end

@implementation IMSession

+ (instancetype)shared {
	static IMSession *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMSession alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSString *urlString = [defaults stringForKey:kDefaultsBaseURL];
		NSString *token = [self keychainToken];
		if (urlString.length > 0 && token.length > 0) {
			_baseURL = [NSURL URLWithString:urlString];
			_accessToken = token;
			_userId = [defaults stringForKey:kDefaultsUserId];
		}
	}
	return self;
}

- (BOOL)isLoggedIn {
	return self.baseURL != nil && self.accessToken.length > 0;
}

- (void)startWithBaseURL:(NSURL *)baseURL accessToken:(NSString *)token userId:(NSString *)userId {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:baseURL.absoluteString forKey:kDefaultsBaseURL];
	[defaults setObject:userId forKey:kDefaultsUserId];

	[self setKeychainToken:token];

	self.baseURL = baseURL;
	self.accessToken = token;
	self.userId = userId;

	[[NSNotificationCenter defaultCenter] postNotificationName:IMSessionDidChangeNotification object:self];
}

- (void)logout {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:kDefaultsBaseURL];
	[defaults removeObjectForKey:kDefaultsUserId];
	[self deleteKeychainToken];

	self.baseURL = nil;
	self.accessToken = nil;
	self.userId = nil;

	[[NSNotificationCenter defaultCenter] postNotificationName:IMSessionDidChangeNotification object:self];
}

- (nullable NSString *)authorizationHeader {
	if (self.accessToken.length == 0) {
		return nil;
	}
	return [NSString stringWithFormat:@"Bearer %@", self.accessToken];
}

#pragma mark - Keychain

- (NSMutableDictionary *)keychainQuery {
	return [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: kKeychainService,
		(__bridge id)kSecAttrAccount: kKeychainAccount,
	} mutableCopy];
}

- (nullable NSString *)keychainToken {
	NSMutableDictionary *query = [self keychainQuery];
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status != errSecSuccess || result == NULL) {
		return nil;
	}
	NSData *data = (__bridge_transfer NSData *)result;
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)setKeychainToken:(NSString *)token {
	[self deleteKeychainToken];

	NSMutableDictionary *query = [self keychainQuery];
	query[(__bridge id)kSecValueData] = [token dataUsingEncoding:NSUTF8StringEncoding];
	query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
	SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}

- (void)deleteKeychainToken {
	NSMutableDictionary *query = [self keychainQuery];
	SecItemDelete((__bridge CFDictionaryRef)query);
}

@end
