#import "IMTag.h"

static id IMTagValue(id value) { return [value isKindOfClass:[NSNull class]] ? nil : value; }

@interface IMTag ()
@property (nonatomic, copy) NSString *tagId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy, nullable) NSString *color;
@property (nonatomic, copy, nullable) NSString *parentId;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *updatedAt;
@end

@implementation IMTag
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMTagValue(dictionary[@"id"]); _tagId = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMTagValue(dictionary[@"name"]); _name = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMTagValue(dictionary[@"value"]); _value = [value isKindOfClass:[NSString class]] ? value : _name;
		value = IMTagValue(dictionary[@"color"]); _color = [value isKindOfClass:[NSString class]] ? value : nil;
		value = IMTagValue(dictionary[@"parentId"]); _parentId = [value isKindOfClass:[NSString class]] ? value : nil;
		value = IMTagValue(dictionary[@"createdAt"]); _createdAt = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMTagValue(dictionary[@"updatedAt"]); _updatedAt = [value isKindOfClass:[NSString class]] ? value : @"";
	}
	return self;
}
+ (NSArray<IMTag *> *)tagsWithArray:(NSArray *)array {
	NSMutableArray *tags = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) if ([value isKindOfClass:[NSDictionary class]]) [tags addObject:[[self alloc] initWithDictionary:value]];
	return tags;
}
@end
