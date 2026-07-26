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
	IMAccountRowStorage,
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

@interface SettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong, nullable) IMUser *user;
@property (nonatomic, copy, nullable) NSString *serverVersion;
@property (nonatomic, strong, nullable) IMServerStorage *serverStorage;
@property (nonatomic) unsigned long long cacheSizeBytes;
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

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[IMUserApi currentUserWithCompletion:^(IMUser *_Nullable user, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && user) {
			strongSelf.user = user;
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

- (void)wifiOnlySwitchChanged:(UISwitch *)sender {
	IMPrefs.shared.wifiOnlyUpload = sender.isOn;
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
			return IMAccountRowCount;
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
		return _(@"Only enable this if you understand the risk — it disables TLS certificate "
		          @"validation for this app's connection to your server (self-signed certs on a "
		          @"trusted LAN/WireGuard server only).");
	}
	return nil;
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title detail:(nullable NSString *)detail {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kValueCellId];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 0;
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
		case IMSettingsSectionAccount:
			switch (indexPath.row) {
				case IMAccountRowName:
					return [self valueCellWithTitle:_(@"Name") detail:self.user.name ?: @"—"];
				case IMAccountRowEmail:
					return [self valueCellWithTitle:_(@"Email") detail:self.user.email ?: @"—"];
				case IMAccountRowStorage: {
					NSString *detail = self.user.quotaSizeInBytes > 0
					    ? [NSString stringWithFormat:_(@"%@ of %@"), [self formattedBytes:self.user.quotaUsageInBytes],
					                                  [self formattedBytes:self.user.quotaSizeInBytes]]
					    : [NSString stringWithFormat:_(@"%@ (unlimited)"), [self formattedBytes:self.user.quotaUsageInBytes]];
					return [self valueCellWithTitle:_(@"Storage Used") detail:self.user ? detail : @"—"];
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
	if (indexPath.section == IMSettingsSectionAccount && indexPath.row == IMAccountRowLogOut) {
		[self logOutTapped];
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

@end
