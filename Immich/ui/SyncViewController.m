#import "SyncViewController.h"
#import "IMForegroundSync.h"
#import "IMPhotoLibrary.h"
#import "IMDatabase.h"
#import "IMPrefs.h"
#import "LocalAssetGridViewController.h"
#import "common.h"
#import <Photos/Photos.h>

typedef NS_ENUM(NSInteger, IMSyncSection) {
	IMSyncSectionBackup = 0,
	IMSyncSectionLibrary,
	IMSyncSectionStatus,
	IMSyncSectionActions,
	IMSyncSectionCount,
};

typedef NS_ENUM(NSInteger, IMSyncLibraryRow) {
	IMSyncLibraryRowAccess = 0,
	IMSyncLibraryRowTotal,
	IMSyncLibraryRowCount,
};

typedef NS_ENUM(NSInteger, IMSyncStatusRow) {
	IMSyncStatusRowSynced = 0,
	IMSyncStatusRowPendingUpload,
	IMSyncStatusRowCount,
};

static NSString *const kValueCellId = @"value";
static NSString *const kSwitchCellId = @"switch";
static NSString *const kActionCellId = @"action";

@interface SyncViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic) PHAuthorizationStatus authStatus;
@property (nonatomic) NSInteger totalCount;
@property (nonatomic) NSInteger syncedCount;
@property (nonatomic) NSInteger pendingUploadCount;
@end

@implementation SyncViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Sync");
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

	self.authStatus = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
	self.totalCount = [[IMPhotoLibrary shared] totalAssetCount];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(syncProgressed)
	                                              name:IMForegroundSyncProgressNotification
	                                            object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(syncFinished:)
	                                              name:IMForegroundSyncDidFinishNotification
	                                            object:nil];
	[self reloadCounts];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)syncProgressed {
	[self reloadCounts];
}

- (void)syncFinished:(NSNotification *)note {
	[self reloadCounts];
	NSError *error = note.userInfo[IMForegroundSyncErrorUserInfoKey];
	if (error && self.viewIfLoaded.window) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Sync Check Stopped")
		                                                                 message:error.localizedDescription
		                                                          preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.authStatus = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
	self.totalCount = [[IMPhotoLibrary shared] totalAssetCount];
	[self reloadCounts];
}

- (void)reloadCounts {
	NSInteger localOnly = 0, synced = 0;
	[[IMDatabase shared] syncStateCountsLocalOnly:&localOnly synced:&synced];
	self.pendingUploadCount = localOnly;
	self.syncedCount = synced;
	[self.tableView reloadData];
}

#pragma mark - Actions

- (void)backupSwitchChanged:(UISwitch *)sender {
	IMPrefs.shared.backupEnabled = sender.isOn;
	[self.tableView reloadData];
	if (sender.isOn && !IMForegroundSync.shared.isRunning) {
		[self checkNowTapped];
	}
}

- (void)accessRowTapped {
	if (self.authStatus == PHAuthorizationStatusNotDetermined) {
		__weak typeof(self) weakSelf = self;
		[[IMPhotoLibrary shared] requestAuthorizationWithCompletion:^(BOOL granted) {
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) {
				return;
			}
			strongSelf.authStatus = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
			strongSelf.totalCount = [[IMPhotoLibrary shared] totalAssetCount];
			[strongSelf.tableView reloadData];
		}];
		return;
	}
	NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
	if (settingsURL) {
		[[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:nil];
	}
}

- (void)showPendingUploads {
	if (self.pendingUploadCount == 0) {
		return;
	}
	NSArray<NSString *> *deviceAssetIds = [[IMDatabase shared] deviceAssetIdsWithState:IMSyncStateLocalOnly];
	LocalAssetGridViewController *vc = [LocalAssetGridViewController gridWithTitle:_(@"Not on Server")
	                                                                deviceAssetIds:deviceAssetIds];
	[self.navigationController pushViewController:vc animated:YES];
}

- (void)checkNowTapped {
	if (IMForegroundSync.shared.isRunning) {
		[IMForegroundSync.shared cancel];
		return;
	}
	[IMForegroundSync.shared startWithProgress:nil completion:nil];
	[self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return IMSyncSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case IMSyncSectionLibrary: return IMSyncLibraryRowCount;
		case IMSyncSectionStatus: return IMSyncStatusRowCount;
		default: return 1;
	}
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case IMSyncSectionLibrary: return _(@"Photo Library");
		case IMSyncSectionStatus: return _(@"Backup Status");
		default: return nil;
	}
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	switch (section) {
		case IMSyncSectionBackup:
			return IMPrefs.shared.backupEnabled
			    ? _(@"New and missing photos are checked and uploaded automatically while the app is open — on launch, when you switch back to it, and when your library changes.")
			    : _(@"Off: Check Now still compares your library against the server, but never uploads.");
		case IMSyncSectionActions:
			return _(@"Check Now compares your library against the server by checksum. It uploads "
			          @"anything missing only while Backup above is on.");
		default:
			return nil;
	}
}

- (NSString *)accessStatusText {
	switch (self.authStatus) {
		case PHAuthorizationStatusAuthorized: return _(@"Full Access");
		case PHAuthorizationStatusLimited: return _(@"Limited Access");
		case PHAuthorizationStatusDenied: return _(@"Denied — tap to open Settings");
		case PHAuthorizationStatusRestricted: return _(@"Restricted");
		case PHAuthorizationStatusNotDetermined:
		default: return _(@"Tap to Allow Access");
	}
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title detail:(nullable NSString *)detail {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kValueCellId];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title on:(BOOL)on action:(SEL)action {
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
		case IMSyncSectionBackup:
			return [self switchCellWithTitle:_(@"Backup") on:IMPrefs.shared.backupEnabled action:@selector(backupSwitchChanged:)];
		case IMSyncSectionLibrary:
			switch (indexPath.row) {
				case IMSyncLibraryRowAccess: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Access") detail:[self accessStatusText]];
					cell.selectionStyle = UITableViewCellSelectionStyleDefault;
					return cell;
				}
				default:
					return [self valueCellWithTitle:_(@"Total Photos & Videos") detail:[@(self.totalCount) stringValue]];
			}
		case IMSyncSectionStatus:
			switch (indexPath.row) {
				case IMSyncStatusRowSynced:
					return [self valueCellWithTitle:_(@"Already on Server") detail:[@(self.syncedCount) stringValue]];
				default: {
					UITableViewCell *cell = [self valueCellWithTitle:_(@"Not on Server") detail:[@(self.pendingUploadCount) stringValue]];
					if (self.pendingUploadCount > 0) {
						cell.selectionStyle = UITableViewCellSelectionStyleDefault;
						cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					}
					return cell;
				}
			}
		default: {
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kActionCellId forIndexPath:indexPath];
			if (IMForegroundSync.shared.isRunning) {
				cell.textLabel.text = [NSString stringWithFormat:_(@"Cancel (%ld of %ld checked)"),
				                                                  (long)IMForegroundSync.shared.checkedCount,
				                                                  (long)IMForegroundSync.shared.totalCount];
				if (@available(iOS 13.0, *)) {
					cell.textLabel.textColor = UIColor.systemRedColor;
				}
			} else {
				cell.textLabel.text = _(@"Check Now");
				if (@available(iOS 13.0, *)) {
					cell.textLabel.textColor = UIColor.systemBlueColor;
				}
			}
			cell.textLabel.textAlignment = NSTextAlignmentCenter;
			return cell;
		}
	}
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == IMSyncSectionLibrary && indexPath.row == IMSyncLibraryRowAccess) {
		[self accessRowTapped];
		return;
	}
	if (indexPath.section == IMSyncSectionStatus && indexPath.row == IMSyncStatusRowPendingUpload) {
		[self showPendingUploads];
		return;
	}
	if (indexPath.section == IMSyncSectionActions) {
		[self checkNowTapped];
	}
}

@end
