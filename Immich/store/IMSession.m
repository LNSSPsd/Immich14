#import "IMSession.h"
#import "common.h"
#import "IMDatabase.h"
#import "IMThumbCache.h"
#import "IMUserApi.h"
#import "IMUserPreferencesApi.h"
#import "IMServerApi.h"
#import "IMSystemConfigApi.h"
#import "IMBackupQueue.h"
#import "IMPrefs.h"
#import "IMLockedPINStore.h"
#import <Security/Security.h>

static NSString *const kKeychainService = @"com.lns.immich-ios-14.session";
static NSString *const kKeychainAccount = @"accessToken";

static NSString *const kDefaultsBaseURL = @"IMSessionBaseURL";
static NSString *const kDefaultsUserId  = @"IMSessionUserId";
static NSString *const kDefaultsAuthKind = @"IMSessionAuthKind"; // "apiKey"; absent => Bearer
static NSString *const kDefaultsPasswordChangeRequired = @"IMSessionPasswordChangeRequired";
static NSString *const kAuthKindAPIKeyValue = @"apiKey";

static void IMClearAccountMediaCaches(void) {
	NSString *temporary = NSTemporaryDirectory();
	if (temporary.length == 0) return;
	NSArray<NSString *> *names = @[ @"IMVideoCache", @"IMLiveCache", @"IMOriginalCache", @"IMShare" ];
	NSFileManager *manager = [NSFileManager defaultManager];
	for (NSString *name in names) {
		NSString *path = [temporary stringByAppendingPathComponent:name];
		(void)[manager removeItemAtPath:path error:NULL];
	}
}

static void IMClearAccountScopedState(void) {
	[IMLockedPINStore deleteAllRememberedPINs];
	[[IMDatabase shared] clearAllData];
	[[IMBackupQueue shared] reset];
	[[IMThumbCache shared] clearWithCompletion:^{}];
	IMClearAccountMediaCaches();
	[IMUserApi clearCachedUser];
	[IMUserPreferencesApi clearCachedPreferences];
	[IMServerApi clearCached];
	[IMSystemConfigApi clearCachedConfig];
	IMPrefs.shared.backupEnabled = NO;
}

@interface IMSession ()
@property (nonatomic, copy, nullable) NSURL *baseURL;
@property (nonatomic, copy, nullable) NSString *accessToken;
@property (nonatomic, copy, nullable) NSString *userId;
@property (nonatomic) IMSessionAuthKind authKind;
@property (nonatomic) BOOL passwordChangeRequired;
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
			_authKind = [[defaults stringForKey:kDefaultsAuthKind] isEqualToString:kAuthKindAPIKeyValue]
			    ? IMSessionAuthKindAPIKey
			    : IMSessionAuthKindBearer;
			_passwordChangeRequired = (_authKind == IMSessionAuthKindBearer) &&
			                         [defaults boolForKey:kDefaultsPasswordChangeRequired];
		}
	}
	return self;
}

- (BOOL)isLoggedIn {
	return self.baseURL != nil && self.accessToken.length > 0;
}

- (void)reloadFromPersistence {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	(void)[defaults synchronize];
	NSString *urlString = [defaults stringForKey:kDefaultsBaseURL];
	NSString *token = [self keychainToken];
	NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
	if (url && token.length > 0) {
		self.baseURL = url;
		self.accessToken = token;
		self.userId = [defaults stringForKey:kDefaultsUserId];
		self.authKind = [[defaults stringForKey:kDefaultsAuthKind] isEqualToString:kAuthKindAPIKeyValue]
		    ? IMSessionAuthKindAPIKey
		    : IMSessionAuthKindBearer;
		self.passwordChangeRequired = (self.authKind == IMSessionAuthKindBearer) &&
		                              [defaults boolForKey:kDefaultsPasswordChangeRequired];
	} else {
		self.baseURL = nil;
		self.accessToken = nil;
		self.userId = nil;
		self.authKind = IMSessionAuthKindBearer;
		self.passwordChangeRequired = NO;
	}
}

- (void)startWithBaseURL:(NSURL *)baseURL
                  secret:(NSString *)secret
                  userId:(nullable NSString *)userId
                    kind:(IMSessionAuthKind)kind
   passwordChangeRequired:(BOOL)passwordChangeRequired {
	BOOL accountChanged = self.isLoggedIn &&
	    (![self.baseURL.absoluteString isEqualToString:baseURL.absoluteString] ||
	     !((self.userId == nil && userId == nil) || [self.userId isEqualToString:userId]) ||
	     self.authKind != kind);
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:baseURL.absoluteString forKey:kDefaultsBaseURL];
	if (userId) {
		[defaults setObject:userId forKey:kDefaultsUserId];
	} else {
		[defaults removeObjectForKey:kDefaultsUserId];
	}
	if (kind == IMSessionAuthKindAPIKey) {
		[defaults setObject:kAuthKindAPIKeyValue forKey:kDefaultsAuthKind];
	} else {
		[defaults removeObjectForKey:kDefaultsAuthKind];
	}
	[defaults setBool:passwordChangeRequired forKey:kDefaultsPasswordChangeRequired];

	[self setKeychainToken:secret];

	self.baseURL = baseURL;
	self.accessToken = secret;
	self.userId = userId;
	self.authKind = kind;
	self.passwordChangeRequired = passwordChangeRequired;
	if (accountChanged) {
		IMClearAccountScopedState();
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:IMSessionDidChangeNotification object:self];
}

- (void)startWithBaseURL:(NSURL *)baseURL accessToken:(NSString *)token userId:(NSString *)userId {
	[self startWithBaseURL:baseURL
	               secret:token
	               userId:userId
	                 kind:IMSessionAuthKindBearer
	 passwordChangeRequired:NO];
}

- (void)startWithBaseURL:(NSURL *)baseURL
             accessToken:(NSString *)token
                  userId:(NSString *)userId
   passwordChangeRequired:(BOOL)passwordChangeRequired {
	[self startWithBaseURL:baseURL
	               secret:token
	               userId:userId
	                 kind:IMSessionAuthKindBearer
	 passwordChangeRequired:passwordChangeRequired];
}

- (void)startWithBaseURL:(NSURL *)baseURL apiKey:(NSString *)apiKey userId:(nullable NSString *)userId {
	[self startWithBaseURL:baseURL
	               secret:apiKey
	               userId:userId
	                 kind:IMSessionAuthKindAPIKey
	 passwordChangeRequired:NO];
}

- (void)clearPasswordChangeRequirement {
	self.passwordChangeRequired = NO;
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultsPasswordChangeRequired];
}

- (void)logout {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:kDefaultsBaseURL];
	[defaults removeObjectForKey:kDefaultsUserId];
	[defaults removeObjectForKey:kDefaultsAuthKind];
	[defaults removeObjectForKey:kDefaultsPasswordChangeRequired];
	[self deleteKeychainToken];

	self.baseURL = nil;
	self.accessToken = nil;
	self.userId = nil;
	self.authKind = IMSessionAuthKindBearer;
	self.passwordChangeRequired = NO;

	IMClearAccountScopedState();

	[[NSNotificationCenter defaultCenter] postNotificationName:IMSessionDidChangeNotification object:self];
}

- (nullable NSString *)authorizationHeader {
	if (self.accessToken.length == 0 || self.authKind != IMSessionAuthKindBearer) {
		return nil;
	}
	return [NSString stringWithFormat:@"Bearer %@", self.accessToken];
}

- (nullable NSString *)apiKeyHeaderValue {
	if (self.accessToken.length == 0 || self.authKind != IMSessionAuthKindAPIKey) {
		return nil;
	}
	return self.accessToken;
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
	OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	if (status != errSecSuccess) {
		NSLog(@"IMSession: SecItemAdd failed (%d) — token not persisted, session is in-memory only", (int)status);
	}
}

- (void)deleteKeychainToken {
	NSMutableDictionary *query = [self keychainQuery];
	SecItemDelete((__bridge CFDictionaryRef)query);
}

@end
