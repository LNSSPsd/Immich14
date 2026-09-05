#import "IMWorkflowApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMWorkflowError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:0
	                        userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSError *IMWorkflowMalformedResponse(void) {
	return IMWorkflowError(_(@"The server returned an invalid workflow response."));
}

static void IMWorkflowAsyncFailure(void (^completion)(void)) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(); });
}

static NSArray<NSDictionary *> *_Nullable IMWorkflowStepDictionaries(NSArray<IMWorkflowStep *> *steps,
	                                                                    NSError **error) {
	if (![steps isKindOfClass:[NSArray class]]) {
		if (error) *error = IMWorkflowError(_(@"Workflow steps must be an array."));
		return nil;
	}
	NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:steps.count];
	for (id value in steps) {
		IMWorkflowStep *step = [value isKindOfClass:[IMWorkflowStep class]] ? value : nil;
		if (!step || step.method.length == 0) {
			if (error) *error = IMWorkflowError(_(@"Each workflow step needs a method."));
			return nil;
		}
		[result addObject:[step requestDictionary]];
	}
	return [result copy];
}

static void IMWorkflowParseResponse(id json,
	                                    NSError *requestError,
	                                    void (^completion)(IMWorkflow *_Nullable workflow,
	                                                       NSError *_Nullable error)) {
	if (requestError) {
		completion(nil, requestError);
		return;
	}
	if (![json isKindOfClass:[NSDictionary class]]) {
		completion(nil, IMWorkflowMalformedResponse());
		return;
	}
	IMWorkflow *workflow = [IMWorkflow workflowWithResponseDictionary:json];
	completion(workflow, workflow ? nil : IMWorkflowMalformedResponse());
}

static void IMWorkflowParseShareResponse(id json,
	                                      NSError *requestError,
	                                      void (^completion)(IMWorkflowShareResponse *_Nullable response,
	                                                         NSError *_Nullable error)) {
	if (requestError) {
		completion(nil, requestError);
		return;
	}
	IMWorkflowShareResponse *response = [IMWorkflowShareResponse responseWithDictionary:json];
	completion(response, response ? nil : IMWorkflowMalformedResponse());
}

@implementation IMWorkflowApi

+ (void)workflowsWithEnabled:(NSNumber *)enabled
                   completion:(void (^)(NSArray<IMWorkflow *> *, NSError *))completion {
	NSDictionary *query = enabled ? @{ @"enabled": enabled.boolValue ? @"true" : @"false" } : nil;
	[[IMApiClient shared] GET:@"/workflows" query:query completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMWorkflowMalformedResponse());
			return;
		}
		completion([IMWorkflow workflowsWithResponseArray:json], nil);
	}];
}

+ (void)workflowsWithCompletion:(void (^)(NSArray<IMWorkflow *> *, NSError *))completion {
	[self workflowsWithEnabled:nil completion:completion];
}

+ (void)allWorkflowsWithCompletion:(void (^)(NSArray<IMWorkflow *> *, NSError *))completion {
	[self workflowsWithCompletion:completion];
}

+ (void)workflowWithId:(NSString *)workflowId
            completion:(void (^)(IMWorkflow *, NSError *))completion {
	if (![workflowId isKindOfClass:[NSString class]] || workflowId.length == 0) {
		NSError *error = IMWorkflowError(_(@"A workflow ID is required."));
		IMWorkflowAsyncFailure(^{ completion(nil, error); });
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/workflows/%@", workflowId];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		IMWorkflowParseResponse(json, error, completion);
	}];
}

+ (void)workflowShareWithId:(NSString *)workflowId
                  completion:(void (^)(IMWorkflowShareResponse *, NSError *))completion {
	if (![workflowId isKindOfClass:[NSString class]] || workflowId.length == 0) {
		NSError *error = IMWorkflowError(_(@"A workflow ID is required."));
		IMWorkflowAsyncFailure(^{ completion(nil, error); });
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/workflows/%@/share", workflowId];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		IMWorkflowParseShareResponse(json, error, completion);
	}];
}

+ (void)workflowTriggersWithCompletion:(void (^)(NSArray<IMWorkflowTrigger *> *, NSError *))completion {
	[[IMApiClient shared] GET:@"/workflows/triggers" query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMWorkflowError(_(@"The server returned invalid workflow triggers.")));
			return;
		}
		completion([IMWorkflowTrigger triggersWithResponseArray:json], nil);
	}];
}

+ (void)createWorkflowWithName:(NSString *)name
                    description:(NSString *)description
                        trigger:(NSString *)trigger
                        enabled:(BOOL)enabled
                          steps:(NSArray<IMWorkflowStep *> *)steps
                     completion:(void (^)(IMWorkflow *, NSError *))completion {
	if (![trigger isKindOfClass:[NSString class]] || trigger.length == 0) {
		NSError *error = IMWorkflowError(_(@"Choose a workflow trigger."));
		IMWorkflowAsyncFailure(^{ completion(nil, error); });
		return;
	}
	NSError *stepError = nil;
	NSArray<NSDictionary *> *stepDictionaries = IMWorkflowStepDictionaries(steps, &stepError);
	if (!stepDictionaries) {
		IMWorkflowAsyncFailure(^{ completion(nil, stepError); });
		return;
	}
	NSMutableDictionary *body = [@{
		@"trigger": trigger,
		@"enabled": @(enabled),
		@"steps": stepDictionaries,
	} mutableCopy];
	if (name != nil) body[@"name"] = name.length ? name : [NSNull null];
	if (description != nil) body[@"description"] = description.length ? description : [NSNull null];
	[[IMApiClient shared] POST:@"/workflows" body:body completion:^(id json, NSError *error) {
		IMWorkflowParseResponse(json, error, completion);
	}];
}

+ (void)updateWorkflowId:(NSString *)workflowId
                     name:(NSString *)name
              description:(NSString *)description
                  trigger:(NSString *)trigger
                  enabled:(NSNumber *)enabled
                    steps:(NSArray<IMWorkflowStep *> *)steps
               completion:(void (^)(IMWorkflow *, NSError *))completion {
	if (![workflowId isKindOfClass:[NSString class]] || workflowId.length == 0) {
		NSError *error = IMWorkflowError(_(@"A workflow ID is required."));
		IMWorkflowAsyncFailure(^{ completion(nil, error); });
		return;
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"name"] = name ?: [NSNull null];
	body[@"description"] = description ?: [NSNull null];
	if (trigger.length) body[@"trigger"] = trigger;
	if (enabled != nil) body[@"enabled"] = @([enabled boolValue]);
	if (steps != nil) {
		NSError *stepError = nil;
		NSArray<NSDictionary *> *stepDictionaries = IMWorkflowStepDictionaries(steps, &stepError);
		if (!stepDictionaries) {
			IMWorkflowAsyncFailure(^{ completion(nil, stepError); });
			return;
		}
		body[@"steps"] = stepDictionaries;
	}
	NSString *path = [NSString stringWithFormat:@"/workflows/%@", workflowId];
	[[IMApiClient shared] PUT:path body:body completion:^(id json, NSError *error) {
		IMWorkflowParseResponse(json, error, completion);
	}];
}

+ (void)setWorkflowId:(NSString *)workflowId
              enabled:(BOOL)enabled
           completion:(void (^)(IMWorkflow *, NSError *))completion {
	if (![workflowId isKindOfClass:[NSString class]] || workflowId.length == 0) {
		NSError *error = IMWorkflowError(_(@"A workflow ID is required."));
		IMWorkflowAsyncFailure(^{ completion(nil, error); });
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/workflows/%@", workflowId];
	[[IMApiClient shared] PUT:path body:@{ @"enabled": @(enabled) } completion:^(id json, NSError *error) {
		IMWorkflowParseResponse(json, error, completion);
	}];
}

+ (void)deleteWorkflowId:(NSString *)workflowId
               completion:(void (^)(BOOL, NSError *))completion {
	if (![workflowId isKindOfClass:[NSString class]] || workflowId.length == 0) {
		NSError *error = IMWorkflowError(_(@"A workflow ID is required."));
		IMWorkflowAsyncFailure(^{ completion(NO, error); });
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/workflows/%@", workflowId];
	[[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

@end
