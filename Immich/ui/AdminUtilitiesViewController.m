#import "AdminUtilitiesViewController.h"
#import "IMAdminApi.h"
#import "IMAdminUtilityApi.h"
#import "IMAdminNotificationApi.h"
#import "IMAdminUser.h"
#import "IMApiClient.h"
#import "IMSystemConfigApi.h"
#import "IMMaintenanceDetectInstall.h"
#import "IMTestEmailResponse.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMAdminUtilityRow) {
	IMAdminUtilityRowUnlinkOAuth = 0,
	IMAdminUtilityRowDetectInstall,
	IMAdminUtilityRowSendNotification,
	IMAdminUtilityRowTestEmail,
	IMAdminUtilityRowCount,
};

@interface AdminUtilitiesViewController ()
@property (nonatomic) BOOL mutating;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, weak) UIAlertAction *notificationSendAction;
@end

@implementation AdminUtilitiesViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Administrator Utilities");
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 62.0;
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return IMAdminUtilityRowCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return _(@"Server tools");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"admin-utility";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.textLabel.numberOfLines = 2;
	cell.detailTextLabel.numberOfLines = 3;
	switch (indexPath.row) {
		case IMAdminUtilityRowUnlinkOAuth:
			cell.textLabel.text = _(@"Unlink all OAuth accounts");
			cell.detailTextLabel.text = _(@"Remove OAuth associations from every user account.");
			break;
		case IMAdminUtilityRowDetectInstall:
			cell.textLabel.text = _(@"Detect existing install");
			cell.detailTextLabel.text = _(@"Check storage folders for readable and writable install markers.");
			break;
		case IMAdminUtilityRowSendNotification:
			cell.textLabel.text = _(@"Send notification");
			cell.detailTextLabel.text = _(@"Create an in-app notification for an active user.");
			break;
		case IMAdminUtilityRowTestEmail:
			cell.textLabel.text = _(@"Send test email");
			cell.detailTextLabel.text = _(@"Verify the current SMTP configuration by sending a message to your account.");
			break;
	}
	cell.accessibilityLabel = cell.textLabel.text;
	cell.accessibilityValue = cell.detailTextLabel.text;
	return cell;
}

- (void)setBusy:(BOOL)busy {
	self.mutating = busy;
	self.tableView.userInteractionEnabled = !busy;
	if (busy) {
		if (!self.spinner) {
			self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
			self.spinner.hidesWhenStopped = YES;
		}
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
		[self.spinner startAnimating];
	} else {
		[self.spinner stopAnimating];
		self.navigationItem.rightBarButtonItem = nil;
	}
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (void)showError:(NSError *)error {
	[self showMessage:error.localizedDescription.length ? error.localizedDescription : _(@"The server could not complete this administrator action.")
	             title:_(@"Administrator Utilities")];
}

- (void)unlinkOAuthTapped {
	if (self.mutating) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Unlink all OAuth accounts?")
	                                                                 message:_(@"Every user will need to link OAuth again. Password and API-key credentials are not changed.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Unlink all") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		AdminUtilitiesViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf setBusy:YES];
		[IMAdminUtilityApi unlinkAllOAuthAccountsWithCompletion:^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				AdminUtilitiesViewController *inner = weakSelf;
				if (!inner) return;
				[inner setBusy:NO];
				if (!success || error) [inner showError:error];
				else [inner showMessage:_(@"OAuth associations were removed from all users.") title:_(@"OAuth accounts unlinked")];
			});
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)composeNotificationForUser:(IMAdminUser *)user {
	if (!user || self.mutating || !self.viewIfLoaded.window) return;
	NSString *recipient = user.name.length ? [NSString stringWithFormat:_(@"%@\n%@"), user.name, user.email] : user.email;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Send notification")
	                                                                 message:recipient
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Title");
		field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Description (optional)");
		field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Send") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminUtilitiesViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *title = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSString *description = [alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!title.length) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[strongSelf showError:[NSError errorWithDomain:IMApiErrorDomain
				                                      code:1
				                                  userInfo:@{NSLocalizedDescriptionKey: _(@"Enter a notification title.")}]];
			});
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			[strongSelf chooseNotificationLevelForUser:user title:title description:description];
		});
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseNotificationLevelForUser:(IMAdminUser *)user
	                              title:(NSString *)title
	                       description:(NSString *)description {
	if (!user || !title.length || self.mutating || !self.viewIfLoaded.window) return;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Notification severity")
	                                                                  message:_(@"Choose how the notification should appear.")
	                                                           preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	NSArray<NSArray<NSString *> *> *levels = @[
		@[ _(@"Info"), @"info" ],
		@[ _(@"Success"), @"success" ],
		@[ _(@"Warning"), @"warning" ],
		@[ _(@"Error"), @"error" ],
	];
	for (NSArray<NSString *> *level in levels) {
		[sheet addAction:[UIAlertAction actionWithTitle:level[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[weakSelf sendNotificationForUser:user title:title description:description level:level[1]];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.sourceView = self.view;
		sheet.popoverPresentationController.sourceRect = self.view.bounds;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)sendNotificationForUser:(IMAdminUser *)user
	                         title:(NSString *)title
	                  description:(NSString *)description
	                         level:(NSString *)level {
	if (!user || !title.length || self.mutating) return;
	[self setBusy:YES];
	__weak typeof(self) weakSelf = self;
	[IMAdminNotificationApi createNotificationForUserId:user.userId
	                                             title:title
	                                      description:description.length ? description : nil
	                                             level:level
	                                              type:@"Custom"
	                                            readAt:nil
	                                              data:nil
	                                        completion:^(IMNotification *notification, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			AdminUtilitiesViewController *inner = weakSelf;
			if (!inner) return;
			[inner setBusy:NO];
			if (error || !notification) {
				[inner showError:error ?: [NSError errorWithDomain:IMApiErrorDomain
				                                             code:2
				                                         userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid notification.")}]];
			} else {
				[inner showMessage:_(@"The notification was created for the selected user.") title:_(@"Notification sent")];
			}
		});
	}];
}

- (void)sendNotificationTapped {
	if (self.mutating) return;
	[self setBusy:YES];
	__weak typeof(self) weakSelf = self;
	[IMAdminApi usersIncludingDeleted:NO completion:^(NSArray<IMAdminUser *> *users, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			AdminUtilitiesViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			[strongSelf setBusy:NO];
			if (!strongSelf.viewIfLoaded.window) return;
			if (error || !users) {
				[strongSelf showError:error];
				return;
			}
			if (!users.count) {
				[strongSelf showMessage:_(@"There are no active users to notify.") title:_(@"Send notification")];
				return;
			}
			UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Choose recipient")
			                                                               message:_(@"Select an active user to receive the in-app notification.")
			                                                        preferredStyle:UIAlertControllerStyleActionSheet];
			for (IMAdminUser *user in users) {
				NSString *label = user.name.length ? [NSString stringWithFormat:_(@"%@ · %@"), user.name, user.email] : user.email;
				[sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
					[weakSelf dismissViewControllerAnimated:YES completion:^{
						[weakSelf composeNotificationForUser:user];
					}];
				}]];
			}
			[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
			if (sheet.popoverPresentationController) {
				sheet.popoverPresentationController.sourceView = strongSelf.view;
				sheet.popoverPresentationController.sourceRect = strongSelf.view.bounds;
			}
			[strongSelf presentViewController:sheet animated:YES completion:nil];
		});
	}];
}

- (NSString *)displayNameForFolder:(NSString *)folder {
	NSDictionary *names = @{
		@"encoded-video": _(@"Encoded video"),
		@"library": _(@"Library"),
		@"upload": _(@"Uploads"),
		@"profile": _(@"Profiles"),
		@"thumbs": _(@"Thumbnails"),
		@"backups": _(@"Database backups"),
	};
	return names[folder] ?: folder;
}

- (void)detectInstallTapped {
	if (self.mutating) return;
	[self setBusy:YES];
	__weak typeof(self) weakSelf = self;
	[IMAdminUtilityApi detectPriorInstallWithCompletion:^(IMMaintenanceDetectInstall *result, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			AdminUtilitiesViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			[strongSelf setBusy:NO];
			if (error || !result) {
				[strongSelf showError:error];
				return;
			}
			NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:result.storage.count];
			for (IMMaintenanceStorageFolder *folder in result.storage) {
				NSString *state = [NSString stringWithFormat:_(@"%@ — %ld files\n%@ / %@"),
				                  [strongSelf displayNameForFolder:folder.folder], (long)folder.files,
				                  folder.isReadable ? _(@"Readable") : _(@"Not readable"),
				                  folder.isWritable ? _(@"Writable") : _(@"Not writable")];
				[lines addObject:state];
			}
			[strongSelf showMessage:lines.count ? [lines componentsJoinedByString:@"\n\n"] : _(@"The server reported no storage folders.")
			                 title:_(@"Existing install check")];
		});
	}];
}

- (NSDictionary *_Nullable)smtpConfigurationFromSystemConfig:(IMSystemConfig *)config {
	id notifications = config.rawDictionary[@"notifications"];
	id smtp = [notifications isKindOfClass:[NSDictionary class]] ? notifications[@"smtp"] : nil;
	return [smtp isKindOfClass:[NSDictionary class]] ? [smtp copy] : nil;
}

- (void)sendTestEmailTapped {
	if (self.mutating) return;
	[self setBusy:YES];
	__weak typeof(self) weakSelf = self;
	[IMSystemConfigApi configWithCompletion:^(IMSystemConfig *config, NSError *error) {
		AdminUtilitiesViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf setBusy:NO];
		if (error || !config) {
			[strongSelf showError:error];
			return;
		}
		NSDictionary *smtp = [strongSelf smtpConfigurationFromSystemConfig:config];
		if (!smtp) {
			[strongSelf showMessage:_(@"The server configuration does not contain a complete SMTP section.") title:_(@"Test email")];
			return;
		}
		UIAlertController *confirm = [UIAlertController alertControllerWithTitle:_(@"Send a test email?")
		                                                                    message:_(@"Immich will send a test message using the current SMTP settings to the administrator account.")
		                                                             preferredStyle:UIAlertControllerStyleAlert];
		[confirm addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[confirm addAction:[UIAlertAction actionWithTitle:_(@"Send") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			AdminUtilitiesViewController *inner = weakSelf;
			if (!inner) return;
			[inner setBusy:YES];
			[IMAdminUtilityApi sendTestEmailWithSMTPConfiguration:smtp completion:^(IMTestEmailResponse *response, NSError *sendError) {
				dispatch_async(dispatch_get_main_queue(), ^{
					AdminUtilitiesViewController *target = weakSelf;
					if (!target) return;
					[target setBusy:NO];
					if (sendError || !response) [target showError:sendError];
					else [target showMessage:[NSString stringWithFormat:_(@"The test email was accepted (message ID: %@)."), response.messageId]
					                  title:_(@"Test email sent")];
				});
			}];
		}]];
		[strongSelf presentViewController:confirm animated:YES completion:nil];
	}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 0 || self.mutating) return;
	switch (indexPath.row) {
		case IMAdminUtilityRowUnlinkOAuth: [self unlinkOAuthTapped]; break;
		case IMAdminUtilityRowDetectInstall: [self detectInstallTapped]; break;
		case IMAdminUtilityRowSendNotification: [self sendNotificationTapped]; break;
		case IMAdminUtilityRowTestEmail: [self sendTestEmailTapped]; break;
	}
}

@end
