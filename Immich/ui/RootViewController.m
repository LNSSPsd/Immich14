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
#import "IMSession.h"
#import "IMAccountApi.h"

@interface RootViewController ()
@property (nonatomic) BOOL forcedPasswordPromptVisible;
@property (nonatomic) BOOL forcedPasswordRequestInFlight;
@property (nonatomic) BOOL forcedPasswordPromptRetryScheduled;
@property (nonatomic, copy, nullable) NSString *pendingForcedPasswordMessage;
- (void)presentForcedPasswordPromptWithMessage:(nullable NSString *)message;
- (void)scheduleForcedPasswordPromptRetry;
@end

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
		UITabBarItem *tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:img tag:i];
		vc.tabBarItem = tabBarItem;
		UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:vc];
		navigation.tabBarItem = tabBarItem;
		[tabs addObject:navigation];
	}];

	self.viewControllers = tabs;
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(notificationStoreChanged)
	                                             name:IMNotificationsDidChangeNotification
	                                           object:nil];
	[self updateNotificationsBadge];

	[self prefetchTabData];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (![IMSession shared].isLoggedIn || ![IMSession shared].passwordChangeRequired) {
		self.pendingForcedPasswordMessage = nil;
		self.tabBar.userInteractionEnabled = YES;
		return;
	}
	if (self.forcedPasswordPromptVisible && !self.presentedViewController) {
		self.forcedPasswordPromptVisible = NO;
	}
	if (!self.forcedPasswordPromptVisible && !self.forcedPasswordRequestInFlight) {
		[self presentForcedPasswordPromptWithMessage:nil];
	}
}

- (void)presentForcedPasswordPromptWithMessage:(NSString *)message {
	if (![IMSession shared].isLoggedIn || ![IMSession shared].passwordChangeRequired ||
	    self.forcedPasswordPromptVisible || self.forcedPasswordRequestInFlight) {
		return;
	}
	if (!self.viewIfLoaded.window) {
		if (message.length > 0) self.pendingForcedPasswordMessage = message;
		return;
	}
	self.tabBar.userInteractionEnabled = NO;
	if (self.presentedViewController) {
		if (message.length > 0) {
			self.pendingForcedPasswordMessage = message;
		}
		[self scheduleForcedPasswordPromptRetry];
		return;
	}
	if (message.length == 0 && self.pendingForcedPasswordMessage.length > 0) {
		message = self.pendingForcedPasswordMessage;
	}
	self.pendingForcedPasswordMessage = nil;
	self.forcedPasswordPromptVisible = YES;
	NSString *promptMessage = message.length > 0
	    ? message
	    : _(@"Your administrator requires a password change before you can continue.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Change your password")
	                                                                 message:promptMessage
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Current password");
		field.secureTextEntry = YES;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"New password (8+ characters)");
		field.secureTextEntry = YES;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Confirm new password");
		field.secureTextEntry = YES;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Sign Out")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *action) {
		(void)action;
		RootViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.forcedPasswordPromptVisible = NO;
		strongSelf.forcedPasswordRequestInFlight = NO;
		strongSelf.pendingForcedPasswordMessage = nil;
		strongSelf.tabBar.userInteractionEnabled = YES;
		[[IMSession shared] logout];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Change Password")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
		(void)action;
		RootViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSArray<UITextField *> *fields = alert.textFields;
		NSString *current = fields.count > 0 ? (fields[0].text ?: @"") : @"";
		NSString *newPassword = fields.count > 1 ? (fields[1].text ?: @"") : @"";
		NSString *confirmation = fields.count > 2 ? (fields[2].text ?: @"") : @"";
		NSString *validationMessage = nil;
		if (current.length == 0) {
			validationMessage = _(@"Enter your current password.");
		} else if (newPassword.length < 8) {
			validationMessage = _(@"The new password must contain at least 8 characters.");
		} else if (![newPassword isEqualToString:confirmation]) {
			validationMessage = _(@"The new passwords do not match.");
		}
		if (validationMessage.length > 0) {
			strongSelf.forcedPasswordPromptVisible = NO;
			strongSelf.pendingForcedPasswordMessage = validationMessage;
			[strongSelf scheduleForcedPasswordPromptRetry];
			return;
		}
		strongSelf.forcedPasswordPromptVisible = NO;
		strongSelf.forcedPasswordRequestInFlight = YES;
		strongSelf.tabBar.userInteractionEnabled = NO;
		[IMAccountApi changePassword:current
		                 newPassword:newPassword
		            invalidateSessions:NO
		                   completion:^(BOOL success, NSError *_Nullable error) {
			RootViewController *inner = weakSelf;
			if (!inner) return;
			if (success && !error) {
				inner.forcedPasswordRequestInFlight = NO;
				inner.tabBar.userInteractionEnabled = YES;
				[IMSession.shared clearPasswordChangeRequirement];
				inner.forcedPasswordPromptVisible = NO;
				UIAlertController *confirmationAlert = [UIAlertController alertControllerWithTitle:_(@"Password changed")
				                                                                  message:_(@"Your password has been updated.")
				                                                           preferredStyle:UIAlertControllerStyleAlert];
				[confirmationAlert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
				[inner presentViewController:confirmationAlert animated:YES completion:nil];
				return;
			}
			inner.forcedPasswordRequestInFlight = NO;
			inner.tabBar.userInteractionEnabled = YES;
			inner.forcedPasswordPromptVisible = NO;
			NSString *errorMessage = error.localizedDescription.length > 0
			    ? error.localizedDescription
			    : _(@"The server rejected the password change.");
			[inner presentForcedPasswordPromptWithMessage:errorMessage];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)scheduleForcedPasswordPromptRetry {
	if (self.forcedPasswordPromptRetryScheduled) {
		return;
	}
	self.forcedPasswordPromptRetryScheduled = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		RootViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.forcedPasswordPromptRetryScheduled = NO;
		if (strongSelf.presentedViewController) {
			if ([IMSession shared].isLoggedIn && [IMSession shared].passwordChangeRequired) {
				[strongSelf scheduleForcedPasswordPromptRetry];
			} else {
				strongSelf.pendingForcedPasswordMessage = nil;
				strongSelf.tabBar.userInteractionEnabled = YES;
			}
			return;
		}
		NSString *message = strongSelf.pendingForcedPasswordMessage;
		strongSelf.pendingForcedPasswordMessage = nil;
		[strongSelf presentForcedPasswordPromptWithMessage:message];
	});
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
