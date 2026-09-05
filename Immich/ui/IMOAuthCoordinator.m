#import "IMOAuthCoordinator.h"
#import "IMOAuthApi.h"
#import "IMApiClient.h"
#import "IMSession.h"
#import "common.h"
#import <AuthenticationServices/AuthenticationServices.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

typedef NS_ENUM(NSInteger, IMOAuthCoordinatorFlow) {
	IMOAuthCoordinatorFlowNone = 0,
	IMOAuthCoordinatorFlowLogin,
	IMOAuthCoordinatorFlowLink,
};

static NSError *IMOAuthCoordinatorError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The OAuth request could not be completed.") }];
}

static NSString *IMOAuthBase64URL(NSData *data) {
	NSString *encoded = [data base64EncodedStringWithOptions:0];
	encoded = [encoded stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
	encoded = [encoded stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	while ([encoded hasSuffix:@"="]) {
		encoded = [encoded substringToIndex:encoded.length - 1];
	}
	return encoded;
}

static NSString *IMOAuthRandomString(NSUInteger byteCount, NSError **error) {
	if (byteCount == 0) {
		if (error) *error = IMOAuthCoordinatorError(_(@"Unable to create OAuth state."));
		return nil;
	}
	NSMutableData *data = [NSMutableData dataWithLength:byteCount];
	if (SecRandomCopyBytes(kSecRandomDefault, byteCount, data.mutableBytes) != errSecSuccess) {
		if (error) *error = IMOAuthCoordinatorError(_(@"Unable to create secure OAuth state."));
		return nil;
	}
	return IMOAuthBase64URL(data);
}

static NSString *IMOAuthCodeChallenge(NSString *verifier) {
	NSData *data = [verifier dataUsingEncoding:NSUTF8StringEncoding];
	if (data.length == 0) {
		return nil;
	}
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	return IMOAuthBase64URL([NSData dataWithBytes:digest length:sizeof(digest)]);
}

static BOOL IMOAuthCallbackURLShapeIsValid(NSURL *url) {
	if (![url isKindOfClass:[NSURL class]] ||
	    ![url.scheme.lowercaseString isEqualToString:@"app.immich"] ||
	    url.host.length > 0 ||
	    ![url.path isEqualToString:@"/oauth-callback"]) {
		return NO;
	}
	return YES;
}

static BOOL IMOAuthServerURLIsValid(NSURL *url) {
	return [url isKindOfClass:[NSURL class]] &&
	       [@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString] &&
	       url.host.length > 0;
}

static NSArray<NSString *> *IMOAuthQueryValues(NSURLComponents *components, NSString *name) {
	NSMutableArray<NSString *> *values = [NSMutableArray array];
	for (NSURLQueryItem *item in components.queryItems) {
		if ([item.name isEqualToString:name] && [item.value isKindOfClass:[NSString class]]) {
			[values addObject:item.value];
		}
	}
	return values.copy;
}

@interface IMOAuthCoordinator () <ASWebAuthenticationPresentationContextProviding>
@property (nonatomic, strong, nullable) ASWebAuthenticationSession *webSession;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *codeVerifier;
@property (nonatomic, copy, nullable) NSURL *baseURL;
@property (nonatomic, weak, nullable) UIViewController *presentingViewController;
@property (nonatomic) IMOAuthCoordinatorFlow flow;
@property (nonatomic, copy, nullable) IMOAuthLoginCompletion loginCompletion;
@property (nonatomic, copy, nullable) IMOAuthLinkCompletion linkCompletion;
@end

@implementation IMOAuthCoordinator

+ (instancetype)shared {
	static IMOAuthCoordinator *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[self alloc] init];
	});
	return shared;
}

- (BOOL)isActive {
	return self.flow != IMOAuthCoordinatorFlowNone;
}

- (BOOL)startLoginFromViewController:(UIViewController *)presentingViewController
	                         baseURL:(NSURL *)baseURL
	                      completion:(IMOAuthLoginCompletion)completion {
	if (self.isActive) {
		if (completion) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(NO, IMOAuthCoordinatorError(_(@"Another OAuth sign-in is already in progress.")));
			});
		}
		return NO;
	}
	if (![presentingViewController isKindOfClass:[UIViewController class]] ||
	    !IMOAuthServerURLIsValid(baseURL)) {
		if (completion) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(NO, IMOAuthCoordinatorError(_(@"A valid server URL is required for OAuth sign-in.")));
			});
		}
		return NO;
	}
	self.flow = IMOAuthCoordinatorFlowLogin;
	self.baseURL = baseURL;
	self.presentingViewController = presentingViewController;
	self.loginCompletion = [completion copy];
	self.linkCompletion = nil;
	NSError *randomError = nil;
	self.state = IMOAuthRandomString(32, &randomError);
	self.codeVerifier = IMOAuthRandomString(64, &randomError);
	NSString *challenge = IMOAuthCodeChallenge(self.codeVerifier);
	if (!self.state || !self.codeVerifier || !challenge) {
		[self failCurrentLogin:randomError ?: IMOAuthCoordinatorError(_(@"Unable to create a secure OAuth transaction."))];
		return NO;
	}
	__weak typeof(self) weakSelf = self;
	[IMOAuthApi authorizeWithBaseURL:baseURL
	                      redirectURI:IMOAuthApi.nativeRedirectURI
	                             state:self.state
	                     codeChallenge:challenge
	                        completion:^(IMOAuthAuthorizeResponse *response, NSError *error) {
		IMOAuthCoordinator *strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.isActive || strongSelf.flow != IMOAuthCoordinatorFlowLogin) return;
		if (error || !response) {
			[strongSelf failCurrentLogin:error ?: IMOAuthCoordinatorError(_(@"The server did not return an OAuth authorization URL."))];
			return;
		}
		[strongSelf presentAuthorizationURL:[NSURL URLWithString:response.url]];
	}];
	return YES;
}

- (BOOL)startLinkFromViewController:(UIViewController *)presentingViewController
	                      completion:(IMOAuthLinkCompletion)completion {
	if (self.isActive) {
		if (completion) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(nil, IMOAuthCoordinatorError(_(@"Another OAuth transaction is already in progress.")));
			});
		}
		return NO;
	}
	NSURL *baseURL = [IMSession shared].baseURL;
	if (![presentingViewController isKindOfClass:[UIViewController class]] ||
	    ![IMSession shared].isLoggedIn || !IMOAuthServerURLIsValid(baseURL)) {
		if (completion) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(nil, IMOAuthCoordinatorError(_(@"Sign in before linking an OAuth account.")));
			});
		}
		return NO;
	}
	self.flow = IMOAuthCoordinatorFlowLink;
	self.baseURL = baseURL;
	self.presentingViewController = presentingViewController;
	self.loginCompletion = nil;
	self.linkCompletion = [completion copy];
	NSError *randomError = nil;
	self.state = IMOAuthRandomString(32, &randomError);
	self.codeVerifier = IMOAuthRandomString(64, &randomError);
	NSString *challenge = IMOAuthCodeChallenge(self.codeVerifier);
	if (!self.state || !self.codeVerifier || !challenge) {
		[self failCurrentLink:randomError ?: IMOAuthCoordinatorError(_(@"Unable to create a secure OAuth transaction."))];
		return NO;
	}
	__weak typeof(self) weakSelf = self;
	[IMOAuthApi authorizeWithBaseURL:baseURL
	                      redirectURI:IMOAuthApi.nativeRedirectURI
	                             state:self.state
	                     codeChallenge:challenge
	                        completion:^(IMOAuthAuthorizeResponse *response, NSError *error) {
		IMOAuthCoordinator *strongSelf = weakSelf;
		if (!strongSelf || !strongSelf.isActive || strongSelf.flow != IMOAuthCoordinatorFlowLink) return;
		if (error || !response) {
			[strongSelf failCurrentLink:error ?: IMOAuthCoordinatorError(_(@"The server did not return an OAuth authorization URL."))];
			return;
		}
		[strongSelf presentAuthorizationURL:[NSURL URLWithString:response.url]];
	}];
	return YES;
}

- (void)presentAuthorizationURL:(NSURL *)url {
	if (!url || (![url.scheme.lowercaseString isEqualToString:@"http"] &&
	             ![url.scheme.lowercaseString isEqualToString:@"https"]) || url.host.length == 0) {
		if (self.flow == IMOAuthCoordinatorFlowLogin) {
			[self failCurrentLogin:IMOAuthCoordinatorError(_(@"The server returned an invalid OAuth authorization URL."))];
		} else if (self.flow == IMOAuthCoordinatorFlowLink) {
			[self failCurrentLink:IMOAuthCoordinatorError(_(@"The server returned an invalid OAuth authorization URL."))];
		}
		return;
	}
	__weak typeof(self) weakSelf = self;
	ASWebAuthenticationSession *session = [[ASWebAuthenticationSession alloc]
	    initWithURL:url
	callbackURLScheme:@"app.immich"
 completionHandler:^(NSURL *callbackURL, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			IMOAuthCoordinator *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (callbackURL) {
				[strongSelf handleCallbackURL:callbackURL];
			} else if (strongSelf.isActive) {
				NSError *cancelError = error ?: IMOAuthCoordinatorError(_(@"OAuth sign-in was cancelled."));
				if (strongSelf.flow == IMOAuthCoordinatorFlowLogin) {
					[strongSelf failCurrentLogin:cancelError];
				} else {
					[strongSelf failCurrentLink:cancelError];
				}
			}
		});
	}];
	if (@available(iOS 13.0, *)) {
		session.presentationContextProvider = self;
		session.prefersEphemeralWebBrowserSession = NO;
	}
	self.webSession = session;
	if (![session start]) {
		self.webSession = nil;
		NSError *error = IMOAuthCoordinatorError(_(@"Unable to open the OAuth sign-in page."));
		if (self.flow == IMOAuthCoordinatorFlowLogin) {
			[self failCurrentLogin:error];
		} else {
			[self failCurrentLink:error];
		}
	}
}

- (BOOL)handleCallbackURL:(NSURL *)url {
	if (![url isKindOfClass:[NSURL class]] ||
	    ![url.scheme.lowercaseString isEqualToString:@"app.immich"]) {
		return NO;
	}
	if (!IMOAuthCallbackURLShapeIsValid(url)) {
		if (self.isActive) {
			NSError *error = IMOAuthCoordinatorError(_(@"The OAuth callback URL is invalid."));
			if (self.flow == IMOAuthCoordinatorFlowLogin) [self failCurrentLogin:error];
			else [self failCurrentLink:error];
		}
		return YES;
	}
	if (!self.isActive) {
		return YES;
	}
	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	NSArray<NSString *> *errorValues = IMOAuthQueryValues(components, @"error");
	NSArray<NSString *> *errorDescriptionValues = IMOAuthQueryValues(components, @"error_description");
	NSArray<NSString *> *stateValues = IMOAuthQueryValues(components, @"state");
	NSArray<NSString *> *codeValues = IMOAuthQueryValues(components, @"code");
	NSString *errorCode = errorValues.firstObject;
	NSString *errorDescription = errorDescriptionValues.firstObject;
	NSString *callbackState = stateValues.firstObject;
	NSString *code = codeValues.firstObject;
	if (errorCode.length > 0) {
		NSString *message = errorDescription.length > 0 ? errorDescription : _(@"The OAuth provider rejected the request.");
		NSError *error = IMOAuthCoordinatorError(message);
		if (self.flow == IMOAuthCoordinatorFlowLogin) [self failCurrentLogin:error];
		else [self failCurrentLink:error];
		return YES;
	}
	if (stateValues.count != 1 || codeValues.count != 1 || errorValues.count > 1 ||
	    errorDescriptionValues.count > 1 || callbackState.length == 0 ||
	    ![callbackState isEqualToString:self.state] || code.length == 0) {
		NSError *error = IMOAuthCoordinatorError(_(@"The OAuth callback state or authorization code is invalid."));
		if (self.flow == IMOAuthCoordinatorFlowLogin) [self failCurrentLogin:error];
		else [self failCurrentLink:error];
		return YES;
	}
	[self exchangeCallbackURL:url];
	return YES;
}

- (void)exchangeCallbackURL:(NSURL *)callbackURL {
	IMOAuthCoordinatorFlow flow = self.flow;
	NSURL *baseURL = self.baseURL;
	NSString *state = self.state;
	NSString *verifier = self.codeVerifier;
	IMOAuthLoginCompletion loginCompletion = [self.loginCompletion copy];
	IMOAuthLinkCompletion linkCompletion = [self.linkCompletion copy];
	[self clearPendingState];
	if (flow == IMOAuthCoordinatorFlowLogin) {
		[IMOAuthApi finishLoginWithBaseURL:baseURL
	                         callbackURL:callbackURL
	                                state:state
	                          codeVerifier:verifier
	                             completion:^(IMOAuthLoginResponse *response, NSError *error) {
			if (loginCompletion) loginCompletion(response != nil && error == nil, error);
		}];
	} else if (flow == IMOAuthCoordinatorFlowLink) {
		[IMOAuthApi linkWithCallbackURL:callbackURL
	                              state:state
	                        codeVerifier:verifier
	                           completion:^(IMUser *user, NSError *error) {
			if (linkCompletion) linkCompletion(user, error);
		}];
	}
}

- (void)cancel {
	if (!self.isActive) return;
	NSError *error = IMOAuthCoordinatorError(_(@"The OAuth transaction was cancelled."));
	if (self.flow == IMOAuthCoordinatorFlowLogin) {
		[self failCurrentLogin:error];
	} else {
		[self failCurrentLink:error];
	}
}

- (void)failCurrentLogin:(NSError *)error {
	IMOAuthLoginCompletion completion = [self.loginCompletion copy];
	[self clearPendingState];
	if (completion) completion(NO, error);
}

- (void)failCurrentLink:(NSError *)error {
	IMOAuthLinkCompletion completion = [self.linkCompletion copy];
	[self clearPendingState];
	if (completion) completion(nil, error);
}

- (void)clearPendingState {
	ASWebAuthenticationSession *session = self.webSession;
	self.flow = IMOAuthCoordinatorFlowNone;
	self.webSession = nil;
	[session cancel];
	self.state = nil;
	self.codeVerifier = nil;
	self.baseURL = nil;
	self.presentingViewController = nil;
	self.loginCompletion = nil;
	self.linkCompletion = nil;
}

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
	(void)session;
	UIWindow *window = self.presentingViewController.viewIfLoaded.window;
	if (!window) {
		window = [UIApplication sharedApplication].keyWindow;
	}
	if (!window) {
		window = [UIApplication sharedApplication].windows.firstObject;
	}
	if (!window) {
		window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	}
	return window;
}

@end
