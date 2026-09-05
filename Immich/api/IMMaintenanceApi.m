#import "IMMaintenanceApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMMaintenanceAPIError(NSString *message, NSInteger code) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:code
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The maintenance request failed.") }];
}

static void IMMaintenanceCompleteOnMain(void (^completion)(id _Nullable value, NSError *_Nullable error),
	                                       id _Nullable value,
	                                       NSError *_Nullable error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(value, error); });
}

@implementation IMMaintenanceApi

+ (nullable NSURLSessionTask *)loginWithToken:(NSString *)token
	                                    completion:(void (^)(IMMaintenanceAuth *_Nullable, NSError *_Nullable))completion {
	IMMaintenanceLoginRequest *request = [IMMaintenanceLoginRequest requestWithToken:token];
	if (!request) {
		IMMaintenanceCompleteOnMain(completion, nil, IMMaintenanceAPIError(_(@"The maintenance token is invalid."), 1));
		return nil;
	}
	return [self loginWithRequest:request completion:completion];
}

+ (nullable NSURLSessionTask *)loginWithRequest:(IMMaintenanceLoginRequest *)request
	                                      completion:(void (^)(IMMaintenanceAuth *_Nullable, NSError *_Nullable))completion {
	if (![request isKindOfClass:[IMMaintenanceLoginRequest class]]) {
		IMMaintenanceCompleteOnMain(completion, nil, IMMaintenanceAPIError(_(@"A valid maintenance login request is required."), 1));
		return nil;
	}
	return [[IMApiClient shared] POST:@"/admin/maintenance/login"
	                              body:request.requestDictionary
	                        completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMMaintenanceAuth *auth = [IMMaintenanceAuth authWithDictionary:json];
		completion(auth, auth ? nil : IMMaintenanceAPIError(_(@"The server returned an invalid maintenance identity."), 2));
	}];
}

@end
