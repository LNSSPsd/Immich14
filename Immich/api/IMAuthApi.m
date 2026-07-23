#import "IMAuthApi.h"
#import "IMApiClient.h"
#import "IMSession.h"

@implementation IMAuthApi

+ (void)loginWithBaseURL:(NSURL *)baseURL
                    email:(NSString *)email
                 password:(NSString *)password
               completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	[client POST:@"/auth/login"
	        body:@{ @"email": email, @"password": password }
	  completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(NO, error);
			    return;
		    }
		    NSDictionary *dict = (NSDictionary *)json;
		    NSString *token = dict[@"accessToken"];
		    NSString *userId = dict[@"userId"];
		    if (![token isKindOfClass:[NSString class]] || ![userId isKindOfClass:[NSString class]]) {
			    completion(NO, [NSError errorWithDomain:IMApiErrorDomain
			                                        code:0
			                                    userInfo:@{ NSLocalizedDescriptionKey: @"Malformed login response." }]);
			    return;
		    }
		    [[IMSession shared] startWithBaseURL:baseURL accessToken:token userId:userId];
		    completion(YES, nil);
	    }];
}

+ (void)validateTokenWithCompletion:(void (^)(BOOL valid))completion {
	[[IMApiClient shared] POST:@"/auth/validateToken"
	                       body:nil
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(NO);
			    return;
		    }
		    completion([json[@"authStatus"] boolValue]);
	    }];
}

+ (void)logoutWithCompletion:(void (^)(void))completion {
	[[IMApiClient shared] POST:@"/auth/logout"
	                       body:nil
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		    [[IMSession shared] logout];
		    completion();
	    }];
}

@end
