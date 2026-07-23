#import "RootViewController.h"
#import "common.h"
#import "TimelineViewController.h"
#import "SearchViewController.h"
#import "AlbumsViewController.h"
#import "SettingsViewController.h"
#import "IMAlbumApi.h"
#import "IMSearchApi.h"
#import "IMUserApi.h"
#import "IMServerApi.h"

@implementation RootViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	NSArray<NSString *> *titles = @[ _(@"Timeline"), _(@"Search"), _(@"Albums"), _(@"Settings") ];
	NSArray<NSString *> *symbols = @[ @"photo.on.rectangle", @"magnifyingglass", @"rectangle.stack", @"gearshape" ];

	NSMutableArray<UIViewController *> *tabs = [NSMutableArray array];
	[titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
		UIViewController *vc;
		if ([title isEqualToString:_(@"Settings")]) {
			vc = [[SettingsViewController alloc] init];
		} else if ([title isEqualToString:_(@"Timeline")]) {
			vc = [[TimelineViewController alloc] init];
		} else if ([title isEqualToString:_(@"Search")]) {
			vc = [[SearchViewController alloc] init];
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

	[self prefetchTabData];
}

- (void)prefetchTabData {
	[IMAlbumApi allAlbumsWithCompletion:^(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error) {
	}];
	[IMSearchApi allPeopleWithCompletion:^(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error) {
	}];
	[IMSearchApi assetsByCityWithCompletion:^(NSArray<IMAsset *> *_Nullable assets, NSArray<NSString *> *_Nullable cityNames,
	                                          NSError *_Nullable error) {
	}];
	[IMUserApi currentUserWithCompletion:^(IMUser *_Nullable user, NSError *_Nullable error) {
	}];
	[IMServerApi serverVersionWithCompletion:^(NSString *_Nullable versionString, NSError *_Nullable error) {
	}];
	[IMServerApi serverStorageWithCompletion:^(IMServerStorage *_Nullable storage, NSError *_Nullable error) {
	}];
}

@end
