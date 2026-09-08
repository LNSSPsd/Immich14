#import "IMAdminUser.h"
#import <math.h>
#include <limits.h>
#include <string.h>

static id IMAdminValue(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static long long IMAdminIntegerValue(id value) {
	if ([value isKindOfClass:[NSNumber class]]) return [value longLongValue];
	if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
		return [(NSString *)value longLongValue];
	}
	return 0;
}

static BOOL IMAdminStrictString(id value, BOOL nonEmpty) {
	return [value isKindOfClass:[NSString class]] && (!nonEmpty || [(NSString *)value length] > 0);
}

static BOOL IMAdminStrictUUIDv4(id value) {
	if (!IMAdminStrictString(value, YES)) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	return canonical.length == 36 && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMAdminStrictEmail(id value) {
	if (!IMAdminStrictString(value, YES)) return NO;
	static NSRegularExpression *expression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:
		    @"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
		                                                         options:0
		                                                           error:NULL];
	});
	return [expression firstMatchInString:value options:0 range:NSMakeRange(0, [(NSString *)value length])] != nil;
}

static BOOL IMAdminStrictDateTime(id value) {
	if (!IMAdminStrictString(value, YES)) return NO;
	static NSISO8601DateFormatter *withFraction;
	static NSISO8601DateFormatter *withoutFraction;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		withFraction = [[NSISO8601DateFormatter alloc] init];
		withFraction.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
		withoutFraction = [[NSISO8601DateFormatter alloc] init];
		withoutFraction.formatOptions = NSISO8601DateFormatWithInternetDateTime;
	});
	return [withFraction dateFromString:value] != nil || [withoutFraction dateFromString:value] != nil;
}

static BOOL IMAdminStrictNullableDateTime(id value) {
	return [value isKindOfClass:[NSNull class]] || IMAdminStrictDateTime(value);
}

static BOOL IMAdminStrictBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMAdminStrictInteger(id value, long long *outValue) {
	if (![value isKindOfClass:[NSNumber class]] || IMAdminStrictBoolean(value)) return NO;
	double number = [(NSNumber *)value doubleValue];
	if (!isfinite(number) || floor(number) != number || number < 0.0 ||
	    number > 9007199254740991.0 || number > (double)LLONG_MAX) return NO;
	if (outValue) *outValue = [(NSNumber *)value longLongValue];
	return YES;
}

static BOOL IMAdminStrictNullableString(id value, BOOL nonEmpty) {
	return [value isKindOfClass:[NSNull class]] || IMAdminStrictString(value, nonEmpty);
}

static BOOL IMAdminStrictEnum(id value, NSSet<NSString *> *allowed) {
	return IMAdminStrictString(value, YES) && [allowed containsObject:value];
}

@interface IMAdminUser ()
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *avatarColor;
@property (nonatomic, copy, nullable) NSString *storageLabel;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *profileChangedAt;
@property (nonatomic, copy) NSString *profileImagePath;
@property (nonatomic, copy) NSString *oauthId;
@property (nonatomic, copy) NSString *updatedAt;
@property (nonatomic, strong, nullable) IMUserLicense *license;
@property (nonatomic) BOOL isAdmin;
@property (nonatomic) BOOL shouldChangePassword;
@property (nonatomic) long long quotaUsageInBytes;
@property (nonatomic) long long quotaSizeInBytes;
@property (nonatomic, copy, nullable) NSString *deletedAt;
@end

@implementation IMAdminUser
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMAdminValue(dictionary[@"id"]);
		_userId = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"name"]);
		_name = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"email"]);
		_email = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"status"]);
		_status = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"avatarColor"]);
		_avatarColor = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"storageLabel"]);
		_storageLabel = [value isKindOfClass:[NSString class]] ? value : nil;
		value = IMAdminValue(dictionary[@"createdAt"]);
		_createdAt = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"profileChangedAt"]);
		_profileChangedAt = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"profileImagePath"]);
		_profileImagePath = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"oauthId"]);
		_oauthId = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"updatedAt"]);
		_updatedAt = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAdminValue(dictionary[@"isAdmin"]);
		_isAdmin = [value isKindOfClass:[NSNumber class]] && [value boolValue];
		value = IMAdminValue(dictionary[@"shouldChangePassword"]);
		_shouldChangePassword = [value isKindOfClass:[NSNumber class]] && [value boolValue];
		value = IMAdminValue(dictionary[@"quotaUsageInBytes"]);
		_quotaUsageInBytes = IMAdminIntegerValue(value);
		value = IMAdminValue(dictionary[@"quotaSizeInBytes"]);
		_quotaSizeInBytes = IMAdminIntegerValue(value);
		value = IMAdminValue(dictionary[@"deletedAt"]);
		_deletedAt = [value isKindOfClass:[NSString class]] ? value : nil;
		id rawLicense = dictionary[@"license"];
		_license = [rawLicense isKindOfClass:[NSDictionary class]]
		    ? [IMUserLicense licenseWithDictionary:rawLicense]
		    : nil;
	}
	return self;
}

+ (nullable instancetype)userWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	NSArray<NSString *> *requiredKeys = @[
		@"avatarColor", @"createdAt", @"deletedAt", @"email", @"id", @"isAdmin", @"license",
		@"name", @"oauthId", @"profileChangedAt", @"profileImagePath", @"quotaSizeInBytes",
		@"quotaUsageInBytes", @"shouldChangePassword", @"status", @"storageLabel", @"updatedAt"
	];
	for (NSString *key in requiredKeys) {
		if (dictionary[key] == nil) return nil;
	}
	if (!IMAdminStrictUUIDv4(dictionary[@"id"]) || !IMAdminStrictEmail(dictionary[@"email"]) ||
	    !IMAdminStrictString(dictionary[@"name"], NO) || !IMAdminStrictString(dictionary[@"oauthId"], NO) ||
	    !IMAdminStrictString(dictionary[@"profileImagePath"], NO) ||
	    !IMAdminStrictDateTime(dictionary[@"createdAt"]) ||
	    !IMAdminStrictDateTime(dictionary[@"profileChangedAt"]) ||
	    !IMAdminStrictDateTime(dictionary[@"updatedAt"]) ||
	    !IMAdminStrictEnum(dictionary[@"avatarColor"], [NSSet setWithArray:@[
		    @"primary", @"pink", @"red", @"yellow", @"blue", @"green", @"purple", @"orange", @"gray", @"amber"
	    ]]) ||
	    !IMAdminStrictEnum(dictionary[@"status"], [NSSet setWithArray:@[ @"active", @"removing", @"deleted" ]]) ||
	    !IMAdminStrictBoolean(dictionary[@"isAdmin"]) ||
	    !IMAdminStrictBoolean(dictionary[@"shouldChangePassword"]) ||
	    !IMAdminStrictNullableDateTime(dictionary[@"deletedAt"]) ||
	    !IMAdminStrictNullableString(dictionary[@"storageLabel"], NO)) {
		return nil;
	}

	long long quotaUsage = 0;
	long long quotaSize = 0;
	if (![dictionary[@"quotaUsageInBytes"] isKindOfClass:[NSNull class]] &&
	    !IMAdminStrictInteger(dictionary[@"quotaUsageInBytes"], &quotaUsage)) return nil;
	if (![dictionary[@"quotaSizeInBytes"] isKindOfClass:[NSNull class]] &&
	    !IMAdminStrictInteger(dictionary[@"quotaSizeInBytes"], &quotaSize)) return nil;

	id rawLicense = dictionary[@"license"];
	IMUserLicense *license = nil;
	if (![rawLicense isKindOfClass:[NSNull class]]) {
		license = [IMUserLicense licenseWithDictionary:rawLicense];
		if (!license) return nil;
	}

	IMAdminUser *user = [[self alloc] init];
	user.userId = [dictionary[@"id"] copy];
	user.name = [dictionary[@"name"] copy];
	user.email = [dictionary[@"email"] copy];
	user.status = [dictionary[@"status"] copy];
	user.avatarColor = [dictionary[@"avatarColor"] copy];
	id storageLabel = dictionary[@"storageLabel"];
	user.storageLabel = [storageLabel isKindOfClass:[NSString class]] ? [storageLabel copy] : nil;
	user.createdAt = [dictionary[@"createdAt"] copy];
	user.profileChangedAt = [dictionary[@"profileChangedAt"] copy];
	user.profileImagePath = [dictionary[@"profileImagePath"] copy];
	user.oauthId = [dictionary[@"oauthId"] copy];
	user.updatedAt = [dictionary[@"updatedAt"] copy];
	user.license = license;
	user.isAdmin = [dictionary[@"isAdmin"] boolValue];
	user.shouldChangePassword = [dictionary[@"shouldChangePassword"] boolValue];
	user.quotaUsageInBytes = quotaUsage;
	user.quotaSizeInBytes = quotaSize;
	id deletedAt = dictionary[@"deletedAt"];
	user.deletedAt = [deletedAt isKindOfClass:[NSString class]] ? [deletedAt copy] : nil;
	return user;
}

+ (nullable instancetype)userWithCompatibleResponseDictionary:(NSDictionary *)dictionary {
	IMAdminUser *strict = [self userWithResponseDictionary:dictionary];
	if (strict) return strict;
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;

	id userId = dictionary[@"id"];
	id name = dictionary[@"name"];
	id email = dictionary[@"email"];
	id isAdmin = dictionary[@"isAdmin"];
	if (!IMAdminStrictString(userId, YES) || !IMAdminStrictString(name, NO) ||
	    !IMAdminStrictEmail(email) || !IMAdminStrictBoolean(isAdmin)) {
		return nil;
	}

	for (NSString *key in @[ @"isAdmin", @"shouldChangePassword" ]) {
		id value = dictionary[key];
		if (value != nil && !IMAdminStrictBoolean(value)) return nil;
	}
	for (NSString *key in @[ @"avatarColor", @"status", @"profileImagePath", @"oauthId", @"storageLabel" ]) {
		id value = dictionary[key];
		if (value != nil && ![value isKindOfClass:[NSNull class]] && ![value isKindOfClass:[NSString class]]) return nil;
	}
	for (NSString *key in @[ @"createdAt", @"profileChangedAt", @"updatedAt", @"deletedAt" ]) {
		id value = dictionary[key];
		if (value != nil && ![value isKindOfClass:[NSNull class]] && ![value isKindOfClass:[NSString class]]) return nil;
	}
	for (NSString *key in @[ @"quotaSizeInBytes", @"quotaUsageInBytes" ]) {
		id value = dictionary[key];
		if (value != nil && ![value isKindOfClass:[NSNull class]] &&
		    ![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSString class]]) return nil;
	}
	return [[self alloc] initWithDictionary:dictionary];
}

+ (NSArray<IMAdminUser *> *)usersWithArray:(NSArray *)array {
	NSMutableArray *users = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		if ([value isKindOfClass:[NSDictionary class]]) {
			[users addObject:[[self alloc] initWithDictionary:value]];
		}
	}
	return users;
}
@end
