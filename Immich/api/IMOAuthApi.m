#import "IMOAuthApi.h"
#import "IMApiClient.h"
#import "IMSession.h"
#import "common.h"
#include <math.h>

static NSError *IMOAuthValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The OAuth request is invalid.") }];
}

static NSError *IMOAuthMalformedResponseError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The server returned an invalid OAuth response.") }];
}

static BOOL IMOAuthHTTPURL(NSURL *url) {
	return [url isKindOfClass:[NSURL class]] &&
	       ([@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString]) &&
	       url.host.length > 0;
}

static void IMOAuthCompleteAsync(void (^completion)(id _Nullable, NSError *_Nullable),
	                              id _Nullable value,
	                              NSError *_Nullable error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(value, error);
	});
}

static void IMOAuthCompleteBoolAsync(void (^completion)(BOOL, NSError *_Nullable),
	                                  BOOL success,
	                                  NSError *_Nullable error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(success, error);
	});
}

static BOOL IMOAuthUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) {
		return NO;
	}
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
	if (!uuid) {
		return NO;
	}
	NSString *canonical = uuid.UUIDString.lowercaseString;
	return [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMOAuthEmail(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
		return NO;
	}
	NSString *email = (NSString *)value;
	if ([email rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound ||
	    [email rangeOfString:@"\r"].location != NSNotFound ||
	    [email rangeOfString:@"\n"].location != NSNotFound) {
		return NO;
	}
	NSArray<NSString *> *parts = [email componentsSeparatedByString:@"@"];
	if (parts.count != 2 || parts[0].length == 0 || parts[1].length == 0 ||
	    [parts[1] hasPrefix:@"."] || [parts[1] hasSuffix:@"."]) {
		return NO;
	}
	return YES;
}

static BOOL IMOAuthBoolean(id value) {
	return [value isKindOfClass:[NSNumber class]] &&
	       ([(NSNumber *)value doubleValue] == 0.0 || [(NSNumber *)value doubleValue] == 1.0);
}

static BOOL IMOAuthInteger(id value, BOOL nullable) {
	if (nullable && value == [NSNull null]) {
		return YES;
	}
	return [value isKindOfClass:[NSNumber class]] &&
	       isfinite([(NSNumber *)value doubleValue]) &&
	       floor([(NSNumber *)value doubleValue]) == [(NSNumber *)value doubleValue] &&
	       [(NSNumber *)value longLongValue] >= 0;
}

static BOOL IMOAuthDateString(id value, BOOL nullable) {
	if (nullable && value == [NSNull null]) {
		return YES;
	}
	return [value isKindOfClass:[NSString class]] &&
	       [(NSString *)value length] > 0 &&
	       IMDateFromServerTimestamp((NSString *)value) != nil;
}

static BOOL IMOAuthLicense(id value) {
	if (value == [NSNull null]) {
		return YES;
	}
	if (![value isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSDictionary *license = (NSDictionary *)value;
	id licenseKey = license[@"licenseKey"];
	id activationKey = license[@"activationKey"];
	id activatedAt = license[@"activatedAt"];
	if (![licenseKey isKindOfClass:[NSString class]] || [(NSString *)licenseKey length] == 0 ||
	    ![activationKey isKindOfClass:[NSString class]] || [(NSString *)activationKey length] == 0 ||
	    !IMOAuthDateString(activatedAt, NO)) {
		return NO;
	}
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^IM(SV|CL)(-[0-9A-Za-z]{4}){8}$"
	                                                                            options:0
	                                                                              error:NULL];
	NSUInteger matches = [regex numberOfMatchesInString:licenseKey
	                                             options:0
	                                               range:NSMakeRange(0, [(NSString *)licenseKey length])];
	return matches == 1;
}

static BOOL IMOAuthUserResponseIsValid(id value) {
	if (![value isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSDictionary *user = (NSDictionary *)value;
	if (!IMOAuthUUIDv4(user[@"id"]) || !IMOAuthEmail(user[@"email"]) ||
	    ![user[@"name"] isKindOfClass:[NSString class]] ||
	    ![user[@"profileImagePath"] isKindOfClass:[NSString class]] ||
	    ![user[@"avatarColor"] isKindOfClass:[NSString class]] ||
	    ![user[@"profileChangedAt"] isKindOfClass:[NSString class]] ||
	    !IMOAuthDateString(user[@"profileChangedAt"], NO) ||
	    ![user[@"oauthId"] isKindOfClass:[NSString class]] ||
	    !IMOAuthBoolean(user[@"isAdmin"]) ||
	    !IMOAuthBoolean(user[@"shouldChangePassword"]) ||
	    ![user[@"status"] isKindOfClass:[NSString class]] ||
	    ![@[ @"active", @"removing", @"deleted" ] containsObject:user[@"status"]] ||
	    !IMOAuthDateString(user[@"createdAt"], NO) ||
	    !IMOAuthDateString(user[@"updatedAt"], NO) ||
	    !IMOAuthDateString(user[@"deletedAt"], YES) ||
	    !IMOAuthLicense(user[@"license"]) ||
	    !IMOAuthInteger(user[@"quotaSizeInBytes"], YES) ||
	    !IMOAuthInteger(user[@"quotaUsageInBytes"], YES)) {
		return NO;
	}
	if (![user[@"storageLabel"] isKindOfClass:[NSString class]] && user[@"storageLabel"] != [NSNull null]) {
		return NO;
	}
	if (![@[ @"primary", @"pink", @"red", @"yellow", @"blue", @"green", @"purple", @"orange", @"gray", @"amber" ]
	      containsObject:user[@"avatarColor"]]) {
		return NO;
	}
	return YES;
}

static NSDictionary *IMOAuthCallbackBody(NSURL *callbackURL,
	                                        NSString *state,
	                                        NSString *codeVerifier) {
	NSMutableDictionary *body = [@{ @"url": callbackURL.absoluteString } mutableCopy];
	if (state.length > 0) {
		body[@"state"] = state;
	}
	if (codeVerifier.length > 0) {
		body[@"codeVerifier"] = codeVerifier;
	}
	return body;
}

@implementation IMOAuthApi

+ (NSString *)nativeRedirectURI {
	return @"app.immich:///oauth-callback";
}

+ (void)authorizeWithBaseURL:(NSURL *)baseURL
	              redirectURI:(NSString *)redirectURI
	                     state:(NSString *)state
	             codeChallenge:(NSString *)codeChallenge
	                completion:(void (^)(IMOAuthAuthorizeResponse *_Nullable, NSError *_Nullable))completion {
	if (!IMOAuthHTTPURL(baseURL) ||
	    ![redirectURI isKindOfClass:[NSString class]] || redirectURI.length == 0) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"A valid server and redirect URL are required.")));
		return;
	}
	if (state != nil && (![state isKindOfClass:[NSString class]] || state.length == 0)) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"OAuth state cannot be empty.")));
		return;
	}
	if (codeChallenge != nil && (![codeChallenge isKindOfClass:[NSString class]] || codeChallenge.length == 0)) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"OAuth code challenge cannot be empty.")));
		return;
	}
	NSURL *redirectURL = [NSURL URLWithString:redirectURI];
	if (!redirectURL || redirectURL.scheme.length == 0) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"The OAuth redirect URL is invalid.")));
		return;
	}
	NSMutableDictionary *body = [@{ @"redirectUri": redirectURI } mutableCopy];
	if (state.length > 0) {
		body[@"state"] = state;
	}
	if (codeChallenge.length > 0) {
		body[@"codeChallenge"] = codeChallenge;
	}
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	[client POST:@"/oauth/authorize" body:body completion:^(id json, NSError *error) {
		[client invalidate];
		if (error) {
			completion(nil, error);
			return;
		}
		IMOAuthAuthorizeResponse *response = [IMOAuthAuthorizeResponse responseWithDictionary:json];
		completion(response, response ? nil : IMOAuthMalformedResponseError(_(@"The server returned an invalid OAuth authorization URL.")));
	}];
}

+ (void)finishLoginWithBaseURL:(NSURL *)baseURL
	                  callbackURL:(NSURL *)callbackURL
	                         state:(NSString *)state
	                   codeVerifier:(NSString *)codeVerifier
	                      completion:(void (^)(IMOAuthLoginResponse *_Nullable, NSError *_Nullable))completion {
	if (!IMOAuthHTTPURL(baseURL) ||
	    ![callbackURL isKindOfClass:[NSURL class]] || callbackURL.absoluteString.length == 0) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"A valid server and OAuth callback URL are required.")));
		return;
	}
	if (state != nil && (![state isKindOfClass:[NSString class]] || state.length == 0)) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"OAuth state cannot be empty.")));
		return;
	}
	if (codeVerifier != nil && (![codeVerifier isKindOfClass:[NSString class]] || codeVerifier.length == 0)) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"OAuth code verifier cannot be empty.")));
		return;
	}
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	[client POST:@"/oauth/callback"
	        body:IMOAuthCallbackBody(callbackURL, state, codeVerifier)
	  completion:^(id json, NSError *error) {
		[client invalidate];
		if (error) {
			completion(nil, error);
			return;
		}
		IMOAuthLoginResponse *response = [IMOAuthLoginResponse responseWithDictionary:json];
		if (!response) {
			completion(nil, IMOAuthMalformedResponseError(_(@"The server returned an invalid OAuth login response.")));
			return;
		}
		[[IMSession shared] startWithBaseURL:baseURL
		                       accessToken:response.accessToken
		                            userId:response.userId
		             passwordChangeRequired:response.shouldChangePassword && !response.isAdmin];
		completion(response, nil);
	}];
}

+ (void)linkWithCallbackURL:(NSURL *)callbackURL
	                  state:(NSString *)state
	            codeVerifier:(NSString *)codeVerifier
	               completion:(void (^)(IMUser *_Nullable, NSError *_Nullable))completion {
	if (![IMSession shared].isLoggedIn) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"Sign in before linking an OAuth account.")));
		return;
	}
	if (![callbackURL isKindOfClass:[NSURL class]] || callbackURL.absoluteString.length == 0) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"A valid OAuth callback URL is required.")));
		return;
	}
	if (state != nil && (![state isKindOfClass:[NSString class]] || state.length == 0)) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"OAuth state cannot be empty.")));
		return;
	}
	if (codeVerifier != nil && (![codeVerifier isKindOfClass:[NSString class]] || codeVerifier.length == 0)) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"OAuth code verifier cannot be empty.")));
		return;
	}
	[[IMApiClient shared] POST:@"/oauth/link"
	                       body:IMOAuthCallbackBody(callbackURL, state, codeVerifier)
	                 completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (!IMOAuthUserResponseIsValid(json)) {
			completion(nil, IMOAuthMalformedResponseError(_(@"The server returned an invalid linked-user response.")));
			return;
		}
		completion([[IMUser alloc] initWithDictionary:(NSDictionary *)json], nil);
	}];
}

+ (void)unlinkWithCompletion:(void (^)(IMUser *_Nullable, NSError *_Nullable))completion {
	if (![IMSession shared].isLoggedIn) {
		IMOAuthCompleteAsync(completion, nil, IMOAuthValidationError(_(@"Sign in before unlinking an OAuth account.")));
		return;
	}
	[[IMApiClient shared] POST:@"/oauth/unlink" body:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (!IMOAuthUserResponseIsValid(json)) {
			completion(nil, IMOAuthMalformedResponseError(_(@"The server returned an invalid unlinked-user response.")));
			return;
		}
		completion([[IMUser alloc] initWithDictionary:(NSDictionary *)json], nil);
	}];
}

+ (void)backchannelLogoutWithToken:(NSString *)logoutToken
	                    completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (![logoutToken isKindOfClass:[NSString class]] || logoutToken.length == 0 ||
	    [logoutToken rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) {
		IMOAuthCompleteBoolAsync(completion, NO, IMOAuthValidationError(_(@"The OAuth logout token is invalid.")));
		return;
	}
	NSURL *baseURL = [IMSession shared].baseURL;
	if (!IMOAuthHTTPURL(baseURL)) {
		IMOAuthCompleteBoolAsync(completion, NO, IMOAuthValidationError(_(@"A server URL is required for OAuth logout.")));
		return;
	}
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	client.anonymous = YES;
	[client POSTForm:@"/oauth/backchannel-logout"
	          fields:@{ @"logout_token": logoutToken }
	      completion:^(id _Nullable json, NSError *_Nullable error) {
		[client invalidate];
		completion(error == nil, error);
	}];
}

+ (nullable NSURL *)mobileRedirectURLWithBaseURL:(NSURL *)baseURL
	                                  queryItems:(NSArray<NSURLQueryItem *> *)queryItems {
	if (!IMOAuthHTTPURL(baseURL)) return nil;
	NSString *baseString = baseURL.absoluteString;
	while ([baseString hasSuffix:@"/"]) {
		baseString = [baseString substringToIndex:baseString.length - 1];
	}
	NSURL *endpoint = [NSURL URLWithString:[baseString stringByAppendingString:@"/oauth/mobile-redirect"]];
	if (!endpoint) return nil;
	if (queryItems.count == 0) return endpoint;
	for (NSURLQueryItem *item in queryItems) {
		if (![item isKindOfClass:[NSURLQueryItem class]] || item.name.length == 0 ||
		    [item.name rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound ||
		    [item.value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) {
			return nil;
		}
	}
	NSURLComponents *components = [NSURLComponents componentsWithURL:endpoint resolvingAgainstBaseURL:NO];
	components.queryItems = queryItems;
	return components.URL;
}

@end
