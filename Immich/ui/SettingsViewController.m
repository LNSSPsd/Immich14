#import "SettingsViewController.h"
#import "IMApiClient.h"
#import "IMAuthApi.h"
#import "IMUserApi.h"
#import "IMServerApi.h"
#import "IMSession.h"
#import "IMPrefs.h"
#import "IMThumbCache.h"
#import "IMAssetApi.h"
#import "common.h"
#import "PartnersViewController.h"
#import "AdminUsersViewController.h"
#import "TrashViewController.h"
#import "SharedLinksViewController.h"
#import "VisibilityViewController.h"
#import "TagsViewController.h"
#import "PeopleViewController.h"
#import "FoldersViewController.h"
#import "AccountSecurityViewController.h"
#import "AccountActivityViewController.h"
#import "OAuthAccountViewController.h"
#import "UserPreferencesViewController.h"
#import "DuplicatesViewController.h"
#import "AdminLibrariesViewController.h"
#import "AdminServerViewController.h"

typedef NS_ENUM(NSInteger, IMSettingsSection) {
	IMSettingsSectionAccount = 0,
	IMSettingsSectionServer,
	IMSettingsSectionPreferences,
	IMSettingsSectionAdvanced,
	IMSettingsSectionAbout,
	IMSettingsSectionCount,
};

typedef NS_ENUM(NSInteger, IMAccountRow) {
	IMAccountRowName = 0,
	IMAccountRowEmail,
	IMAccountRowProfileImage,
	IMAccountRowStorage,
	IMAccountRowSecurity,
	IMAccountRowActivity,
	IMAccountRowOAuth,
	IMAccountRowLockedPIN,
	IMAccountRowTrash,
	IMAccountRowSharedLinks,
	IMAccountRowArchive,
	IMAccountRowHidden,
	IMAccountRowPartners,
	IMAccountRowTags,
	IMAccountRowFolders,
	IMAccountRowPeople,
	IMAccountRowDuplicates,
	IMAccountRowAdministration,
	IMAccountRowLogOut,
	IMAccountRowCount,
};

typedef NS_ENUM(NSInteger, IMServerRow) {
	IMServerRowURL = 0,
	IMServerRowStorage, 
	IMServerRowCount,
};

typedef NS_ENUM(NSInteger, IMPreferencesRow) {
	IMPreferencesRowWifiOnly = 0,
	IMPreferencesRowLockedPhotosBiometric,
	IMPreferencesRowUserPreferences,
	IMPreferencesRowThumbnailQuality,
	IMPreferencesRowClearCache,
	IMPreferencesRowCount,
};

typedef NS_ENUM(NSInteger, IMAboutRow) {
	IMAboutRowAppVersion = 0,
	IMAboutRowServerVersion,
	IMAboutRowCount,
};

static NSString *const kValueCellId = @"value";
static NSString *const kSwitchCellId = @"switch";
static NSString *const kActionCellId = @"action";

@interface SettingsViewController () <UITableViewDataSource, UITableViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) IMUser *user;
@property (nonatomic, copy, nullable) NSString *serverVersion;
@property (nonatomic, strong, nullable) IMServerStorage *serverStorage;
@property (nonatomic) unsigned long long cacheSizeBytes;
@property (nonatomic, strong, nullable) UIImage *profileImage;
@property (nonatomic, strong, nullable) NSURLSessionTask *profileImageTask;
@property (nonatomic) BOOL profileImageMutating;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Settings");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	}

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 52.0;
	[self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kActionCellId];
	[self.view addSubview:self.tableView];
	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	self.user = [IMUserApi cachedUser];
	self.serverVersion = [IMServerApi cachedServerVersion];
	self.serverStorage = [IMServerApi cachedServerStorage];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)dealloc {
	[self.profileImageTask cancel];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[IMUserApi currentUserWithCompletion:^(IMUser *_Nullable user, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && user) {
			strongSelf.user = user;
			[strongSelf loadProfileImageForUser:user];
			[strongSelf.tableView reloadData];
		}
	}];
	[IMServerApi serverVersionWithCompletion:^(NSString *_Nullable versionString, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && versionString) {
			strongSelf.serverVersion = versionString;
			[strongSelf.tableView reloadData];
		}
	}];
	[IMServerApi serverStorageWithCompletion:^(IMServerStorage *_Nullable storage, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && storage) {
			strongSelf.serverStorage = storage;
			[strongSelf.tableView reloadData];
		}
	}];
	[[IMThumbCache shared] diskCacheSizeWithCompletion:^(unsigned long long bytes) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.cacheSizeBytes = bytes;
		[strongSelf.tableView reloadData];
		}];
}

- (void)loadProfileImageForUser:(IMUser *)user {
	[self.profileImageTask cancel];
	self.profileImageTask = nil;
	self.profileImage = nil;
	if (!user.profileImagePath.length || !user.userId.length) {
		NSIndexPath *path = [NSIndexPath indexPathForRow:IMAccountRowProfileImage inSection:IMSettingsSectionAccount];
		if (self.tableView.window) [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
		return;
	}
	NSString *userId = user.userId;
	__weak typeof(self) weakSelf = self;
	self.profileImageTask = [IMUserApi profileImageDataForUserId:userId completion:^(NSData *data, NSError *error) {
		SettingsViewController *self = weakSelf;
		if (!self || ![self.user.userId isEqualToString:userId]) return;
		self.profileImageTask = nil;
		if (!error && data.length) self.profileImage = [UIImage imageWithData:data scale:[UIScreen mainScreen].scale];
		NSIndexPath *path = [NSIndexPath indexPathForRow:IMAccountRowProfileImage inSection:IMSettingsSectionAccount];
		if (self.tableView.window) [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
	}];
}

- (NSString *)formattedBytes:(unsigned long long)bytes {
	NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
	formatter.countStyle = NSByteCountFormatterCountStyleFile;
	return [formatter stringFromByteCount:(long long)bytes];
}

#pragma mark - Actions

- (void)logOutTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Log Out?")
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Log Out")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [IMAuthApi logoutWithCompletion:^{
		    }];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)thumbnailQualityTapped {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Thumbnail Quality")
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Standard")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    IMPrefs.shared.thumbnailQuality = IMAssetMediaSizeThumbnail;
		    [weakSelf.tableView reloadData];
	    }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"High")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    IMPrefs.shared.thumbnailQuality = IMAssetMediaSizePreview;
		    [weakSelf.tableView reloadData];
	    }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	NSIndexPath *path = [NSIndexPath indexPathForRow:IMPreferencesRowThumbnailQuality inSection:IMSettingsSectionPreferences];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)clearCacheTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Clear Thumbnail Cache?")
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Clear")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [[IMThumbCache shared] clearWithCompletion:^{
			    typeof(self) strongSelf = weakSelf;
			    if (!strongSelf) {
				    return;
			    }
			    strongSelf.cacheSizeBytes = 0;
			    [strongSelf.tableView reloadData];
		    }];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)editProfileTapped {
	if (!self.user) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Edit Profile") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Name"); field.text = self.user.name; }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Email"); field.text = self.user.email; field.keyboardType = UIKeyboardTypeEmailAddress; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSString *email = [alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!name.length || !email.length) {
			[weakSelf showProfileError:[NSError errorWithDomain:@"IMUserApi" code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Enter a name and email address.")}]];
			return;
		}
		[IMUserApi updateCurrentUserWithFields:@{ @"name": name, @"email": email } completion:^(IMUser *user, NSError *error) {
			SettingsViewController *self = weakSelf;
			if (!self) return;
			if (error || !user) { [self showProfileError:error]; return; }
			self.user = user;
			dispatch_async(dispatch_get_main_queue(), ^{ [self.tableView reloadData]; });
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showProfileError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Profile Update Failed") message:error.localizedDescription ?: _(@"The server could not update your profile.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)profileImageTapped {
	if (self.profileImageMutating) return;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Profile Image") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Choose Photo") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf chooseProfileImage];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Avatar Color") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf avatarColorTapped];
	}]];
	if (self.user.profileImagePath.length) {
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Remove Photo") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
			[weakSelf removeProfileImage];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	NSIndexPath *path = [NSIndexPath indexPathForRow:IMAccountRowProfileImage inSection:IMSettingsSectionAccount];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)avatarColorTapped {
	NSArray<NSString *> *colors = @[ @"primary", @"pink", @"red", @"yellow", @"blue", @"green", @"purple", @"orange", @"gray", @"amber" ];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Avatar Color") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	for (NSString *color in colors) {
		[sheet addAction:[UIAlertAction actionWithTitle:color.capitalizedString style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			SettingsViewController *self = weakSelf;
			if (!self || self.profileImageMutating) return;
			self.profileImageMutating = YES;
			self.tableView.userInteractionEnabled = NO;
			[IMUserApi updateCurrentUserWithFields:@{ @"avatarColor": color } completion:^(IMUser *user, NSError *error) {
				SettingsViewController *inner = weakSelf;
				if (!inner) return;
				inner.profileImageMutating = NO;
				inner.tableView.userInteractionEnabled = YES;
				if (error || !user) { [inner showProfileError:error]; return; }
				inner.user = user;
				[inner.tableView reloadData];
			}];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Use Default") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		SettingsViewController *self = weakSelf;
		if (!self || self.profileImageMutating) return;
		self.profileImageMutating = YES;
		self.tableView.userInteractionEnabled = NO;
		[IMUserApi updateCurrentUserWithFields:@{ @"avatarColor": [NSNull null] } completion:^(IMUser *user, NSError *error) {
			SettingsViewController *inner = weakSelf;
			if (!inner) return;
			inner.profileImageMutating = NO;
			inner.tableView.userInteractionEnabled = YES;
			if (error || !user) { [inner showProfileError:error]; return; }
			inner.user = user;
			[inner.tableView reloadData];
		}];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = self.view.bounds; }
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)chooseProfileImage {
	if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
		[self showProfileError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"The photo library is unavailable on this device.")}]];
		return;
	}
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	picker.allowsEditing = YES;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
	UIImage *image = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
	__weak typeof(self) weakSelf = self;
	[picker dismissViewControllerAnimated:YES completion:^{
		SettingsViewController *self = weakSelf;
		if (!self || !image) return;
		NSData *data = UIImageJPEGRepresentation(image, 0.9);
		if (!data.length) {
			[self showProfileError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"The selected photo could not be encoded.")}]];
			return;
		}
		[self uploadProfileImageData:data];
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)uploadProfileImageData:(NSData *)data {
	if (self.profileImageMutating) return;
	self.profileImageMutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMUserApi uploadProfileImageData:data filename:@"profile.jpg" completion:^(BOOL success, NSError *error) {
		SettingsViewController *self = weakSelf;
		if (!self) return;
		self.profileImageMutating = NO;
		self.tableView.userInteractionEnabled = YES;
		if (!success || error) { [self showProfileError:error]; return; }
		self.user = [IMUserApi cachedUser] ?: self.user;
		[self loadProfileImageForUser:self.user];
		[self.tableView reloadData];
	}];
}

- (void)removeProfileImage {
	if (self.profileImageMutating) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Remove profile photo?") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		SettingsViewController *self = weakSelf;
		if (!self) return;
		self.profileImageMutating = YES;
		self.tableView.userInteractionEnabled = NO;
		[IMUserApi deleteProfileImageWithCompletion:^(BOOL success, NSError *error) {
			SettingsViewController *inner = weakSelf;
			if (!inner) return;
			inner.profileImageMutating = NO;
			inner.tableView.userInteractionEnabled = YES;
			if (!success || error) { [inner showProfileError:error]; return; }
			inner.profileImage = nil;
			inner.user = [IMUserApi cachedUser] ?: inner.user;
			[inner.tableView reloadData];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)wifiOnlySwitchChanged:(UISwitch *)sender {
	IMPrefs.shared.wifiOnlyUpload = sender.isOn;
}

- (void)lockedPhotosBiometricSwitchChanged:(UISwitch *)sender {
	IMPrefs.shared.lockedPhotosBiometricEnabled = sender.isOn;
}

- (void)allowInsecureTLSSwitchChanged:(UISwitch *)sender {
	IMPrefs.shared.allowInsecureTLS = sender.isOn;
	[[IMApiClient shared] resetConnections];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return IMSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case IMSettingsSectionAccount:
			return IMAccountRowCount - (self.user.isAdmin ? 0 : 1);
		case IMSettingsSectionServer:
			return IMServerRowCount;
		case IMSettingsSectionPreferences:
			return IMPreferencesRowCount;
		case IMSettingsSectionAdvanced:
			return 1;
		case IMSettingsSectionAbout:
			return IMAboutRowCount;
		default:
			return 0;
	}
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case IMSettingsSectionAccount: return _(@"Account");
		case IMSettingsSectionServer: return _(@"Server");
		case IMSettingsSectionPreferences: return _(@"Preferences");
		case IMSettingsSectionAdvanced: return _(@"Advanced");
		case IMSettingsSectionAbout: return _(@"About");
		default: return nil;
	}
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == IMSettingsSectionAdvanced) {
		return _(@"Accepts self-signed certificates. Use only with a trusted server.");
	}
	return nil;
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title detail:(nullable NSString *)detail {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kValueCellId];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 1;
	cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
	cell.accessibilityLabel = title;
	cell.accessibilityValue = detail;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title
                                       on:(BOOL)on
                                   action:(SEL)action {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSwitchCellId];
	cell.textLabel.text = title;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = on;
	[toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	switch (indexPath.section) {
		case IMSettingsSectionAccount: {
			NSInteger accountRow = indexPath.row;
			if (!self.user.isAdmin && accountRow >= IMAccountRowAdministration) accountRow++;
			switch (accountRow) {
				case IMAccountRowName:
					{ UITableViewCell *cell = [self valueCellWithTitle:_(@"Name") detail:self.user.name ?: @"—"]; cell.selectionStyle = UITableViewCellSelectionStyleDefault; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell; }
				case IMAccountRowEmail:
					{ UITableViewCell *cell = [self valueCellWithTitle:_(@"Email") detail:self.user.email ?: @"—"]; cell.selectionStyle = UITableViewCellSelectionStyleDefault; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell; }
				case IMAccountRowProfileImage: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Profile Photo") detail:self.user.profileImagePath.length ? _(@"Set") : _(@"Not set")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					cell.imageView.image = self.profileImage;
					cell.imageView.layer.cornerRadius = 20.0;
					cell.imageView.layer.masksToBounds = YES;
					return cell;
				}
				case IMAccountRowStorage: {
					NSString *detail = self.user.quotaSizeInBytes > 0
					    ? [NSString stringWithFormat:_(@"%@ of %@"), [self formattedBytes:self.user.quotaUsageInBytes],
					                                  [self formattedBytes:self.user.quotaSizeInBytes]]
					    : [NSString stringWithFormat:_(@"%@ (unlimited)"), [self formattedBytes:self.user.quotaUsageInBytes]];
					return [self valueCellWithTitle:_(@"Storage Used") detail:self.user ? detail : @"—"];
				}
					case IMAccountRowSecurity: {
						UITableViewCell *cell = [self valueCellWithTitle:_(@"Account Security") detail:_(@"Password, devices & keys")];
						cell.selectionStyle = UITableViewCellSelectionStyleDefault;
						cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
						return cell;
					}
					case IMAccountRowActivity: {
						UITableViewCell *cell = [self valueCellWithTitle:_(@"Account Activity") detail:_(@"History & license")];
						cell.selectionStyle = UITableViewCellSelectionStyleDefault;
						cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
						return cell;
					}
					case IMAccountRowOAuth: {
						UITableViewCell *cell = [self valueCellWithTitle:_(@"OAuth Account") detail:_(@"Linked provider")];
						cell.selectionStyle = UITableViewCellSelectionStyleDefault;
						cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
						return cell;
					}
				case IMAccountRowLockedPIN: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Locked Photos PIN") detail:_(@"PIN settings")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMAccountRowTrash: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Trash") detail:_(@"Deleted photos")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMAccountRowSharedLinks: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Shared Links") detail:_(@"Public links")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMAccountRowArchive: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Archive") detail:_(@"Archived photos")]; cell.selectionStyle=UITableViewCellSelectionStyleDefault; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
				}
				case IMAccountRowHidden: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Hidden Photos") detail:_(@"Hidden photos")]; cell.selectionStyle=UITableViewCellSelectionStyleDefault; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
				}
				case IMAccountRowPartners: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Partner Sharing") detail:_(@"Shared libraries")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMAccountRowTags: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Tags") detail:_(@"Tagged photos")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMAccountRowFolders: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Folders") detail:_(@"Original folders")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMAccountRowAdministration: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Administration") detail:_(@"Server controls")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMAccountRowPeople: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"People") detail:_(@"Faces & people")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMAccountRowDuplicates: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Duplicates") detail:_(@"Duplicate photos")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				default: {
					UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kActionCellId forIndexPath:indexPath];
					cell.textLabel.text = _(@"Log Out");
					if (@available(iOS 13.0, *)) {
						cell.textLabel.textColor = UIColor.systemRedColor;
					}
					cell.textLabel.textAlignment = NSTextAlignmentCenter;
					return cell;
			}
		}
		}
		case IMSettingsSectionServer:
			switch (indexPath.row) {
				case IMServerRowURL:
					return [self valueCellWithTitle:_(@"Server URL") detail:[IMSession shared].baseURL.absoluteString ?: @"—"];
				default: {
					IMServerStorage *storage = self.serverStorage;
					NSString *detail = storage
					    ? [NSString stringWithFormat:_(@"%@ of %@ (%.0f%%)"), storage.diskUse, storage.diskSize, storage.diskUsagePercentage]
					    : @"—";
					return [self valueCellWithTitle:_(@"Server Storage") detail:detail];
				}
			}
		case IMSettingsSectionPreferences:
			switch (indexPath.row) {
				case IMPreferencesRowWifiOnly:
					return [self switchCellWithTitle:_(@"Wi-Fi Only Upload")
				                               on:IMPrefs.shared.wifiOnlyUpload
				                           action:@selector(wifiOnlySwitchChanged:)];
				case IMPreferencesRowLockedPhotosBiometric:
					return [self switchCellWithTitle:_(@"Biometric Unlock for Locked Photos")
				                               on:IMPrefs.shared.lockedPhotosBiometricEnabled
				                           action:@selector(lockedPhotosBiometricSwitchChanged:)];
				case IMPreferencesRowUserPreferences: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"User Preferences") detail:_(@"Immich preferences")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				case IMPreferencesRowThumbnailQuality: {
					BOOL high = [IMPrefs.shared.thumbnailQuality isEqualToString:IMAssetMediaSizePreview];
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Thumbnail Quality")
					                                            detail:high ? _(@"High") : _(@"Standard")];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					return cell;
				}
				default: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Clear Thumbnail Cache")
					                                            detail:[self formattedBytes:self.cacheSizeBytes]];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					if (@available(iOS 13.0, *)) {
						cell.textLabel.textColor = UIColor.systemRedColor;
					}
					return cell;
				}
			}
		case IMSettingsSectionAdvanced:
			return [self switchCellWithTitle:_(@"Allow Insecure TLS")
			                               on:IMPrefs.shared.allowInsecureTLS
			                           action:@selector(allowInsecureTLSSwitchChanged:)];
		default:
			switch (indexPath.row) {
				case IMAboutRowAppVersion:
					return [self valueCellWithTitle:_(@"App Version")
					                            detail:[NSString stringWithFormat:@"%s (%s)", APP_VERSION_STRING, APP_COMMIT_HASH]];
				default:
					return [self valueCellWithTitle:_(@"Server Version") detail:self.serverVersion ?: @"—"];
		}
	}
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSInteger accountRow = indexPath.row;
	if (indexPath.section == IMSettingsSectionAccount && !self.user.isAdmin && accountRow >= IMAccountRowAdministration) accountRow++;
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowLogOut) {
		[self logOutTapped];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && (accountRow == IMAccountRowName || accountRow == IMAccountRowEmail)) {
		[self editProfileTapped];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowProfileImage) {
		[self profileImageTapped];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowPartners) {
		[self.navigationController pushViewController:[[PartnersViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowTags) {
		[self.navigationController pushViewController:[[TagsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowFolders) {
		[self.navigationController pushViewController:[[FoldersViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowPeople) {
		[self.navigationController pushViewController:[[PeopleViewController alloc] init] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowDuplicates) {
		[self.navigationController pushViewController:[[DuplicatesViewController alloc] init] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowLockedPIN) {
		[self manageLockedPIN];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowSecurity) {
		[self.navigationController pushViewController:[[AccountSecurityViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowActivity) {
		[self.navigationController pushViewController:[[AccountActivityViewController alloc] init] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowOAuth) {
		[self.navigationController pushViewController:[[OAuthAccountViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowTrash) {
		[self.navigationController pushViewController:[[TrashViewController alloc] init] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowSharedLinks) {
		[self.navigationController pushViewController:[[SharedLinksViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowArchive) {
		[self.navigationController pushViewController:[[VisibilityViewController alloc] initWithVisibility:@"archive" title:_(@"Archive")] animated:YES]; return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowHidden) {
		[self.navigationController pushViewController:[[VisibilityViewController alloc] initWithVisibility:@"hidden" title:_(@"Hidden Photos")] animated:YES]; return;
	}
	if (indexPath.section == IMSettingsSectionAccount && accountRow == IMAccountRowAdministration && self.user.isAdmin) {
		[self.navigationController pushViewController:[[AdminUsersViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionPreferences && indexPath.row == IMPreferencesRowUserPreferences) {
		[self.navigationController pushViewController:[[UserPreferencesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
		return;
	}
	if (indexPath.section == IMSettingsSectionPreferences && indexPath.row == IMPreferencesRowThumbnailQuality) {
		[self thumbnailQualityTapped];
		return;
	}
	if (indexPath.section == IMSettingsSectionPreferences && indexPath.row == IMPreferencesRowClearCache) {
		[self clearCacheTapped];
		return;
	}
}

- (void)manageLockedPIN {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Locked Photos PIN") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Set PIN") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Set PIN") message:_(@"Choose a six-digit PIN.") preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder = _(@"Six-digit PIN"); f.keyboardType = UIKeyboardTypeNumberPad; f.secureTextEntry = YES; }];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a2){ [IMAuthApi setupPIN:alert.textFields.firstObject.text completion:^(BOOL ok, NSError *e){ if (!ok) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showPINError:e]; }); }]; }]];
		[weakSelf presentViewController:alert animated:YES completion:nil];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Change PIN") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Change PIN") message:nil preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder = _(@"Current PIN"); f.keyboardType = UIKeyboardTypeNumberPad; f.secureTextEntry = YES; }];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder = _(@"New six-digit PIN"); f.keyboardType = UIKeyboardTypeNumberPad; f.secureTextEntry = YES; }];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a2){ [IMAuthApi changePIN:alert.textFields[1].text currentPIN:alert.textFields[0].text password:nil completion:^(BOOL ok, NSError *e){ if (!ok) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showPINError:e]; }); }]; }]];
		[weakSelf presentViewController:alert animated:YES completion:nil];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Remove PIN") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Remove PIN") message:_(@"Enter your account password to confirm.") preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *f){ f.placeholder = _(@"Password"); f.secureTextEntry = YES; }];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a2){ [IMAuthApi resetPINWithPassword:alert.textFields.firstObject.text pin:nil completion:^(BOOL ok, NSError *e){ if (!ok) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showPINError:e]; }); }]; }]];
		[weakSelf presentViewController:alert animated:YES completion:nil];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds), 1, 1); }
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)showPINError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"PIN Update Failed") message:error.localizedDescription ?: _(@"The server rejected the PIN change.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
