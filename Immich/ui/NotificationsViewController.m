#import "NotificationsViewController.h"
#import "IMNotificationApi.h"
#import "IMNotification.h"
#import "common.h"

static NSString *const kNotificationCellIdentifier = @"notification-cell";

@interface NotificationsViewController ()
@property (nonatomic, copy) NSArray<IMNotification *> *notifications;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic) BOOL unreadOnly;
@property (nonatomic) NSUInteger generation;
@end

@implementation NotificationsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Notifications");
	self.notifications = [IMNotificationApi cachedNotifications] ?: @[];
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	}
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reloadNotifications) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	self.emptyLabel.adjustsFontForContentSizeCategory = YES;
	self.emptyLabel.text = _(@"No notifications.");
	self.tableView.backgroundView = self.emptyLabel;
	self.navigationItem.leftItemsSupplementBackButton = YES;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"All")
	                                                                         style:UIBarButtonItemStylePlain
	                                                                        target:self
	                                                                        action:@selector(filterTapped)];
	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithTitle:_(@"Mark All") style:UIBarButtonItemStylePlain target:self action:@selector(markAllRead)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteRead)]
	];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(notificationStoreChanged)
	                                             name:IMNotificationsDidChangeNotification
	                                           object:nil];
	[self reloadNotifications];
}

- (void)dealloc {
	[self.task cancel];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self updateBadgeAndControls];
	[self reloadNotifications];
}

- (void)notificationStoreChanged {
	NSArray<IMNotification *> *cached = [IMNotificationApi cachedNotifications];
	if (cached && !self.task) {
		self.notifications = self.unreadOnly ? [cached filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(IMNotification *item, NSDictionary *bindings) { return !item.isRead; }]] : cached;
		[self.tableView reloadData];
	}
	[self updateBadgeAndControls];
}

- (void)updateBadgeAndControls {
	NSInteger unread = [IMNotificationApi cachedUnreadCount];
	self.tabBarItem.badgeValue = unread > 0 ? [@(unread) stringValue] : nil;
	self.navigationItem.leftBarButtonItem.title = self.unreadOnly ? _(@"Unread") : _(@"All");
	self.navigationItem.rightBarButtonItems.firstObject.enabled = unread > 0;
	NSArray<IMNotification *> *cached = [IMNotificationApi cachedNotifications];
	BOOL hasRead = NO;
	for (IMNotification *item in cached) if (item.isRead) { hasRead = YES; break; }
	self.navigationItem.rightBarButtonItems.lastObject.enabled = hasRead;
}

- (void)filterTapped {
	self.unreadOnly = !self.unreadOnly;
	[self reloadNotifications];
}

- (void)reloadNotifications {
	self.generation += 1;
	NSUInteger generation = self.generation;
	[self.task cancel];
	self.task = nil;
	[self.refresh beginRefreshing];
	__weak typeof(self) weakSelf = self;
	self.task = [IMNotificationApi notificationsWithUnreadOnly:self.unreadOnly completion:^(NSArray<IMNotification *> *items, NSError *error) {
		NotificationsViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		strongSelf.task = nil;
		[strongSelf.refresh endRefreshing];
		if (error) {
			strongSelf.emptyLabel.text = error.localizedDescription.length ? error.localizedDescription : _(@"Unable to load notifications. Pull to retry.");
			strongSelf.emptyLabel.hidden = strongSelf.notifications.count > 0;
			if (strongSelf.notifications.count == 0) [strongSelf showError:error];
			return;
		}
		strongSelf.notifications = items ?: @[];
		strongSelf.emptyLabel.text = strongSelf.unreadOnly ? _(@"No unread notifications.") : _(@"No notifications.");
		strongSelf.emptyLabel.hidden = strongSelf.notifications.count > 0;
		[strongSelf.tableView reloadData];
		[strongSelf updateBadgeAndControls];
	}];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Notifications")
	                                                                 message:error.localizedDescription ?: _(@"The server could not load notifications.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)markAllRead {
	if ([IMNotificationApi cachedUnreadCount] == 0) return;
	self.navigationItem.rightBarButtonItems.firstObject.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMNotificationApi setAllNotificationsRead:YES completion:^(BOOL success, NSError *error) {
		NotificationsViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		if (!success || error) {
			strongSelf.navigationItem.rightBarButtonItems.firstObject.enabled = YES;
			[strongSelf showError:error ?: [NSError errorWithDomain:@"IMNotificationApi" code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not mark notifications as read.")}]];
			return;
		}
		[strongSelf reloadNotifications];
	}];
}

- (void)deleteRead {
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	for (IMNotification *item in self.notifications) if (item.isRead) [ids addObject:item.notificationId];
	if (ids.count == 0) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete Read Notifications?")
	                                                                 message:[NSString stringWithFormat:_(@"This will permanently delete %lu notifications."), (unsigned long)ids.count]
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[IMNotificationApi deleteNotificationIds:ids completion:^(BOOL success, NSError *error) {
			NotificationsViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!success || error) { [strongSelf showError:error]; return; }
			[strongSelf reloadNotifications];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)dateStringForNotification:(IMNotification *)notification {
	static NSDateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterShortStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
		formatter.doesRelativeDateFormatting = YES;
	});
	return [formatter stringFromDate:notification.createdAt] ?: @"";
}

- (UIColor *)colorForLevel:(NSString *)level {
	if ([level isEqualToString:@"error"]) return UIColor.systemRedColor;
	if ([level isEqualToString:@"warning"]) return UIColor.systemOrangeColor;
	if ([level isEqualToString:@"success"]) return UIColor.systemGreenColor;
	return UIColor.systemBlueColor;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.notifications.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kNotificationCellIdentifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kNotificationCellIdentifier];
	IMNotification *notification = self.notifications[indexPath.row];
	cell.textLabel.text = notification.title.length ? notification.title : notification.type;
	cell.textLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:17 weight:notification.isRead ? UIFontWeightRegular : UIFontWeightSemibold]];
	cell.textLabel.adjustsFontForContentSizeCategory = YES;
	cell.detailTextLabel.text = notification.notificationDescription.length ? [NSString stringWithFormat:_(@"%@\n%@"), notification.notificationDescription, [self dateStringForNotification:notification]] : [self dateStringForNotification:notification];
	cell.detailTextLabel.numberOfLines = 2;
	cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
	cell.detailTextLabel.textColor = notification.isRead ? UIColor.secondaryLabelColor : [self colorForLevel:notification.level];
	cell.accessoryType = notification.isRead ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
	cell.accessibilityLabel = notification.title;
	cell.accessibilityValue = notification.isRead ? _(@"Read") : _(@"Unread");
	return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 64.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	IMNotification *notification = self.notifications[indexPath.row];
	void (^showDetail)(void) = ^{
		NSString *message = notification.notificationDescription.length ? notification.notificationDescription : _(@"No additional details.");
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:notification.title.length ? notification.title : notification.type message:message preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
	};
	if (notification.isRead) {
		showDetail();
		return;
	}
	__weak typeof(self) weakSelf = self;
	[IMNotificationApi setNotificationId:notification.notificationId read:YES completion:^(IMNotification *updated, NSError *error) {
		NotificationsViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		if (error) { [strongSelf showError:error]; return; }
		if (!strongSelf.unreadOnly) {
			NSUInteger row = [strongSelf.notifications indexOfObject:notification];
			if (row != NSNotFound) [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
		} else {
			[strongSelf reloadNotifications];
		}
		showDetail();
	}];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	IMNotification *notification = self.notifications[indexPath.row];
	__weak typeof(self) weakSelf = self;
	UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:_(@"Delete") handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
		[IMNotificationApi deleteNotificationId:notification.notificationId completion:^(BOOL success, NSError *error) {
			if (success) [weakSelf reloadNotifications];
			completionHandler(success);
		}];
	}];
	UIContextualAction *read = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:notification.isRead ? _(@"Unread") : _(@"Read") handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
		[IMNotificationApi setNotificationId:notification.notificationId read:!notification.isRead completion:^(IMNotification *updated, NSError *error) {
			if (!error) [weakSelf reloadNotifications];
			completionHandler(error == nil);
		}];
	}];
	read.backgroundColor = UIColor.systemBlueColor;
	return [UISwipeActionsConfiguration configurationWithActions:@[delete, read]];
}

@end
