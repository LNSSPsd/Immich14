#import "IMUser.h"
#import "IMAdminUser.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMUser ()
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy, nullable) NSString *avatarColor;
@property (nonatomic, copy, nullable) NSString *profileImagePath;
@property (nonatomic, copy, nullable) NSString *profileChangedAt;
@property (nonatomic, copy, nullable) NSString *oauthId;
@property (nonatomic) BOOL isAdmin;
@property (nonatomic) long long quotaUsageInBytes;
@property (nonatomic) long long quotaSizeInBytes;
@end

@implementation IMUser

+ (nullable instancetype)userWithResponseDictionary:(NSDictionary *)dict {
	if (![IMAdminUser userWithResponseDictionary:dict]) return nil;
	return [[self alloc] initWithDictionary:dict];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
	self = [super init];
	if (self) {
		NSString *userId = IMValueOrNil(dict[@"id"]);
		_userId = [userId isKindOfClass:[NSString class]] ? userId : @"";
		NSString *name = IMValueOrNil(dict[@"name"]);
		_name = [name isKindOfClass:[NSString class]] ? name : @"";
		NSString *email = IMValueOrNil(dict[@"email"]);
		_email = [email isKindOfClass:[NSString class]] ? email : @"";
		id avatarColor = IMValueOrNil(dict[@"avatarColor"]);
		_avatarColor = [avatarColor isKindOfClass:[NSString class]] ? [avatarColor copy] : nil;
		id profileImagePath = IMValueOrNil(dict[@"profileImagePath"]);
		_profileImagePath = [profileImagePath isKindOfClass:[NSString class]] ? [profileImagePath copy] : nil;
		id profileChangedAt = IMValueOrNil(dict[@"profileChangedAt"]);
		_profileChangedAt = [profileChangedAt isKindOfClass:[NSString class]] ? [profileChangedAt copy] : nil;
		id oauthId = IMValueOrNil(dict[@"oauthId"]);
		_oauthId = [oauthId isKindOfClass:[NSString class]] ? [oauthId copy] : nil;
		id admin = IMValueOrNil(dict[@"isAdmin"]);
		_isAdmin = [admin isKindOfClass:[NSNumber class]] && [admin boolValue];
		id usage = IMValueOrNil(dict[@"quotaUsageInBytes"]);
		_quotaUsageInBytes = [usage isKindOfClass:[NSNumber class]] ? [usage longLongValue] : 0;
		id size = IMValueOrNil(dict[@"quotaSizeInBytes"]);
		_quotaSizeInBytes = [size isKindOfClass:[NSNumber class]] ? [size longLongValue] : 0;
	}
	return self;
}

@end
