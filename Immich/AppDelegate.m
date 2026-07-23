#import "AppDelegate.h"
#import "common.h"
#import "RootViewController.h"

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
	return YES;
}

- (UIViewController *)rootViewController {
	return [[RootViewController alloc] init];
}

- (void)sessionDidChange:(NSNotification *)note {
	self.window.rootViewController = [self rootViewController];
}

@end
