#import "IMSessionInfo.h"
#include <string.h>

static id IMSessionValue(id value) { return [value isKindOfClass:[NSNull class]] ? nil : value; }

static BOOL IMSessionBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMSessionUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = [(NSString *)value lowercaseString];
	return [raw isEqualToString:canonical] && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMSessionString(id value) {
	return [value isKindOfClass:[NSString class]];
}

@interface IMSessionInfo ()
@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *deviceOS;
@property (nonatomic, copy) NSString *deviceType;
@property (nonatomic, copy, nullable) NSString *appVersion;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *updatedAt;
@property (nonatomic, copy, nullable) NSString *expiresAt;
@property (nonatomic, copy, nullable) NSString *token;
@property (nonatomic) BOOL current;
@property (nonatomic) BOOL pendingSyncReset;
@end

@implementation IMSessionInfo
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMSessionValue(dictionary[@"id"]); _sessionId = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMSessionValue(dictionary[@"deviceOS"]); _deviceOS = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMSessionValue(dictionary[@"deviceType"]); _deviceType = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMSessionValue(dictionary[@"appVersion"]); _appVersion = [value isKindOfClass:[NSString class]] ? value : nil;
		value = IMSessionValue(dictionary[@"createdAt"]); _createdAt = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMSessionValue(dictionary[@"updatedAt"]); _updatedAt = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMSessionValue(dictionary[@"expiresAt"]); _expiresAt = [value isKindOfClass:[NSString class]] ? value : nil;
		value = IMSessionValue(dictionary[@"token"]); _token = [value isKindOfClass:[NSString class]] ? value : nil;
		_current = [IMSessionValue(dictionary[@"current"]) boolValue];
		_pendingSyncReset = [IMSessionValue(dictionary[@"isPendingSyncReset"]) boolValue];
	}
	return self;
}
+ (NSArray<IMSessionInfo *> *)sessionsWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) if ([value isKindOfClass:[NSDictionary class]]) [result addObject:[[self alloc] initWithDictionary:value]];
	return result;
}

+ (nullable instancetype)sessionWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    !IMSessionUUIDv4(dictionary[@"id"]) ||
	    !IMSessionString(dictionary[@"createdAt"]) ||
	    !IMSessionString(dictionary[@"updatedAt"]) ||
	    !IMSessionString(dictionary[@"deviceOS"]) ||
	    !IMSessionString(dictionary[@"deviceType"]) ||
	    !IMSessionBoolean(dictionary[@"current"]) ||
	    !IMSessionBoolean(dictionary[@"isPendingSyncReset"])) return nil;
	if (dictionary[@"appVersion"] == nil ||
	    (![dictionary[@"appVersion"] isKindOfClass:[NSNull class]] &&
	     ![dictionary[@"appVersion"] isKindOfClass:[NSString class]])) return nil;
	id expiresAt = dictionary[@"expiresAt"];
	if (expiresAt != nil && ![expiresAt isKindOfClass:[NSNull class]] && ![expiresAt isKindOfClass:[NSString class]]) return nil;
	id token = dictionary[@"token"];
	if (token != nil && ![token isKindOfClass:[NSString class]]) return nil;
	IMSessionInfo *result = [[self alloc] initWithDictionary:dictionary];
	return result.sessionId.length > 0 ? result : nil;
}

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	return [self sessionWithResponseDictionary:dictionary];
}

@end
