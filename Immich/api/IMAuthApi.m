#import "IMAuthApi.h"
#import "IMApiClient.h"
#import "IMSession.h"
#import "common.h"
#import <math.h>

static NSError *IMAuthMalformedResponse(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The server returned an invalid authentication response.")}];
}

static NSError *IMAuthSignupValidationError(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"Enter a valid server URL, email, name, and password.")}];
}

static BOOL IMAuthSignupEmailIsValid(NSString *email) {
	if (![email isKindOfClass:[NSString class]] || email.length == 0) return NO;
	static NSRegularExpression *expression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:
	    @"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
	                                                         options:0
	                                                           error:NULL];
	});
	return [expression firstMatchInString:email options:0 range:NSMakeRange(0, email.length)] != nil;
}

static BOOL IMAuthSignupBaseURLIsValid(NSURL *baseURL) {
	if (![baseURL isKindOfClass:[NSURL class]] || baseURL.host.length == 0) return NO;
	return [baseURL.scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
	       [baseURL.scheme caseInsensitiveCompare:@"https"] == NSOrderedSame;
}

@implementation IMAuthApi

+ (void)signUpAdminWithBaseURL:(NSURL *)baseURL
                          email:(NSString *)email
                           name:(NSString *)name
                        password:(NSString *)password
                      completion:(void (^)(IMAdminUser *_Nullable user,
                                           NSError *_Nullable error))completion {
	NSString *trimmedEmail = [email isKindOfClass:[NSString class]]
	    ? [email stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
	    : @"";
	NSString *trimmedName = [name isKindOfClass:[NSString class]]
	    ? [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
	    : @"";
	if (!IMAuthSignupBaseURLIsValid(baseURL) || !IMAuthSignupEmailIsValid(trimmedEmail) ||
	    trimmedName.length == 0 || ![password isKindOfClass:[NSString class]] || password.length == 0) {
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(nil, IMAuthSignupValidationError());
		});
		return;
	}

	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	client.anonymous = YES;
	[client POST:@"/auth/admin-sign-up"
	        body:@{ @"email": trimmedEmail, @"name": trimmedName, @"password": password }
	  completion:^(id _Nullable json, NSError *_Nullable error) {
		[client invalidate];
		if (error) {
			completion(nil, error);
			return;
		}
		IMAdminUser *user = [IMAdminUser userWithResponseDictionary:json];
		completion(user, user ? nil : IMAuthMalformedResponse(_(@"The server returned an invalid administrator response.")));
	}];
}

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
				completion(NO, error ?: IMAuthMalformedResponse(_(@"The server returned an invalid login response.")));
				return;
			}
		    NSDictionary *dict = (NSDictionary *)json;
		    NSString *token = dict[@"accessToken"];
		    NSString *userId = dict[@"userId"];
			if (![token isKindOfClass:[NSString class]] || token.length == 0 ||
			    ![userId isKindOfClass:[NSString class]] || userId.length == 0) {
				completion(NO, IMAuthMalformedResponse(_(@"The server returned an invalid login response.")));
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
				completion(NO, error ?: IMAuthMalformedResponse(_(@"The server returned an invalid API-key response.")));
				return;
			}
			id userId = ((NSDictionary *)json)[@"id"];
			if (![userId isKindOfClass:[NSString class]] || [userId length] == 0) {
				completion(NO, IMAuthMalformedResponse(_(@"The server returned an invalid user response.")));
				return;
			}
			[[IMSession shared] startWithBaseURL:baseURL
		                                   apiKey:apiKey
		                                   userId:userId];
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
			    id authStatus = ((NSDictionary *)json)[@"authStatus"];
			    if (![authStatus isKindOfClass:[NSNumber class]]) {
				    completion(NO, NO);
				    return;
			    }
			    BOOL valid = [authStatus boolValue];
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

+ (void)unlockSessionWithPIN:(NSString *)pin
                   completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	[[IMApiClient shared] POST:@"/auth/session/unlock"
	                       body:@{ @"pinCode": pin }
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		completion(error == nil, error);
	}];
}

+ (void)lockSessionWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	[[IMApiClient shared] POST:@"/auth/session/lock"
	                       body:nil
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		completion(error == nil, error);
	}];
}

+ (void)setupPIN:(NSString *)pin completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	[[IMApiClient shared] POST:@"/auth/pin-code" body:@{ @"pinCode": pin ?: @"" } completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (void)changePIN:(NSString *)newPIN
       currentPIN:(nullable NSString *)currentPIN
         password:(nullable NSString *)password
       completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSMutableDictionary *body = [@{ @"newPinCode": newPIN ?: @"" } mutableCopy];
	if (currentPIN.length > 0) body[@"pinCode"] = currentPIN;
	if (password.length > 0) body[@"password"] = password;
	[[IMApiClient shared] PUT:@"/auth/pin-code" body:body completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (void)resetPINWithPassword:(nullable NSString *)password
                          pin:(nullable NSString *)pin
                   completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	if (password.length > 0) body[@"password"] = password;
	if (pin.length > 0) body[@"pinCode"] = pin;
	[[IMApiClient shared] DELETE:@"/auth/pin-code" body:body completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (void)authStatusWithCompletion:(void (^)(BOOL, BOOL, NSError *))completion {
	[[IMApiClient shared] GET:@"/auth/status" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSDictionary class]]) {
			completion(NO, NO, error ?: IMAuthMalformedResponse(_(@"The server returned an invalid authentication status.")));
			return;
		}
		NSDictionary *status = (NSDictionary *)json;
		if (![status[@"pinCode"] isKindOfClass:[NSNumber class]] ||
		    ![status[@"isElevated"] isKindOfClass:[NSNumber class]]) {
			completion(NO, NO, IMAuthMalformedResponse(_(@"The server returned an invalid authentication status.")));
			return;
		}
		completion([status[@"pinCode"] boolValue], [status[@"isElevated"] boolValue], nil);
	}];
}

@end
