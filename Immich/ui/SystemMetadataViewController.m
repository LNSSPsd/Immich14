#import "SystemMetadataViewController.h"
#import "IMSystemMetadataApi.h"
#import "IMApiClient.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMSystemMetadataSection) {
	IMSystemMetadataSectionOnboarding = 0,
	IMSystemMetadataSectionState,
	IMSystemMetadataSectionCount,
};

@interface SystemMetadataViewController ()
@property (nonatomic, strong, nullable) IMAdminOnboardingStatus *onboarding;
@property (nonatomic, strong, nullable) IMReverseGeocodingState *reverseGeocoding;
@property (nonatomic, strong, nullable) IMVersionCheckState *versionCheck;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@end

@implementation SystemMetadataViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"System Metadata");
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
	                                                                                         target:self
	                                                                                         action:@selector(reload)];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading && !self.mutating) [self reload];
}

- (void)reload {
	if (self.loading || self.mutating) return;
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	__block NSInteger pending = 3;
	__block NSError *firstError;
	void (^finish)(void) = ^{
		pending -= 1;
		if (pending != 0) return;
		SystemMetadataViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loading = NO;
		[strongSelf.refresh endRefreshing];
		[strongSelf.tableView reloadData];
		if (firstError && !strongSelf.onboarding && !strongSelf.reverseGeocoding && !strongSelf.versionCheck) {
			[strongSelf showError:firstError];
		}
	};
	[IMSystemMetadataApi adminOnboardingWithCompletion:^(IMAdminOnboardingStatus *status, NSError *error) {
		if (status) weakSelf.onboarding = status;
		if (error && !firstError) firstError = error;
		finish();
	}];
	[IMSystemMetadataApi reverseGeocodingStateWithCompletion:^(IMReverseGeocodingState *state, NSError *error) {
		if (state) weakSelf.reverseGeocoding = state;
		if (error && !firstError) firstError = error;
		finish();
	}];
	[IMSystemMetadataApi versionCheckStateWithCompletion:^(IMVersionCheckState *state, NSError *error) {
		if (state) weakSelf.versionCheck = state;
		if (error && !firstError) firstError = error;
		finish();
	}];
}

- (void)showError:(NSError *)error {
	if (!self.viewIfLoaded.window) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"System Metadata")
	                                                                 message:error.localizedDescription ?: _(@"The server rejected this request.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)onboardingChanged:(UISwitch *)sender {
	if (!self.onboarding || self.mutating) return;
	BOOL previous = self.onboarding.isOnboarded;
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMSystemMetadataApi setAdminOnboarded:sender.isOn completion:^(BOOL success, NSError *error) {
		SystemMetadataViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = NO;
		strongSelf.tableView.userInteractionEnabled = YES;
		if (!success || error) {
			sender.on = previous;
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server did not update onboarding status.")}]];
			return;
		}
		[strongSelf reload];
	}];
}

- (NSString *)valueOrUnavailable:(NSString *)value {
	return value.length ? value : _(@"Not available");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return IMSystemMetadataSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == IMSystemMetadataSectionOnboarding ? 1 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == IMSystemMetadataSectionOnboarding) return _(@"Onboarding");
	return _(@"Server state");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == IMSystemMetadataSectionOnboarding) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.textLabel.text = _(@"Administrator onboarded");
		cell.detailTextLabel.text = self.onboarding ? (self.onboarding.isOnboarded ? _(@"Setup is complete") : _(@"Setup is pending")) : _(@"Unavailable");
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = self.onboarding.isOnboarded;
		toggle.enabled = self.onboarding != nil && !self.mutating;
		toggle.accessibilityLabel = _(@"Administrator onboarded");
		[toggle addTarget:self action:@selector(onboardingChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	if (indexPath.row == 0) {
		cell.textLabel.text = _(@"Reverse geocoding import");
		cell.detailTextLabel.text = self.reverseGeocoding ? [self valueOrUnavailable:self.reverseGeocoding.lastImportFileName] : _(@"Unavailable");
	} else {
		cell.textLabel.text = _(@"Version check");
		NSString *version = self.versionCheck.releaseVersion.length ? self.versionCheck.releaseVersion : _(@"No release");
		NSString *date = self.versionCheck.checkedAt.length ? self.versionCheck.checkedAt : _(@"Never");
		cell.detailTextLabel.text = self.versionCheck ? [NSString stringWithFormat:_(@"%@ · %@"), version, date] : _(@"Unavailable");
	}
	return cell;
}

@end
