#import "RootViewController.h"
#import "common.h"
#import "IMAuthApi.h"
#import "IMSession.h"
#import "TimelineViewController.h"

@implementation RootViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	NSArray<NSString *> *titles = @[ _(@"Timeline"), _(@"Search"), _(@"Albums"), _(@"Settings") ];
	NSArray<NSString *> *symbols = @[ @"photo.on.rectangle", @"magnifyingglass", @"rectangle.stack", @"gearshape" ];

	NSMutableArray<UIViewController *> *tabs = [NSMutableArray array];
	[titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger i, BOOL *stop) {
		UIViewController *vc;
		if ([title isEqualToString:_(@"Settings")]) {
			vc = [self settingsPlaceholder];
		} else if ([title isEqualToString:_(@"Timeline")]) {
			vc = [[TimelineViewController alloc] init];
		} else {
			vc = [self placeholderWithTitle:title];
		}
		UIImage *img = nil;
		if (@available(iOS 13.0, *)) {
			img = [UIImage systemImageNamed:symbols[i]];
		}
		vc.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:img tag:i];
		[tabs addObject:[[UINavigationController alloc] initWithRootViewController:vc]];
	}];

	self.viewControllers = tabs;
}

- (UIViewController *)placeholderWithTitle:(NSString *)title {
	UIViewController *vc = [[UIViewController alloc] init];
	vc.title = title;
	if (@available(iOS 13.0, *)) {
		vc.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		vc.view.backgroundColor = UIColor.whiteColor;
	}

	UILabel *label = [[UILabel alloc] init];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = [NSString stringWithFormat:_(@"%@ — not implemented yet"), title];
	label.textColor = UIColor.grayColor;
	[vc.view addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[label.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
		[label.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor],
	]];
	return vc;
}

- (UIViewController *)settingsPlaceholder {
	UIViewController *vc = [self placeholderWithTitle:_(@"Settings")];

	UIButton *logoutButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[logoutButton setTitle:_(@"Log Out") forState:UIControlStateNormal];
	logoutButton.translatesAutoresizingMaskIntoConstraints = NO;
	[logoutButton addTarget:self action:@selector(logoutTapped) forControlEvents:UIControlEventTouchUpInside];
	[vc.view addSubview:logoutButton];
	[NSLayoutConstraint activateConstraints:@[
		[logoutButton.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
		[logoutButton.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor constant:24],
	]];
	return vc;
}

- (void)logoutTapped {
	[IMAuthApi logoutWithCompletion:^{
	}];
}

@end
