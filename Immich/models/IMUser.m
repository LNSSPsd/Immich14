#import "IMUser.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMUser ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *email;
@property (nonatomic) long long quotaUsageInBytes;
@property (nonatomic) long long quotaSizeInBytes;
@end

@implementation IMUser

- (instancetype)initWithDictionary:(NSDictionary *)dict {
	self = [super init];
	if (self) {
		NSString *name = IMValueOrNil(dict[@"name"]);
		_name = [name isKindOfClass:[NSString class]] ? name : @"";
		NSString *email = IMValueOrNil(dict[@"email"]);
		_email = [email isKindOfClass:[NSString class]] ? email : @"";
		id usage = IMValueOrNil(dict[@"quotaUsageInBytes"]);
		_quotaUsageInBytes = [usage isKindOfClass:[NSNumber class]] ? [usage longLongValue] : 0;
		id size = IMValueOrNil(dict[@"quotaSizeInBytes"]);
		_quotaSizeInBytes = [size isKindOfClass:[NSNumber class]] ? [size longLongValue] : 0;
	}
	return self;
}

@end
