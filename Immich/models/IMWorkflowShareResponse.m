#import "IMWorkflowShareResponse.h"

static BOOL IMWorkflowShareStringOrNull(id value, BOOL allowNull) {
	return [value isKindOfClass:[NSString class]] || (allowNull && value == [NSNull null]);
}

@interface IMWorkflowShareResponse ()
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, copy, nullable) NSString *workflowDescription;
@property (nonatomic, copy) NSString *trigger;
@property (nonatomic, copy) NSArray<IMWorkflowStep *> *steps;
@end

@implementation IMWorkflowShareResponse

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	if (!dictionary[@"name"] || !dictionary[@"description"] || !dictionary[@"steps"] || !dictionary[@"trigger"] ||
	    !IMWorkflowShareStringOrNull(dictionary[@"name"], YES) ||
	    !IMWorkflowShareStringOrNull(dictionary[@"description"], YES) ||
	    ![dictionary[@"trigger"] isKindOfClass:[NSString class]] ||
	    ![@[ @"AssetCreate", @"AssetMetadataExtraction" ] containsObject:dictionary[@"trigger"]] ||
	    ![dictionary[@"steps"] isKindOfClass:[NSArray class]]) {
		return nil;
	}
	NSArray *rawSteps = dictionary[@"steps"];
	NSMutableArray<IMWorkflowStep *> *steps = [NSMutableArray arrayWithCapacity:rawSteps.count];
	for (id raw in rawSteps) {
		if (![raw isKindOfClass:[NSDictionary class]]) return nil;
		NSDictionary *stepDictionary = raw;
		if (!stepDictionary[@"method"] || !stepDictionary[@"config"] ||
		    (![stepDictionary[@"config"] isKindOfClass:[NSDictionary class]] && stepDictionary[@"config"] != [NSNull null])) {
			return nil;
		}
		if ([stepDictionary[@"config"] isKindOfClass:[NSDictionary class]] &&
		    ![NSJSONSerialization isValidJSONObject:stepDictionary[@"config"]]) {
			return nil;
		}
		id enabled = stepDictionary[@"enabled"];
		if (enabled && (![enabled isKindOfClass:[NSNumber class]] ||
		                ([(NSNumber *)enabled doubleValue] != 0.0 && [(NSNumber *)enabled doubleValue] != 1.0))) {
			return nil;
		}
		IMWorkflowStep *step = [IMWorkflowStep stepWithResponseDictionary:stepDictionary];
		if (!step) return nil;
		[steps addObject:step];
	}
	IMWorkflowShareResponse *response = [[self alloc] init];
	id name = dictionary[@"name"];
	id description = dictionary[@"description"];
	response.name = [name isKindOfClass:[NSString class]] ? [name copy] : nil;
	response.workflowDescription = [description isKindOfClass:[NSString class]] ? [description copy] : nil;
	response.trigger = [dictionary[@"trigger"] copy];
	response.steps = [steps copy];
	return response;
}

@end
