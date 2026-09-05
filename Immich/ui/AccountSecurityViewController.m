#import "AccountSecurityViewController.h"
#import "IMAccountApi.h"
#import "IMSessionInfo.h"
#import "IMAPIKey.h"
#import "IMSession.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMSecuritySection) {
	IMSecuritySectionPassword = 0,
	IMSecuritySectionSessions,
	IMSecuritySectionKeys,
	IMSecuritySectionCount,
};

@interface AccountSecurityViewController ()
@property (nonatomic, copy) NSArray<IMSessionInfo *> *sessions;
@property (nonatomic, copy) NSArray<IMAPIKey *> *apiKeys;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL invalidateSessionsOnPasswordChange;
@end

@implementation AccountSecurityViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Account Security");
	self.sessions = @[];
	self.apiKeys = @[];
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.sessions.count || self.apiKeys.count) [self reload];
}

- (void)reload {
	if (self.loading) return;
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	__block NSArray<IMSessionInfo *> *sessions;
	__block NSArray<IMAPIKey *> *keys;
	__block NSError *firstError;
	__block NSInteger pending = 2;
	void (^finish)(void) = ^{
		pending -= 1;
		if (pending != 0) return;
		AccountSecurityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loading = NO;
		[strongSelf.refresh endRefreshing];
		if (sessions) strongSelf.sessions = sessions;
		if (keys) strongSelf.apiKeys = keys;
		[strongSelf.tableView reloadData];
		if (firstError && !sessions && !keys) [strongSelf showError:firstError];
	};
	[IMAccountApi sessionsWithCompletion:^(NSArray<IMSessionInfo *> *items, NSError *error) {
		sessions = items;
		if (error && !firstError) firstError = error;
		finish();
	}];
	void (^keysCompletion)(NSArray<IMAPIKey *> *, NSError *) = ^(NSArray<IMAPIKey *> *items, NSError *error) {
		keys = items;
		if (error && !firstError) firstError = error;
		finish();
	};
	if (IMSession.shared.authKind == IMSessionAuthKindAPIKey) {
		[IMAccountApi currentAPIKeyWithCompletion:^(IMAPIKey *key, NSError *error) {
			keysCompletion(key ? @[ key ] : nil, error);
		}];
	} else {
		[IMAccountApi apiKeysWithCompletion:keysCompletion];
	}
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Account Security") message:error.localizedDescription ?: _(@"The server could not complete this request.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)changePasswordTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Change Password") message:_(@"Use at least 8 characters.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Current password"); field.secureTextEntry = YES; }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"New password"); field.secureTextEntry = YES; }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Repeat new password"); field.secureTextEntry = YES; }];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Change") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *current = alert.textFields[0].text ?: @"";
		NSString *newPassword = alert.textFields[1].text ?: @"";
		NSString *repeat = alert.textFields[2].text ?: @"";
		if (![newPassword isEqualToString:repeat]) {
			[weakSelf showError:[NSError errorWithDomain:@"IMAccountApi" code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"The new passwords do not match.")}]];
			return;
		}
		[IMAccountApi changePassword:current newPassword:newPassword invalidateSessions:weakSelf.invalidateSessionsOnPasswordChange completion:^(BOOL success, NSError *error) {
			AccountSecurityViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!success || error) { [strongSelf showError:error]; return; }
			[strongSelf showMessage:_(@"Password changed.")];
			[strongSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Account Security") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)signOutOtherSessions {
	BOOL hasOther = NO;
	for (IMSessionInfo *session in self.sessions) if (!session.isCurrent) { hasOther = YES; break; }
	if (!hasOther) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Sign Out Other Devices?") message:_(@"All sessions except this device will be revoked.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Sign Out") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[IMAccountApi deleteAllOtherSessionsWithCompletion:^(BOOL success, NSError *error) {
			AccountSecurityViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!success || error) { [strongSelf showError:error]; return; }
			[strongSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)createAPIKey {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Create API Key") message:_(@"Enter comma-separated permissions, for example asset.read,asset.upload.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Name (optional)"); }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Permissions"); field.text = @"asset.read"; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Create") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSArray<NSString *> *raw = [alert.textFields[1].text componentsSeparatedByString:@","];
		NSMutableArray<NSString *> *permissions = [NSMutableArray array];
		for (NSString *permission in raw) {
			NSString *trimmed = [permission stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
			if (trimmed.length) [permissions addObject:trimmed];
		}
		[IMAccountApi createAPIKeyNamed:name permissions:permissions completion:^(IMAPIKey *key, NSString *secret, NSError *error) {
			AccountSecurityViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (error || !key || !secret) { [strongSelf showError:error]; return; }
			UIPasteboard.generalPasteboard.string = secret;
			UIAlertController *secretAlert = [UIAlertController alertControllerWithTitle:_(@"API Key Created") message:[NSString stringWithFormat:_(@"The secret was copied to the clipboard. It is shown only once:\n\n%@"), secret] preferredStyle:UIAlertControllerStyleAlert];
			[secretAlert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
			[strongSelf presentViewController:secretAlert animated:YES completion:nil];
			[strongSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)editAPIKey:(IMAPIKey *)key {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Edit API Key") message:_(@"Permissions are comma-separated.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = key.name; field.placeholder = _(@"Name"); }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = [key.permissions componentsJoinedByString:@","]; field.placeholder = _(@"Permissions"); field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSArray *raw = [alert.textFields[1].text componentsSeparatedByString:@","];
		NSMutableArray *permissions = [NSMutableArray array];
		for (NSString *permission in raw) { NSString *trimmed = [permission stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (trimmed.length) [permissions addObject:trimmed]; }
		[IMAccountApi updateAPIKeyId:key.keyId name:name permissions:permissions completion:^(IMAPIKey *updated, NSError *error) {
			AccountSecurityViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (error || !updated) [strongSelf showError:error]; else [strongSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return IMSecuritySectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case IMSecuritySectionPassword: return 2;
		case IMSecuritySectionSessions: return MAX(1, self.sessions.count);
		case IMSecuritySectionKeys: return MAX(1, self.apiKeys.count);
		default: return 0;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case IMSecuritySectionPassword: return _(@"Password");
		case IMSecuritySectionSessions: return _(@"Authorized Devices");
		case IMSecuritySectionKeys: return _(@"API Keys");
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == IMSecuritySectionKeys) return _(@"API-key secrets are displayed once when created. Store them securely.");
	if (section == IMSecuritySectionSessions) return _(@"Revoking a session signs that device out. The current device cannot be revoked here.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"security-cell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textColor = UIColor.labelColor;
	if (indexPath.section == IMSecuritySectionPassword) {
		if (indexPath.row == 0) {
			cell.textLabel.text = _(@"Change Password");
			cell.detailTextLabel.text = _(@"Update the password used to sign in");
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else {
			cell.textLabel.text = _(@"Sign out other devices after changing");
			cell.detailTextLabel.text = _(@"You can also revoke devices below");
			UISwitch *toggle = [[UISwitch alloc] init];
			toggle.on = self.invalidateSessionsOnPasswordChange;
			[toggle addTarget:self action:@selector(passwordSessionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = toggle;
		}
	} else if (indexPath.section == IMSecuritySectionSessions) {
		if (self.sessions.count == 0) {
			cell.textLabel.text = _(@"No authorized devices found");
			cell.detailTextLabel.text = nil;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			return cell;
		}
		IMSessionInfo *session = self.sessions[indexPath.row];
		cell.textLabel.text = session.deviceType.length ? session.deviceType : _(@"Unknown device");
		NSString *os = session.deviceOS.length ? session.deviceOS : _(@"Unknown OS");
		cell.detailTextLabel.text = session.isCurrent ? [NSString stringWithFormat:_(@"%@ · %@"), os, _(@"Current device")] : os;
		cell.accessoryType = session.isCurrent ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
	} else {
		if (self.apiKeys.count == 0) {
			cell.textLabel.text = _(@"No API keys");
			cell.detailTextLabel.text = _(@"Tap + to create one");
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			return cell;
		}
		IMAPIKey *key = self.apiKeys[indexPath.row];
		cell.textLabel.text = key.name.length ? key.name : _(@"Unnamed API key");
		cell.detailTextLabel.text = [key.permissions componentsJoinedByString:@", "];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	return cell;
}

- (void)passwordSessionSwitchChanged:(UISwitch *)sender {
	self.invalidateSessionsOnPasswordChange = sender.isOn;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *selectedCell = [tableView cellForRowAtIndexPath:indexPath];
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == IMSecuritySectionPassword && indexPath.row == 0) {
		[self changePasswordTapped];
	} else if (indexPath.section == IMSecuritySectionSessions && indexPath.row < (NSInteger)self.sessions.count) {
		IMSessionInfo *session = self.sessions[indexPath.row];
		if (session.isCurrent) return;
		[self sessionActions:session sourceCell:selectedCell];
	} else if (indexPath.section == IMSecuritySectionKeys && indexPath.row < (NSInteger)self.apiKeys.count) {
		[self editAPIKey:self.apiKeys[indexPath.row]];
	}
}

- (void)sessionActions:(IMSessionInfo *)session sourceCell:(nullable UITableViewCell *)sourceCell {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:session.deviceType.length ? session.deviceType : _(@"Authorized Device")
	                                                                  message:session.deviceOS.length ? session.deviceOS : nil
	                                                           preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Lock Session") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[IMAccountApi lockSessionId:session.sessionId completion:^(BOOL success, NSError *error) {
			AccountSecurityViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!success || error) [strongSelf showError:error];
			else [strongSelf showMessage:_(@"The device session was locked.")];
		}];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Revoke Session") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		AccountSecurityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf dismissViewControllerAnimated:YES completion:^{
			[strongSelf revokeSession:session];
		}];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = sourceCell ?: self.view;
	sheet.popoverPresentationController.sourceRect = sourceCell ? sourceCell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)revokeSession:(IMSessionInfo *)session {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Revoke Device?") message:session.deviceType preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Revoke") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[IMAccountApi deleteSessionId:session.sessionId completion:^(BOOL success, NSError *error) {
			AccountSecurityViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!success || error) [strongSelf showError:error]; else [strongSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == IMSecuritySectionSessions) return indexPath.row < (NSInteger)self.sessions.count && !self.sessions[indexPath.row].isCurrent;
	if (indexPath.section == IMSecuritySectionKeys) return indexPath.row < (NSInteger)self.apiKeys.count;
	return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete) return;
	if (indexPath.section == IMSecuritySectionSessions && indexPath.row < (NSInteger)self.sessions.count) {
		[self revokeSession:self.sessions[indexPath.row]];
	} else if (indexPath.section == IMSecuritySectionKeys && indexPath.row < (NSInteger)self.apiKeys.count) {
		IMAPIKey *key = self.apiKeys[indexPath.row];
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete API Key?") message:key.name preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		__weak typeof(self) weakSelf = self;
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
			[IMAccountApi deleteAPIKeyId:key.keyId completion:^(BOOL success, NSError *error) {
				AccountSecurityViewController *strongSelf = weakSelf;
				if (!strongSelf) return;
				if (!success || error) [strongSelf showError:error]; else [strongSelf reload];
			}];
		}]];
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
	[super willMoveToParentViewController:parent];
	if (!parent) { /* no retained tasks; NSURLSession callbacks are safely ignored */ }
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (!self.navigationItem.rightBarButtonItem) {
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createAPIKey)];
	}
	if (self.sessions.count > 1) {
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Sign Out Others") style:UIBarButtonItemStylePlain target:self action:@selector(signOutOtherSessions)];
	}
}

@end
