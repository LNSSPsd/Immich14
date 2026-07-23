#import <UIKit/UIKit.h>
#import "common.h"
#import "AppDelegate.h"

NSNotificationName const IMSessionDidChangeNotification = @"IMSessionDidChangeNotification";

int main(int argc, char *argv[]) {
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil,
		                         NSStringFromClass([AppDelegate class]));
	}
}
