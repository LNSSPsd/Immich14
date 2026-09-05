#import "AdminServerViewController.h"
#import "IMServerApi.h"
#import "IMApiClient.h"
#import "IMServerStats.h"
#import "ServerVersionHistoryViewController.h"
#import "AdminSystemConfigViewController.h"
#import "AdminUtilitiesViewController.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMAdminServerSection) {
	IMAdminServerSectionTotals = 0,
	IMAdminServerSectionUsers,
	IMAdminServerSectionInfo,
	IMAdminServerSectionFeatures,
	IMAdminServerSectionLicense,
	IMAdminServerSectionMaintenance,
	IMAdminServerSectionCount,
};

@interface AdminServerViewController ()
@property (nonatomic, strong, nullable) IMServerStats *stats;
@property (nonatomic, strong, nullable) IMServerAbout *about;
@property (nonatomic, strong, nullable) IMServerFeatures *features;
@property (nonatomic, strong, nullable) IMServerConfig *config;
@property (nonatomic, strong, nullable) IMServerStorage *storage;
@property (nonatomic, strong, nullable) IMServerVersionCheck *versionCheck;
@property (nonatomic, copy, nullable) NSArray<IMServerVersionHistoryEntry *> *versionHistory;
@property (nonatomic, strong, nullable) IMServerMediaTypes *mediaTypes;
@property (nonatomic, strong, nullable) IMUserLicense *license;
@property (nonatomic) BOOL licenseLoaded;
@property (nonatomic, copy, nullable) NSDictionary *maintenanceStatus;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation AdminServerViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Server Administration");
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.tableView.backgroundView = self.statusLabel;
	UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
	                                                                            target:self
	                                                                            action:@selector(reload)];
	UIBarButtonItem *configuration = [[UIBarButtonItem alloc] initWithTitle:_(@"Configuration")
	                                                                     style:UIBarButtonItemStylePlain
	                                                                    target:self
	                                                                    action:@selector(configurationTapped)];
	UIBarButtonItem *utilities = [[UIBarButtonItem alloc] initWithTitle:_(@"Tools")
	                                                                style:UIBarButtonItemStylePlain
	                                                               target:self
	                                                               action:@selector(utilitiesTapped)];
	self.navigationItem.rightBarButtonItems = @[refresh, configuration, utilities];
	[self reload];
}

- (void)configurationTapped {
	[self.navigationController pushViewController:[[AdminSystemConfigViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]
	                                     animated:YES];
}

- (void)utilitiesTapped {
	[self.navigationController pushViewController:[[AdminUtilitiesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]
	                                     animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading && !self.mutating) [self reload];
}

- (void)reload {
	if (self.loading || self.mutating) { [self.refresh endRefreshing]; return; }
	self.loading = YES;
	if (!self.stats) self.statusLabel.text = _(@"Loading server statistics…");
	__weak typeof(self) weakSelf = self;
	 dispatch_group_t group = dispatch_group_create();
	__block IMServerStats *stats = nil;
	__block IMServerAbout *about = nil;
	__block IMServerFeatures *features = nil;
	__block IMServerConfig *config = nil;
	__block IMServerStorage *storage = nil;
	__block IMServerVersionCheck *versionCheck = nil;
	__block NSArray<IMServerVersionHistoryEntry *> *versionHistory = nil;
	__block IMServerMediaTypes *mediaTypes = nil;
	__block IMUserLicense *license = nil;
	__block BOOL licenseLoaded = NO;
	__block NSDictionary *status = nil;
	__block NSError *firstError = nil;
	dispatch_group_enter(group);
	[IMServerApi serverStatisticsWithCompletion:^(IMServerStats *value, NSError *error) {
		if (error) firstError = error; else stats = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi maintenanceStatusWithCompletion:^(NSDictionary *value, NSError *error) {
		if (error && !firstError) firstError = error; else status = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi serverAboutWithCompletion:^(IMServerAbout *value, NSError *error) {
		if (error && !firstError) firstError = error; else about = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi serverFeaturesWithCompletion:^(IMServerFeatures *value, NSError *error) {
		if (error && !firstError) firstError = error; else features = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi serverConfigWithCompletion:^(IMServerConfig *value, NSError *error) {
		if (error && !firstError) firstError = error; else config = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi serverStorageWithCompletion:^(IMServerStorage *value, NSError *error) {
		if (error && !firstError) firstError = error; else storage = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi serverVersionCheckWithCompletion:^(IMServerVersionCheck *value, NSError *error) {
		if (error && !firstError) firstError = error; else versionCheck = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi serverVersionHistoryWithCompletion:^(NSArray<IMServerVersionHistoryEntry *> *value, NSError *error) {
		if (error && !firstError) firstError = error; else versionHistory = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi supportedMediaTypesWithCompletion:^(IMServerMediaTypes *value, NSError *error) {
		if (error && !firstError) firstError = error; else mediaTypes = value;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMServerApi serverLicenseWithCompletion:^(IMUserLicense *value, NSError *error) {
		if (error) {
			if (!firstError) firstError = error;
		} else {
			licenseLoaded = YES;
			license = value;
		}
		dispatch_group_leave(group);
	}];
	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		AdminServerViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		[self.refresh endRefreshing];
		if (stats) self.stats = stats;
		if (about) self.about = about;
		if (features) self.features = features;
		if (config) self.config = config;
		if (storage) self.storage = storage;
		if (versionCheck) self.versionCheck = versionCheck;
		if (versionHistory) self.versionHistory = versionHistory;
		if (mediaTypes) self.mediaTypes = mediaTypes;
		if (licenseLoaded) {
			self.licenseLoaded = YES;
			self.license = license;
		}
		if (status) self.maintenanceStatus = status;
		[self.tableView reloadData];
		self.statusLabel.text = (self.stats || self.about || self.features || self.config || self.versionCheck || self.versionHistory || self.mediaTypes) ? nil : _(@"Couldn't load server information. Tap to retry.");
		if (!self.stats && !self.about && firstError) [self showError:firstError];
	});
}

- (NSString *)formattedBytes:(unsigned long long)bytes {
	NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
	formatter.countStyle = NSByteCountFormatterCountStyleFile;
	return [formatter stringFromByteCount:(long long)bytes];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Server Administration") message:error.localizedDescription ?: _(@"The server could not complete this request.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)maintenanceSummary {
	NSDictionary *status = self.maintenanceStatus;
	if (![status isKindOfClass:[NSDictionary class]]) return _(@"Status unavailable");
	BOOL active = [status[@"active"] boolValue];
	NSString *action = [status[@"action"] isKindOfClass:[NSString class]] ? status[@"action"] : @"";
	NSString *task = [status[@"task"] isKindOfClass:[NSString class]] ? status[@"task"] : @"";
	NSNumber *progress = [status[@"progress"] isKindOfClass:[NSNumber class]] ? status[@"progress"] : nil;
	if (!active) return _(@"Maintenance is inactive");
	if (progress) return [NSString stringWithFormat:_(@"%@ — %ld%%%@"), action.length ? action : _(@"Running"), (long)progress.integerValue, task.length ? [NSString stringWithFormat:@"\n%@", task] : @""];
	return [NSString stringWithFormat:_(@"%@%@"), action.length ? action : _(@"Running"), task.length ? [NSString stringWithFormat:@"\n%@", task] : @""];
}

- (void)maintenanceActions {
	BOOL active = [self.maintenanceStatus[@"active"] boolValue];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Maintenance") message:[self maintenanceSummary] preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	if (!active) {
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Start maintenance") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [weakSelf setMaintenanceAction:@"start"]; }]];
	} else {
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"End maintenance") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf setMaintenanceAction:@"end"]; }]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Refresh status") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf reload]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = self.view; sheet.popoverPresentationController.sourceRect = self.view.bounds; }
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)setMaintenanceAction:(NSString *)action {
	if (self.mutating) return;
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMServerApi setMaintenanceAction:action restoreBackupFilename:nil completion:^(BOOL success, NSError *error) {
		AdminServerViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		self.tableView.userInteractionEnabled = YES;
		if (!success) { [self showError:error]; return; }
		[self reload];
	}];
}

- (void)licenseActions {
	NSString *message = self.license
	    ? [NSString stringWithFormat:_(@"Active since %@"), self.license.activatedAt ?: _(@"an unknown date")]
	    : _(@"No product key is registered on this server.");
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Product license")
	                                                                  message:message
	                                                           preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:(self.license ? _(@"Replace license") : _(@"Set license"))
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf promptForLicense];
	}]];
	if (self.license) {
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Remove license")
		                                          style:UIAlertActionStyleDestructive
		                                        handler:^(UIAlertAction *action) {
			[weakSelf confirmDeleteLicense];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Refresh") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf reload];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.sourceView = self.view;
		sheet.popoverPresentationController.sourceRect = self.view.bounds;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptForLicense {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Set product license")
	                                                                     message:_(@"Enter the activation key and the Immich license key supplied for this server.")
	                                                              preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Activation key");
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"License key (IMSV/IMCL-…)");
		field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *activation = alert.textFields.firstObject.text ?: @"";
		NSString *license = alert.textFields.count > 1 ? alert.textFields[1].text : @"";
		[weakSelf setLicenseWithActivationKey:activation licenseKey:license];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)setLicenseWithActivationKey:(NSString *)activationKey licenseKey:(NSString *)licenseKey {
	if (self.mutating) return;
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMServerApi setServerLicenseWithActivationKey:activationKey licenseKey:licenseKey completion:^(IMUserLicense *license, NSError *error) {
		AdminServerViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		self.tableView.userInteractionEnabled = YES;
		if (!license || error) {
			[self showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"The server did not return a valid product license.")}]];
			return;
		}
		self.license = license;
		self.licenseLoaded = YES;
		[self.tableView reloadData];
	}];
}

- (void)confirmDeleteLicense {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Remove product license?")
	                                                                     message:_(@"This removes the registered product key from the server.")
	                                                              preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf deleteLicense];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteLicense {
	if (self.mutating) return;
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMServerApi deleteServerLicenseWithCompletion:^(BOOL success, NSError *error) {
		AdminServerViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		self.tableView.userInteractionEnabled = YES;
		if (!success) {
			[self showError:error];
			return;
		}
		self.license = nil;
		self.licenseLoaded = YES;
		[self.tableView reloadData];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return (self.stats || self.about || self.features || self.config || self.storage || self.versionCheck || self.versionHistory || self.mediaTypes || self.maintenanceStatus || self.licenseLoaded) ? IMAdminServerSectionCount : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == IMAdminServerSectionTotals) return 3;
	if (section == IMAdminServerSectionUsers) return self.stats.usageByUser.count;
	if (section == IMAdminServerSectionInfo) return self.about || self.config || self.storage || self.versionCheck || self.versionHistory || self.mediaTypes ? 8 : 0;
	if (section == IMAdminServerSectionFeatures) return self.features ? 16 : 0;
	if (section == IMAdminServerSectionLicense) return 1;
	if (section == IMAdminServerSectionMaintenance) return 1;
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == IMAdminServerSectionTotals) return _(@"Instance totals");
	if (section == IMAdminServerSectionUsers) return _(@"Usage by user");
	if (section == IMAdminServerSectionInfo) return _(@"Server information");
	if (section == IMAdminServerSectionFeatures) return _(@"Feature flags");
	if (section == IMAdminServerSectionLicense) return _(@"Product license");
	if (section == IMAdminServerSectionMaintenance) return _(@"Maintenance");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"server-admin"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"server-admin"];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.detailTextLabel.numberOfLines = 2;
	if (indexPath.section == IMAdminServerSectionTotals) {
		NSArray *titles = @[_(@"Photos"), _(@"Videos"), _(@"Storage")];
		NSArray *values = @[
			self.stats ? [NSString stringWithFormat:@"%ld", (long)self.stats.photos] : _(@"Unavailable"),
			self.stats ? [NSString stringWithFormat:@"%ld", (long)self.stats.videos] : _(@"Unavailable"),
			self.stats ? [self formattedBytes:self.stats.usage] : (self.storage.diskUse.length ? self.storage.diskUse : _(@"Unavailable"))
		];
		cell.textLabel.text = titles[indexPath.row];
		cell.detailTextLabel.text = values[indexPath.row];
		return cell;
	}
	if (indexPath.section == IMAdminServerSectionUsers) {
		IMServerUsageByUser *user = self.stats.usageByUser[indexPath.row];
		cell.textLabel.text = user.userName.length ? user.userName : _(@"Unnamed user");
		cell.detailTextLabel.text = [NSString stringWithFormat:_(@"%ld photos · %ld videos · %@%@"), (long)user.photos, (long)user.videos, [self formattedBytes:user.usage], user.hasQuota ? [NSString stringWithFormat:_(@" of %@"), [self formattedBytes:user.quotaSizeInBytes]] : @""];
		return cell;
	}
	if (indexPath.section == IMAdminServerSectionInfo) {
		NSArray *titles = @[_(@"Server version"), _(@"Build"), _(@"License"), _(@"External domain"), _(@"Trash retention"), _(@"Latest release"), _(@"Supported media"), _(@"Version history")];
		NSString *build = self.about.build.length ? self.about.build : (self.about.sourceRef.length ? self.about.sourceRef : _(@"Unknown"));
		NSString *license = self.about ? (self.about.licensed ? _(@"Licensed") : _(@"Community")) : _(@"Unavailable");
		NSString *domain = self.config.externalDomain.length ? self.config.externalDomain : _(@"Not configured");
		NSString *trash = self.config ? [NSString stringWithFormat:_(@"%ld days"), (long)self.config.trashDays] : _(@"Unavailable");
		NSString *versionCheckSummary = _(@"Unavailable");
		if (self.versionCheck) {
			NSString *release = self.versionCheck.releaseVersion.length ? self.versionCheck.releaseVersion : _(@"No release");
			NSString *checked = self.versionCheck.checkedAt.length ? self.versionCheck.checkedAt : _(@"Never checked");
			versionCheckSummary = [NSString stringWithFormat:_(@"%@ · checked %@"), release, checked];
		}
		NSString *mediaSummary = _(@"Unavailable");
		if (self.mediaTypes) {
			mediaSummary = [NSString stringWithFormat:_(@"%lu image · %lu video · %lu sidecar"),
			                (unsigned long)self.mediaTypes.image.count,
			                (unsigned long)self.mediaTypes.video.count,
			                (unsigned long)self.mediaTypes.sidecar.count];
		}
		NSString *historySummary = self.versionHistory ? [NSString stringWithFormat:_(@"%lu recorded %@"),
		                                                   (unsigned long)self.versionHistory.count,
		                                                   self.versionHistory.count == 1 ? _(@"version") : _(@"versions")] : _(@"Unavailable");
		NSArray *values = @[
			self.about.version.length ? self.about.version : _(@"Unavailable"), build, license, domain, trash,
			versionCheckSummary, mediaSummary, historySummary
		];
		cell.textLabel.text = titles[indexPath.row];
		cell.detailTextLabel.text = values[indexPath.row];
		if (indexPath.row == 7 && self.versionHistory) cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	if (indexPath.section == IMAdminServerSectionFeatures) {
		NSArray *titles = @[_(@"Search"), _(@"Smart search"), _(@"OCR"), _(@"Facial recognition"), _(@"Map"), _(@"Reverse geocoding"), _(@"Trash"), _(@"Duplicate detection"), _(@"Sidecar"), _(@"Email"), _(@"OAuth"), _(@"Password login"), _(@"Import faces"), _(@"Real-time transcoding"), _(@"Config file"), _(@"OAuth auto-launch")];
		NSArray<NSNumber *> *values = @[@(self.features.search), @(self.features.smartSearch), @(self.features.ocr), @(self.features.facialRecognition), @(self.features.map), @(self.features.reverseGeocoding), @(self.features.trash), @(self.features.duplicateDetection), @(self.features.sidecar), @(self.features.email), @(self.features.oauth), @(self.features.passwordLogin), @(self.features.importFaces), @(self.features.realtimeTranscoding), @(self.features.configFile), @(self.features.oauthAutoLaunch)];
		cell.textLabel.text = titles[indexPath.row];
		cell.detailTextLabel.text = self.features ? (values[indexPath.row].boolValue ? _(@"On") : _(@"Off")) : _(@"Unavailable");
		return cell;
	}
	if (indexPath.section == IMAdminServerSectionLicense) {
		cell.textLabel.text = _(@"Product license");
		if (self.license) {
			NSString *key = self.license.licenseKey;
			NSString *masked = key.length > 8
			    ? [NSString stringWithFormat:@"%@…%@", [key substringToIndex:4], [key substringFromIndex:key.length - 4]]
			    : key;
			cell.detailTextLabel.text = [NSString stringWithFormat:_(@"Active %@ · %@"), self.license.activatedAt, masked ?: _(@"Registered")];
		} else {
			cell.detailTextLabel.text = _(@"Not configured");
		}
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	cell.textLabel.text = _(@"Maintenance mode");
	cell.detailTextLabel.text = [self maintenanceSummary];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == IMAdminServerSectionLicense) {
		[self licenseActions];
		return;
	}
	if (indexPath.section == IMAdminServerSectionInfo && indexPath.row == 7 && self.versionHistory) {
		[self.navigationController pushViewController:[[ServerVersionHistoryViewController alloc] initWithHistory:self.versionHistory]
		                                     animated:YES];
		return;
	}
	if (indexPath.section == IMAdminServerSectionMaintenance) [self maintenanceActions];
}

@end
