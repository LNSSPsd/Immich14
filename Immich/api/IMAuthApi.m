#import "IMAuthApi.h"
#import "IMApiClient.h"
#import "IMSession.h"
#import "common.h"

@implementation IMAuthApi

+ (void)loginWithBaseURL:(NSURL *)baseURL
                    email:(NSString *)email
                 password:(NSString *)password
               completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	[client POST:@"/auth/login"
	        body:@{ @"email": email, @"password": password }
	  completion:^(id _Nullable json, NSError *_Nullable error) {
		    [client invalidate];
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
			                                    userInfo:@{ NSLocalizedDescriptionKey: _(@"Malformed login response.") }]);
			    return;
		    }
		    [[IMSession shared] startWithBaseURL:baseURL accessToken:token userId:userId];
		    completion(YES, nil);
	    }];
}

+ (void)loginWithBaseURL:(NSURL *)baseURL
                   apiKey:(NSString *)apiKey
               completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	client.overrideAPIKey = apiKey;
	[client GET:@"/users/me"
	       query:nil
	  completion:^(id _Nullable json, NSError *_Nullable error) {
		    [client invalidate]; 
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(NO, error);
			    return;
		    }
		    id userId = ((NSDictionary *)json)[@"id"];
		    [[IMSession shared] startWithBaseURL:baseURL
		                                   apiKey:apiKey
		                                   userId:[userId isKindOfClass:[NSString class]] ? userId : nil];
		    completion(YES, nil);
	    }];
}

+ (void)validateTokenWithCompletion:(void (^)(BOOL valid))completion {
	[self validateSessionWithCompletion:^(BOOL valid, BOOL authRejected) {
		completion(valid);
	}];
}

+ (void)validateSessionWithCompletion:(void (^)(BOOL valid, BOOL authRejected))completion {
	if ([IMSession shared].authKind == IMSessionAuthKindAPIKey) {
		[[IMApiClient shared] GET:@"/users/me"
		                     query:nil
		                completion:^(id _Nullable json, NSError *_Nullable error) {
			    if (!error && [json isKindOfClass:[NSDictionary class]]) {
				    completion(YES, NO);
				    return;
			    }
			    NSInteger status = [IMApiClient HTTPStatusForError:error];
			    completion(NO, status == 401 || status == 403);
		    }];
		return;
	}
	[[IMApiClient shared] POST:@"/auth/validateToken"
	                       body:nil
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (!error && [json isKindOfClass:[NSDictionary class]]) {
			    BOOL valid = [json[@"authStatus"] boolValue];
			    completion(valid, !valid); 
			    return;
		    }
		    NSInteger status = [IMApiClient HTTPStatusForError:error];
		    completion(NO, status == 401 || status == 403);
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
