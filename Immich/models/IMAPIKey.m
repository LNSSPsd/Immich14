#import "IMAPIKey.h"

static id IMAPIKeyValue(id value) { return [value isKindOfClass:[NSNull class]] ? nil : value; }

@interface IMAPIKey ()
@property (nonatomic, copy) NSString *keyId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *permissions;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *updatedAt;
@end

@implementation IMAPIKey
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMAPIKeyValue(dictionary[@"id"]); _keyId = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAPIKeyValue(dictionary[@"name"]); _name = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAPIKeyValue(dictionary[@"permissions"]);
		NSMutableArray *permissions = [NSMutableArray array];
		if ([value isKindOfClass:[NSArray class]]) for (id permission in value) if ([permission isKindOfClass:[NSString class]]) [permissions addObject:permission];
		_permissions = [permissions copy];
		value = IMAPIKeyValue(dictionary[@"createdAt"]); _createdAt = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAPIKeyValue(dictionary[@"updatedAt"]); _updatedAt = [value isKindOfClass:[NSString class]] ? value : @"";
	}
	return self;
}
+ (NSArray<IMAPIKey *> *)keysWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) if ([value isKindOfClass:[NSDictionary class]]) [result addObject:[[self alloc] initWithDictionary:value]];
	return result;
}
@end
