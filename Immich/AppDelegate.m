#import "AppDelegate.h"
#import "common.h"
#import "RootViewController.h"
#import "LoginViewController.h"
#import "IMSession.h"
#import "IMAuthApi.h"
#import "IMForegroundSync.h"
#import "IMBackupDaemon.h"
#import "IMPrefs.h"
#import "IMOAuthCoordinator.h"
#import "SharedLinkGuestViewController.h"

@interface AppDelegate ()
@property (nonatomic) UIBackgroundTaskIdentifier syncBackgroundTask;
@property (nonatomic, copy, nullable) NSURL *pendingPublicLinkURL;
- (nullable NSURL *)normalizedPublicLinkURL:(nullable NSURL *)url;
- (BOOL)publicLinkPathIsValid:(nullable NSString *)path;
- (void)presentPublicLinkURL:(NSURL *)url;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.syncBackgroundTask = UIBackgroundTaskInvalid;
	[IMBackupDaemon.shared registerBackgroundTasks];
	[IMBackupDaemon.shared start];
	self.window.rootViewController = [self rootViewController];
	[self.window makeKeyAndVisible];
	NSURL *launchURL = launchOptions[UIApplicationLaunchOptionsURLKey];
	NSURL *launchPublicURL = [self normalizedPublicLinkURL:launchURL];
	if (!launchPublicURL) {
		NSDictionary *activities = launchOptions[UIApplicationLaunchOptionsUserActivityDictionaryKey];
		for (id value in activities.allValues) {
			if (![value isKindOfClass:[NSUserActivity class]]) continue;
			NSURL *candidate = [self normalizedPublicLinkURL:[(NSUserActivity *)value webpageURL]];
			if (candidate) {
				launchPublicURL = candidate;
				break;
			}
		}
	}
	if (launchPublicURL) {
		self.pendingPublicLinkURL = launchPublicURL;
		dispatch_async(dispatch_get_main_queue(), ^{
			NSURL *url = self.pendingPublicLinkURL;
			self.pendingPublicLinkURL = nil;
			if (url) [self presentPublicLinkURL:url];
		});
	}

	[[NSNotificationCenter defaultCenter]
	    addObserver:self
	       selector:@selector(sessionDidChange:)
	           name:IMSessionDidChangeNotification
	         object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncDidFinish:) name:IMForegroundSyncDidFinishNotification object:nil];

	if ([IMSession shared].isLoggedIn) {
		[IMAuthApi validateSessionWithCompletion:^(BOOL valid, BOOL authRejected) {
			if (!valid && authRejected) {
				[[IMSession shared] logout]; 
			}
		}];
	}
	return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	if (!IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) return;
	__weak typeof(self) weakSelf = self;
	self.syncBackgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
		[IMForegroundSync.shared cancel];
		if (weakSelf.syncBackgroundTask != UIBackgroundTaskInvalid) {
			[application endBackgroundTask:weakSelf.syncBackgroundTask];
			weakSelf.syncBackgroundTask = UIBackgroundTaskInvalid;
		}
	}];
	[IMBackupDaemon.shared applicationDidEnterBackground];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
	(void)application;
	[IMBackupDaemon.shared applicationWillEnterForeground];
}

- (BOOL)application:(UIApplication *)application
    openURL:(NSURL *)url
    options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
	(void)application;
	(void)options;
	NSURL *publicURL = [self normalizedPublicLinkURL:url];
	if (publicURL) {
		[self presentPublicLinkURL:publicURL];
		return YES;
	}
	return [IMOAuthCoordinator.shared handleCallbackURL:url];
}

- (BOOL)application:(UIApplication *)application
    continueUserActivity:(NSUserActivity *)userActivity
    restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> *_Nullable restorableObjects))restorationHandler {
	(void)application;
	(void)restorationHandler;
	NSURL *publicURL = [self normalizedPublicLinkURL:userActivity.webpageURL];
	if (!publicURL) return NO;
	[self presentPublicLinkURL:publicURL];
	return YES;
}

- (nullable NSURL *)normalizedPublicLinkURL:(NSURL *)url {
	if (![url isKindOfClass:[NSURL class]]) return nil;
	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	NSString *scheme = components.scheme.lowercaseString;
	if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
		return components.host.length && components.user.length == 0 && components.password.length == 0 &&
		       [self publicLinkPathIsValid:components.path] ? components.URL : nil;
	}
	if (![scheme isEqualToString:@"immich-share"]) return nil;
	if (components.user.length > 0 || components.password.length > 0) return nil;
	for (NSURLQueryItem *item in components.queryItems) {
		if (![item.name isEqualToString:@"url"] || item.value.length == 0) continue;
		NSURL *embedded = [NSURL URLWithString:item.value];
		NSURLComponents *embeddedComponents = [NSURLComponents componentsWithURL:embedded resolvingAgainstBaseURL:NO];
		NSString *embeddedScheme = embeddedComponents.scheme.lowercaseString;
		if (([embeddedScheme isEqualToString:@"http"] || [embeddedScheme isEqualToString:@"https"]) && embeddedComponents.host.length > 0 &&
		    embeddedComponents.user.length == 0 && embeddedComponents.password.length == 0 &&
		    [self publicLinkPathIsValid:embeddedComponents.path]) {
			return embeddedComponents.URL;
		}
	}

	NSString *routePath = components.path ?: @"";
	NSString *host = components.host;
	if (([host.lowercaseString isEqualToString:@"share"] || [host.lowercaseString isEqualToString:@"s"]) && routePath.length > 0) {
		routePath = [NSString stringWithFormat:@"/%@%@", host.lowercaseString, [routePath hasPrefix:@"/"] ? routePath : [@"/" stringByAppendingString:routePath]];
		host = nil;
	}
	if (routePath.length == 0 || [routePath isEqualToString:@"/"] || ![self publicLinkPathIsValid:routePath]) return nil;
	NSURL *serverURL = nil;
	if (host.length > 0) {
		NSURLComponents *server = [[NSURLComponents alloc] init];
		server.scheme = @"https";
		server.host = host;
		server.port = components.port;
		serverURL = server.URL;
	} else {
		NSString *raw = [[NSUserDefaults standardUserDefaults] stringForKey:@"IMLastServerURL"];
		NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (trimmed.length > 0 && ![trimmed hasPrefix:@"http://"] && ![trimmed hasPrefix:@"https://"]) trimmed = [@"http://" stringByAppendingString:trimmed];
		while ([trimmed hasSuffix:@"/"]) trimmed = [trimmed substringToIndex:trimmed.length - 1];
		if ([trimmed.lowercaseString hasSuffix:@"/api"]) trimmed = [trimmed substringToIndex:trimmed.length - 4];
		serverURL = [NSURL URLWithString:trimmed];
	}
	if (!serverURL || serverURL.host.length == 0) return nil;
	NSURLComponents *result = [NSURLComponents componentsWithURL:serverURL resolvingAgainstBaseURL:NO];
	result.path = routePath;
	result.query = components.percentEncodedQuery;
	result.fragment = nil;
	return result.URL;
}

- (BOOL)publicLinkPathIsValid:(NSString *)path {
	if (![path isKindOfClass:[NSString class]]) return NO;
	NSArray<NSString *> *components = [path pathComponents];
	for (NSUInteger index = 0; index + 1 < components.count; index++) {
		NSString *segment = components[index].lowercaseString;
		if (([segment isEqualToString:@"share"] || [segment isEqualToString:@"s"]) && components[index + 1].length > 0 &&
		    ![components[index + 1] isEqualToString:@"/"]) {
			return YES;
		}
	}
	return NO;
}

- (void)presentPublicLinkURL:(NSURL *)url {
	if (!url) return;
	UIViewController *presenter = self.window.rootViewController;
	while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
		presenter = presenter.presentedViewController;
	}
	SharedLinkGuestViewController *guest = [[SharedLinkGuestViewController alloc] initWithPublicURL:url];
	UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:guest];
	navigation.modalPresentationStyle = UIModalPresentationFullScreen;
	[presenter presentViewController:navigation animated:YES completion:nil];
}

- (void)syncDidFinish:(NSNotification *)notification {
	if (self.syncBackgroundTask != UIBackgroundTaskInvalid) {
		[[UIApplication sharedApplication] endBackgroundTask:self.syncBackgroundTask];
		self.syncBackgroundTask = UIBackgroundTaskInvalid;
	}
}

- (UIViewController *)rootViewController {
	if ([IMSession shared].isLoggedIn) {
		return [[RootViewController alloc] init];
	}
	return [[UINavigationController alloc] initWithRootViewController:[[LoginViewController alloc] init]];
}

- (void)sessionDidChange:(NSNotification *)note {
	self.window.rootViewController = [self rootViewController];
}

@end
