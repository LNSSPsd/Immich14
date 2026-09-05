#import <UIKit/UIKit.h>
#import "common.h"
#import "AppDelegate.h"
#import "IMBackupDaemon.h"
#include <string.h>

NSNotificationName const IMSessionDidChangeNotification = @"IMSessionDidChangeNotification";

int main(int argc, char *argv[]) {
	@autoreleasepool {
#if IM_TROLLSTORE
		if (argc > 1 && strcmp(argv[1], "--daemon") == 0) {
			return IMBackupDaemonMain();
		}
#endif
		return UIApplicationMain(argc, argv, nil,
		                         NSStringFromClass([AppDelegate class]));
	}
}
