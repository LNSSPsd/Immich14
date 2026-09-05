#import "RootViewController.h"
#import "common.h"
#import "TimelineViewController.h"
#import "SearchViewController.h"
#import "AlbumsViewController.h"
#import "SyncViewController.h"
#import "SettingsViewController.h"
#import "MapViewController.h"
#import "MemoriesViewController.h"
#import "LockedPhotosViewController.h"
#import "StacksViewController.h"
#import "IMAlbumApi.h"
#import "IMSearchApi.h"
#import "IMUserApi.h"
#import "IMServerApi.h"
#import "IMMapApi.h"
#import "IMMemoryApi.h"
#import "IMForegroundSync.h"
#import "NotificationsViewController.h"
#import "IMNotificationApi.h"
#import "IMUserPreferencesApi.h"

@implementation RootViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	NSArray<NSString *> *titles = @[ _(@"Timeline"), _(@"Search"), _(@"Albums"), _(@"Map"), _(@"Memories"), _(@"Stacks"), _(@"Locked"), _(@"Notifications"), _(@"Sync"), _(@"Settings") ];
	BOOL sfSymbols2;
	if (@available(iOS 14.0, *)) {
		sfSymbols2 = YES;
	} else {
		sfSymbols2 = NO;
	}
	NSArray<NSString *> *symbols = @[
		@"photo.on.rectangle", @"magnifyingglass", @"rectangle.stack", @"map", @"sparkles", @"square.stack.3d.up", @"lock", @"bell",
		sfSymbols2 ? @"arrow.triangle.2.circlepath" : @"arrow.2.circlepath",
		sfSymbols2 ? @"gearshape" : @"gear"
	];

	NSMutableArray<UIViewController *> *tabs = [NSMutableArray array];
	[titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
		UIViewController *vc;
		if ([title isEqualToString:_(@"Settings")]) {
			vc = [[SettingsViewController alloc] init];
		} else if ([title isEqualToString:_(@"Timeline")]) {
			vc = [[TimelineViewController alloc] init];
		} else if ([title isEqualToString:_(@"Search")]) {
			vc = [[SearchViewController alloc] init];
		} else if ([title isEqualToString:_(@"Map")]) {
			vc = [[MapViewController alloc] init];
		} else if ([title isEqualToString:_(@"Memories")]) {
			vc = [[MemoriesViewController alloc] init];
		} else if ([title isEqualToString:_(@"Locked")]) {
			vc = [[LockedPhotosViewController alloc] init];
		} else if ([title isEqualToString:_(@"Notifications")]) {
			vc = [[NotificationsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
		} else if ([title isEqualToString:_(@"Stacks")]) {
			vc = [[StacksViewController alloc] init];
		} else if ([title isEqualToString:_(@"Sync")]) {
			vc = [[SyncViewController alloc] init];
		} else {
			vc = [[AlbumsViewController alloc] init];
		}
		UIImage *img = nil;
		if (@available(iOS 13.0, *)) {
			img = [UIImage systemImageNamed:symbols[i]];
		}
		vc.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:img tag:i];
		[tabs addObject:[[UINavigationController alloc] initWithRootViewController:vc]];
	}];

	self.viewControllers = tabs;
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(notificationStoreChanged)
	                                             name:IMNotificationsDidChangeNotification
	                                           object:nil];
	[self updateNotificationsBadge];

	[self prefetchTabData];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)notificationStoreChanged {
	[self updateNotificationsBadge];
}

- (void)updateNotificationsBadge {
	NSInteger unread = [IMNotificationApi cachedUnreadCount];
	for (UIViewController *controller in self.viewControllers) {
		UINavigationController *navigation = [controller isKindOfClass:[UINavigationController class]] ? (UINavigationController *)controller : nil;
		if ([navigation.viewControllers.firstObject isKindOfClass:[NotificationsViewController class]]) {
			navigation.tabBarItem.badgeValue = unread > 0 ? [@(unread) stringValue] : nil;
			break;
		}
	}
}

- (void)prefetchTabData {
	[IMForegroundSync shared];

	[IMAlbumApi allAlbumsWithCompletion:^(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error) {
	}];
	[IMSearchApi allPeopleWithCompletion:^(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error) {
	}];
	[IMSearchApi assetsByCityWithCompletion:^(NSArray<IMAsset *> *_Nullable assets, NSArray<NSString *> *_Nullable cityNames,
	                                          NSError *_Nullable error) {
	}];
	[IMMapApi markersWithCompletion:^(NSArray<IMMapMarker *> *_Nullable markers, NSError *_Nullable error) {
	}];
	[IMMemoryApi allMemoriesWithCompletion:^(NSArray<IMMemory *> *_Nullable memories, NSError *_Nullable error) {
	}];
	[IMNotificationApi notificationsWithUnreadOnly:NO completion:^(NSArray<IMNotification *> *_Nullable notifications, NSError *_Nullable error) {
	}];
	[IMUserPreferencesApi preferencesWithCompletion:^(IMUserPreferences *_Nullable preferences, NSError *_Nullable error) {
	}];
	[IMUserApi currentUserWithCompletion:^(IMUser *_Nullable user, NSError *_Nullable error) {
	}];
	[IMServerApi serverVersionWithCompletion:^(NSString *_Nullable versionString, NSError *_Nullable error) {
	}];
	[IMServerApi serverStorageWithCompletion:^(IMServerStorage *_Nullable storage, NSError *_Nullable error) {
	}];
}

@end
