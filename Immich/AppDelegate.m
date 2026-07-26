#import "AppDelegate.h"
#import "common.h"
#import "RootViewController.h"
#import "LoginViewController.h"
#import "IMSession.h"
#import "IMAuthApi.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rootViewController = [self rootViewController];
	[self.window makeKeyAndVisible];

	[[NSNotificationCenter defaultCenter]
	    addObserver:self
	       selector:@selector(sessionDidChange:)
	           name:IMSessionDidChangeNotification
	         object:nil];

	if ([IMSession shared].isLoggedIn) {
		[IMAuthApi validateSessionWithCompletion:^(BOOL valid, BOOL authRejected) {
			if (!valid && authRejected) {
				[[IMSession shared] logout]; 
			}
		}];
	}
	return YES;
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
