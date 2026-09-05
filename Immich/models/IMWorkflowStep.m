#import "IMWorkflowStep.h"

static id IMWorkflowStepValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMWorkflowStep ()
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy, nullable) NSDictionary *config;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@end

@implementation IMWorkflowStep

+ (nullable instancetype)stepWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id methodValue = IMWorkflowStepValueOrNil(dictionary[@"method"]);
	if (![methodValue isKindOfClass:[NSString class]] || [(NSString *)methodValue length] == 0) {
		return nil;
	}
	IMWorkflowStep *step = [[self alloc] init];
	step.method = [methodValue copy];
	id configValue = IMWorkflowStepValueOrNil(dictionary[@"config"]);
	step.config = [configValue isKindOfClass:[NSDictionary class]] ? [configValue copy] : nil;
	id enabledValue = IMWorkflowStepValueOrNil(dictionary[@"enabled"]);
	step.enabled = enabledValue == nil ? YES : ([enabledValue isKindOfClass:[NSNumber class]] && [enabledValue boolValue]);
	return step;
}

+ (NSArray<IMWorkflowStep *> *)stepsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMWorkflowStep *> *steps = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		if (![value isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		IMWorkflowStep *step = [self stepWithResponseDictionary:value];
		if (step) {
			[steps addObject:step];
		}
	}
	return [steps copy];
}

- (NSDictionary *)requestDictionary {
	return @{
		@"method": self.method ?: @"",
		@"config": self.config ?: [NSNull null],
		@"enabled": @(self.enabled),
	};
}

@end
