#import "IMWorkflow.h"

static id IMWorkflowValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMWorkflow ()
@property (nonatomic, copy) NSString *workflowId;
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, copy, nullable) NSString *workflowDescription;
@property (nonatomic, copy) NSString *trigger;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *createdAt;
@property (nonatomic, copy, nullable) NSString *updatedAt;
@property (nonatomic, copy) NSArray<IMWorkflowStep *> *steps;
@end

@implementation IMWorkflow

+ (nullable instancetype)workflowWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id identifier = IMWorkflowValueOrNil(dictionary[@"id"]);
	id triggerValue = IMWorkflowValueOrNil(dictionary[@"trigger"]);
	if (![identifier isKindOfClass:[NSString class]] || [(NSString *)identifier length] == 0 ||
	    ![triggerValue isKindOfClass:[NSString class]] || [(NSString *)triggerValue length] == 0) {
		return nil;
	}
	IMWorkflow *workflow = [[self alloc] init];
	workflow.workflowId = [identifier copy];
	id nameValue = IMWorkflowValueOrNil(dictionary[@"name"]);
	workflow.name = [nameValue isKindOfClass:[NSString class]] ? [nameValue copy] : nil;
	id descriptionValue = IMWorkflowValueOrNil(dictionary[@"description"]);
	workflow.workflowDescription = [descriptionValue isKindOfClass:[NSString class]] ? [descriptionValue copy] : nil;
	workflow.trigger = [triggerValue copy];
	id enabledValue = IMWorkflowValueOrNil(dictionary[@"enabled"]);
	workflow.enabled = enabledValue == nil ? YES : ([enabledValue isKindOfClass:[NSNumber class]] && [enabledValue boolValue]);
	id createdValue = IMWorkflowValueOrNil(dictionary[@"createdAt"]);
	workflow.createdAt = [createdValue isKindOfClass:[NSString class]] ? [createdValue copy] : nil;
	id updatedValue = IMWorkflowValueOrNil(dictionary[@"updatedAt"]);
	workflow.updatedAt = [updatedValue isKindOfClass:[NSString class]] ? [updatedValue copy] : nil;
	id stepsValue = IMWorkflowValueOrNil(dictionary[@"steps"]);
	workflow.steps = [stepsValue isKindOfClass:[NSArray class]] ? [IMWorkflowStep stepsWithResponseArray:stepsValue] : @[];
	return workflow;
}

+ (NSArray<IMWorkflow *> *)workflowsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMWorkflow *> *workflows = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMWorkflow *workflow = [value isKindOfClass:[NSDictionary class]] ? [self workflowWithResponseDictionary:value] : nil;
		if (workflow) {
			[workflows addObject:workflow];
		}
	}
	return [workflows copy];
}

@end
