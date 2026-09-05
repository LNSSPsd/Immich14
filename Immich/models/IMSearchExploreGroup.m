#import "IMSearchExploreGroup.h"

static id IMExploreGroupValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMSearchExploreGroup ()
@property (nonatomic, copy) NSString *fieldName;
@property (nonatomic, copy) NSArray<IMSearchExploreItem *> *items;
@end

@implementation IMSearchExploreGroup

+ (nullable instancetype)groupWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id fieldName = IMExploreGroupValueOrNil(dictionary[@"fieldName"]);
	id rawItems = IMExploreGroupValueOrNil(dictionary[@"items"]);
	if (![fieldName isKindOfClass:[NSString class]] || [(NSString *)fieldName length] == 0 ||
	    ![rawItems isKindOfClass:[NSArray class]]) {
		return nil;
	}
	NSMutableArray<IMSearchExploreItem *> *items = [NSMutableArray arrayWithCapacity:[rawItems count]];
	for (id raw in (NSArray *)rawItems) {
		IMSearchExploreItem *item = [IMSearchExploreItem itemWithResponseDictionary:raw];
		if (!item) return nil;
		[items addObject:item];
	}
	IMSearchExploreGroup *group = [[self alloc] init];
	group.fieldName = [fieldName copy];
	group.items = [items copy];
	return group;
}

+ (nullable NSArray<IMSearchExploreGroup *> *)groupsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray<IMSearchExploreGroup *> *groups = [NSMutableArray arrayWithCapacity:array.count];
	for (id raw in array) {
		IMSearchExploreGroup *group = [self groupWithResponseDictionary:raw];
		if (!group) return nil;
		[groups addObject:group];
	}
	return [groups copy];
}

@end
