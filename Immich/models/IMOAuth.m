#import "IMOAuth.h"
#import "common.h"

static BOOL IMOAuthNonEmptyString(id value) {
	return [value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0;
}

static BOOL IMOAuthBoolean(id value) {
	return [value isKindOfClass:[NSNumber class]] &&
	       ([(NSNumber *)value doubleValue] == 0.0 || [(NSNumber *)value doubleValue] == 1.0);
}

static BOOL IMOAuthUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) {
		return NO;
	}
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
	if (!uuid) {
		return NO;
	}
	NSString *canonical = uuid.UUIDString.lowercaseString;
	return [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMOAuthEmail(id value) {
	if (!IMOAuthNonEmptyString(value)) {
		return NO;
	}
	NSString *email = (NSString *)value;
	if ([email rangeOfString:@"\n"].location != NSNotFound ||
	    [email rangeOfString:@"\r"].location != NSNotFound ||
	    [email rangeOfString:@"@"].location == NSNotFound) {
		return NO;
	}
	NSArray<NSString *> *parts = [email componentsSeparatedByString:@"@"];
	if (parts.count != 2 || parts[0].length == 0 || parts[1].length == 0) {
		return NO;
	}
	NSString *domain = parts[1];
	if ([domain hasPrefix:@"."] || [domain hasSuffix:@"."] ||
	    [domain rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
		return NO;
	}
	return YES;
}

@interface IMOAuthAuthorizeResponse ()
@property (nonatomic, copy) NSString *url;
@end

@implementation IMOAuthAuthorizeResponse

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] || !IMOAuthNonEmptyString(dictionary[@"url"])) {
		return nil;
	}
	IMOAuthAuthorizeResponse *response = [[self alloc] init];
	response.url = dictionary[@"url"];
	return response;
}

@end

@interface IMOAuthLoginResponse ()
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic) BOOL isAdmin;
@property (nonatomic) BOOL isOnboarded;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *profileImagePath;
@property (nonatomic) BOOL shouldChangePassword;
@property (nonatomic, copy) NSString *userEmail;
@property (nonatomic, copy) NSString *userId;
@end

@implementation IMOAuthLoginResponse

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    !IMOAuthNonEmptyString(dictionary[@"accessToken"]) ||
	    !IMOAuthBoolean(dictionary[@"isAdmin"]) ||
	    !IMOAuthBoolean(dictionary[@"isOnboarded"]) ||
	    !IMOAuthNonEmptyString(dictionary[@"name"]) ||
	    ![dictionary[@"profileImagePath"] isKindOfClass:[NSString class]] ||
	    !IMOAuthBoolean(dictionary[@"shouldChangePassword"]) ||
	    !IMOAuthEmail(dictionary[@"userEmail"]) ||
	    !IMOAuthUUIDv4(dictionary[@"userId"])) {
		return nil;
	}
	IMOAuthLoginResponse *response = [[self alloc] init];
	response.accessToken = dictionary[@"accessToken"];
	response.isAdmin = [dictionary[@"isAdmin"] boolValue];
	response.isOnboarded = [dictionary[@"isOnboarded"] boolValue];
	response.name = dictionary[@"name"];
	response.profileImagePath = dictionary[@"profileImagePath"];
	response.shouldChangePassword = [dictionary[@"shouldChangePassword"] boolValue];
	response.userEmail = dictionary[@"userEmail"];
	response.userId = dictionary[@"userId"];
	return response;
}

@end
