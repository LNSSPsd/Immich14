#import "IMWorkflowTrigger.h"

static id IMWorkflowTriggerValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMWorkflowTrigger ()
@property (nonatomic, copy) NSString *trigger;
@property (nonatomic, copy) NSArray<NSString *> *types;
@end

@implementation IMWorkflowTrigger

+ (nullable instancetype)triggerWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id triggerValue = IMWorkflowTriggerValueOrNil(dictionary[@"trigger"]);
	if (![triggerValue isKindOfClass:[NSString class]] || [(NSString *)triggerValue length] == 0) {
		return nil;
	}
	NSMutableArray<NSString *> *types = [NSMutableArray array];
	id typesValue = IMWorkflowTriggerValueOrNil(dictionary[@"types"]);
	if ([typesValue isKindOfClass:[NSArray class]]) {
		for (id value in (NSArray *)typesValue) {
			if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
				[types addObject:value];
			}
		}
	}
	IMWorkflowTrigger *trigger = [[self alloc] init];
	trigger.trigger = [triggerValue copy];
	trigger.types = [types copy];
	return trigger;
}

+ (NSArray<IMWorkflowTrigger *> *)triggersWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMWorkflowTrigger *> *triggers = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMWorkflowTrigger *trigger = [value isKindOfClass:[NSDictionary class]] ? [self triggerWithResponseDictionary:value] : nil;
		if (trigger) {
			[triggers addObject:trigger];
		}
	}
	return [triggers copy];
}

@end
