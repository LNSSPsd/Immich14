#import "AdminUsersViewController.h"
#import "IMAdminApi.h"
#import "IMApiClient.h"
#import "AdminJobsViewController.h"
#import "AdminLibrariesViewController.h"
#import "AdminServerViewController.h"
#import "AdminBackupsViewController.h"
#import "AdminIntegrityViewController.h"
#import "AdminUserPreferencesViewController.h"
#import "SystemMetadataViewController.h"
#import "AdminUtilitiesViewController.h"
#import "WorkflowsViewController.h"
#import "common.h"

static NSError *IMAdminUIError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The server returned an invalid user.")}];
}

@interface AdminUsersViewController ()
@property (nonatomic, copy) NSArray<IMAdminUser *> *users;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic) BOOL showingDeleted;
@end

@implementation AdminUsersViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Administration");
	self.users = @[];
	self.showingDeleted = NO;
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createTapped)];
	UIBarButtonItem *tools = [[UIBarButtonItem alloc] initWithTitle:_(@"Tools") style:UIBarButtonItemStylePlain target:self action:@selector(toolsTapped)];
	self.navigationItem.rightBarButtonItems = @[add, tools];
	self.navigationItem.leftItemsSupplementBackButton = YES;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Deleted")
	                                                                         style:UIBarButtonItemStylePlain
	                                                                        target:self
	                                                                        action:@selector(toggleDeletedFilter)];
	self.navigationItem.leftBarButtonItem.accessibilityLabel = _(@"Show deleted users");
}

- (void)toggleDeletedFilter {
	self.showingDeleted = !self.showingDeleted;
	self.navigationItem.leftBarButtonItem.title = self.showingDeleted ? _(@"Active") : _(@"Deleted");
	self.navigationItem.leftBarButtonItem.accessibilityLabel = self.showingDeleted ? _(@"Show active users") : _(@"Show deleted users");
	[self reload];
}

- (void)jobsTapped {
	[self.navigationController pushViewController:[[AdminJobsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}

- (void)toolsTapped {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Administration Tools") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Jobs and queues") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf jobsTapped];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"External libraries") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminUsersViewController *self = weakSelf;
		if (self) [self.navigationController pushViewController:[[AdminLibrariesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Server statistics") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminUsersViewController *self = weakSelf;
		if (self) [self.navigationController pushViewController:[[AdminServerViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"System metadata") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminUsersViewController *self = weakSelf;
		if (self) [self.navigationController pushViewController:[[SystemMetadataViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Administrator utilities") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminUsersViewController *self = weakSelf;
		if (self) [self.navigationController pushViewController:[[AdminUtilitiesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Database backups") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminUsersViewController *self = weakSelf;
		if (self) [self.navigationController pushViewController:[[AdminBackupsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Workflows") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminUsersViewController *self = weakSelf;
		if (self) [self.navigationController pushViewController:[[WorkflowsViewController alloc] init] animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Integrity reports") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminUsersViewController *self = weakSelf;
		if (self) [self.navigationController pushViewController:[[AdminIntegrityViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[IMAdminApi usersIncludingDeleted:self.showingDeleted completion:^(NSArray<IMAdminUser *> *_Nullable users, NSError *_Nullable error) {
		 dispatch_async(dispatch_get_main_queue(), ^{
			 typeof(self) strongSelf = weakSelf;
			 if (!strongSelf) return;
			 [strongSelf.refresh endRefreshing];
			 if (!error && users) { strongSelf.users = users; [strongSelf.tableView reloadData]; }
			 else if (error) { [strongSelf showError:error]; }
		 });
	}];
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server rejected this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Administration") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)createTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Create User") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Email"); field.keyboardType = UIKeyboardTypeEmailAddress; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Name"); }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Password"); field.secureTextEntry = YES; }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Quota bytes (blank = unlimited)");
		field.keyboardType = UIKeyboardTypeNumberPad;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Create") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *email = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *name = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *password = alert.textFields[2].text ?: @"";
		NSString *quotaText = alert.textFields[3].text ?: @"";
		BOOL quotaValid = NO;
		NSNumber *quota = [weakSelf quotaNumberFromText:quotaText valid:&quotaValid];
		if (!quotaValid) {
			[weakSelf showError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Quota must be a non-negative number of bytes.")}]];
			return;
		}
		if (!email.length || !name.length || password.length < 1) {
			[weakSelf showError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Enter an email, name, and password.")}]];
			return;
		}
		[IMAdminApi createUserWithEmail:email name:name password:password isAdmin:NO quotaSizeInBytes:quota completion:^(IMAdminUser *user, NSError *error) {
			if (error || !user) { dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showError:error]; }); return; }
			[weakSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleAdminForUser:(IMAdminUser *)user {
	__weak typeof(self) weakSelf = self;
	[IMAdminApi updateUserId:user.userId isAdmin:!user.isAdmin completion:^(IMAdminUser *updated, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (error || !updated) { [weakSelf showError:error]; return; }
			[weakSelf reload];
		});
	}];
}

- (void)showActionsForUser:(IMAdminUser *)user {
	if (!user) return;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:user.name.length ? user.name : user.email
	                                                                 message:user.email
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	if (user.deletedAt.length == 0) {
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Edit user") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[weakSelf editUser:user];
		}]];
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"User preferences") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			AdminUsersViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			AdminUserPreferencesViewController *controller = [[AdminUserPreferencesViewController alloc] initWithUserId:user.userId userName:user.name.length ? user.name : user.email];
			[strongSelf.navigationController pushViewController:controller animated:YES];
		}]];
		[sheet addAction:[UIAlertAction actionWithTitle:user.shouldChangePassword ? _(@"Clear password-change requirement") : _(@"Require password change")
		                                           style:UIAlertActionStyleDefault
		                                         handler:^(UIAlertAction *action) {
			[weakSelf togglePasswordRequirementForUser:user];
		}]];
	} else {
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Restore user") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[weakSelf restoreUser:user];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Asset statistics") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf showStatisticsForUser:user];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Activity heatmap") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf showHeatmapForUser:user];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Sessions") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf showSessionsForUser:user];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (NSNumber *)quotaNumberFromText:(NSString *)text valid:(BOOL *)valid {
	NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (value.length == 0) {
		if (valid) *valid = YES;
		return nil;
	}
	NSScanner *scanner = [NSScanner scannerWithString:value];
	scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@""];
	unsigned long long parsed = 0;
	BOOL ok = [scanner scanUnsignedLongLong:&parsed] && scanner.isAtEnd && parsed <= 9007199254740991ULL;
	if (valid) *valid = ok;
	return ok ? @(parsed) : nil;
}

- (void)editUser:(IMAdminUser *)user {
	if (!user || user.deletedAt.length > 0) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Edit user")
	                                                                 message:_(@"Password is optional and is only changed when filled in. Leave quota, avatar color, or storage label blank to clear it.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Email");
		field.text = user.email;
		field.keyboardType = UIKeyboardTypeEmailAddress;
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Name");
		field.text = user.name;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"New password (optional)");
		field.secureTextEntry = YES;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Quota bytes (blank = unlimited)");
		field.keyboardType = UIKeyboardTypeNumberPad;
		if (user.quotaSizeInBytes > 0) field.text = [NSString stringWithFormat:@"%lld", user.quotaSizeInBytes];
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Avatar color (primary, blue, ...)");
		field.text = user.avatarColor ?: @"";
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Storage label");
		field.text = user.storageLabel ?: @"";
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *email = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSString *name = [alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSString *password = alert.textFields[2].text ?: @"";
		NSString *quotaText = alert.textFields[3].text ?: @"";
		NSString *avatarColor = [alert.textFields[4].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSString *storageLabel = [alert.textFields[5].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		BOOL quotaValid = NO;
		NSNumber *quota = [weakSelf quotaNumberFromText:quotaText valid:&quotaValid];
		if (!quotaValid) {
			[weakSelf showError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Quota must be a non-negative number of bytes.")}]];
			return;
		}
		NSMutableDictionary<NSString *, id> *fields = [NSMutableDictionary dictionary];
		if (![email isEqualToString:user.email]) fields[@"email"] = email;
		if (![name isEqualToString:user.name]) fields[@"name"] = name;
		if (password.length > 0) fields[@"password"] = password;
		NSString *oldQuota = user.quotaSizeInBytes > 0 ? [NSString stringWithFormat:@"%lld", user.quotaSizeInBytes] : @"";
		if (![quotaText isEqualToString:oldQuota]) fields[@"quotaSizeInBytes"] = quota ?: [NSNull null];
		if (![avatarColor isEqualToString:user.avatarColor ?: @""]) fields[@"avatarColor"] = avatarColor.length ? avatarColor : [NSNull null];
		if (![storageLabel isEqualToString:user.storageLabel ?: @""]) fields[@"storageLabel"] = storageLabel.length ? storageLabel : [NSNull null];
		if (fields.count == 0) return;
		[IMAdminApi updateUserId:user.userId fields:fields completion:^(IMAdminUser *updated, NSError *error) {
			if (error || !updated) { [weakSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid user.")}]]; }
			else [weakSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)togglePasswordRequirementForUser:(IMAdminUser *)user {
	if (!user || user.deletedAt.length > 0) return;
	__weak typeof(self) weakSelf = self;
	[IMAdminApi updateUserId:user.userId fields:@{ @"shouldChangePassword": @(!user.shouldChangePassword) } completion:^(IMAdminUser *updated, NSError *error) {
		if (error || !updated) [weakSelf showError:error ?: IMAdminUIError(_(@"The server returned an invalid user."))];
		else [weakSelf reload];
	}];
}

- (void)restoreUser:(IMAdminUser *)user {
	if (!user || user.deletedAt.length == 0) return;
	__weak typeof(self) weakSelf = self;
	[IMAdminApi restoreUserId:user.userId completion:^(IMAdminUser *restored, NSError *error) {
		if (error || !restored) [weakSelf showError:error ?: IMAdminUIError(_(@"The server returned an invalid user."))];
		else [weakSelf reload];
	}];
}

- (void)showStatisticsForUser:(IMAdminUser *)user {
	if (!user) return;
	__weak typeof(self) weakSelf = self;
	[IMAdminApi statisticsForUserId:user.userId isFavorite:nil isTrashed:nil visibility:nil completion:^(IMAdminUserStatistics *statistics, NSError *error) {
		if (!weakSelf) return;
		NSString *message = error.localizedDescription ?: _(@"The server returned invalid user statistics.");
		if (!error && statistics) {
			message = [NSString stringWithFormat:_(@"Images: %@\nVideos: %@\nTotal: %@"),
			           [weakSelf formattedInteger:statistics.images],
			           [weakSelf formattedInteger:statistics.videos],
			           [weakSelf formattedInteger:statistics.total]];
		}
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Asset statistics") message:message preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[weakSelf presentViewController:alert animated:YES completion:nil];
	}];
}

- (NSString *)formattedInteger:(NSInteger)value {
	NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
	formatter.numberStyle = NSNumberFormatterDecimalStyle;
	return [formatter stringFromNumber:@(value)] ?: [NSString stringWithFormat:@"%ld", (long)value];
}

- (void)showHeatmapForUser:(IMAdminUser *)user {
	if (!user) return;
	__weak typeof(self) weakSelf = self;
	[IMAdminApi calendarHeatmapForUserId:user.userId fromDate:nil toDate:nil type:@"Upload" completion:^(IMCalendarHeatmap *heatmap, NSError *error) {
		AdminUsersViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *message = error.localizedDescription ?: _(@"The server returned invalid activity data.");
		if (!error && heatmap) {
			IMCalendarHeatmapEntry *peak = nil;
			for (IMCalendarHeatmapEntry *entry in heatmap.series) {
				if (!peak || entry.count > peak.count) peak = entry;
			}
			message = [NSString stringWithFormat:_(@"Uploads: %@\nPeriod: %@ – %@"),
			           [strongSelf formattedInteger:heatmap.totalCount], heatmap.fromDate, heatmap.toDate];
			if (peak) message = [message stringByAppendingFormat:_(@"\nMost active: %@ (%@)"), peak.date, [strongSelf formattedInteger:peak.count]];
		}
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Activity heatmap") message:message preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[strongSelf presentViewController:alert animated:YES completion:nil];
	}];
}

- (void)showSessionsForUser:(IMAdminUser *)user {
	if (!user) return;
	__weak typeof(self) weakSelf = self;
	[IMAdminApi sessionsForUserId:user.userId completion:^(NSArray<IMSessionInfo *> *sessions, NSError *error) {
		if (!weakSelf) return;
		NSString *message = error.localizedDescription;
		if (!error) {
			NSMutableArray<NSString *> *lines = [NSMutableArray array];
			NSUInteger limit = sessions.count < 20 ? sessions.count : 20;
			for (NSUInteger i = 0; i < limit; i++) {
				IMSessionInfo *session = sessions[i];
				NSString *device = session.deviceType.length ? session.deviceType : _(@"Unknown device");
				if (session.deviceOS.length) device = [NSString stringWithFormat:_(@"%@ · %@"), device, session.deviceOS];
				if (session.isCurrent) device = [NSString stringWithFormat:_(@"%@ · %@"), device, _(@"current")];
				if (session.updatedAt.length) device = [NSString stringWithFormat:_(@"%@\n%@"), device, session.updatedAt];
				[lines addObject:device];
			}
			if (sessions.count > limit) [lines addObject:[NSString stringWithFormat:_(@"… and %lu more"), (unsigned long)(sessions.count - limit)]];
			message = lines.count ? [lines componentsJoinedByString:@"\n\n"] : _(@"No sessions.");
		}
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Sessions") message:message ?: _(@"No sessions.") preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[weakSelf presentViewController:alert animated:YES completion:nil];
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.users.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"admin-user";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	IMAdminUser *user = self.users[indexPath.row];
	cell.textLabel.text = user.name.length ? user.name : user.email;
	NSString *status = user.status.length ? user.status : _(@"active");
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@", user.email, user.deletedAt.length ? [NSString stringWithFormat:_(@" · %@"), _(@"deleted")] : [NSString stringWithFormat:_(@" · %@"), status]];
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = user.isAdmin;
	toggle.enabled = user.deletedAt.length == 0;
	toggle.tag = indexPath.row;
	[toggle addTarget:self action:@selector(adminSwitchChanged:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	return cell;
}

- (void)adminSwitchChanged:(UISwitch *)sender {
	if (sender.tag >= 0 && sender.tag < (NSInteger)self.users.count) [self toggleAdminForUser:self.users[sender.tag]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= 0 && indexPath.row < (NSInteger)self.users.count) {
		[self showActionsForUser:self.users[indexPath.row]];
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.users.count) return NO;
	return self.users[indexPath.row].deletedAt.length == 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete) return;
	IMAdminUser *user = self.users[indexPath.row];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete User?") message:user.email preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[IMAdminApi deleteUserId:user.userId force:NO completion:^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{ if (error || !success) [weakSelf showError:error]; else [weakSelf reload]; });
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
