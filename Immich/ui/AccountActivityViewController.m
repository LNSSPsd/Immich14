#import "AccountActivityViewController.h"
#import "IMUserAccountApi.h"
#import "IMApiClient.h"
#import "IMCalendarHeatmap.h"
#import "IMUserLicense.h"
#import "IMOnboardingStatus.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMAccountActivitySection) {
	IMAccountActivitySectionOnboarding = 0,
	IMAccountActivitySectionLicense,
	IMAccountActivitySectionHeatmap,
	IMAccountActivitySectionCount,
};

static const NSInteger kOnboardingSwitchTag = 4101;

@interface AccountActivityViewController ()
@property (nonatomic, strong, nullable) IMOnboardingStatus *onboarding;
@property (nonatomic, strong, nullable) IMUserLicense *license;
@property (nonatomic, strong, nullable) IMCalendarHeatmap *heatmap;
@property (nonatomic, strong, nullable) NSError *onboardingError;
@property (nonatomic, strong, nullable) NSError *licenseError;
@property (nonatomic, strong, nullable) NSError *heatmapError;
@property (nonatomic, copy) NSString *heatmapType;
@property (nonatomic, copy, nullable) NSString *heatmapFromDate;
@property (nonatomic, copy, nullable) NSString *heatmapToDate;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic) NSInteger pendingRequests;
@property (nonatomic) NSUInteger generation;
@end

@implementation AccountActivityViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_heatmapType = @"Upload";
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Account Activity");
	if (@available(iOS 13.0, *)) self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	else self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reloadDataFromServer) forControlEvents:UIControlEventValueChanged];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Actions")
	                                                                            style:UIBarButtonItemStylePlain
	                                                                           target:self
	                                                                           action:@selector(actionsTapped)];
	[self reloadDataFromServer];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading) [self reloadDataFromServer];
}

- (void)dealloc {
	_generation += 1;
}

- (void)reloadDataFromServer {
	if (self.loading) {
		[self.refreshControl endRefreshing];
		return;
	}
	self.loading = YES;
	self.pendingRequests = 3;
	NSUInteger generation = ++self.generation;
	[self.refreshControl beginRefreshing];
	__weak typeof(self) weakSelf = self;
	[IMUserAccountApi userOnboardingWithCompletion:^(IMOnboardingStatus *status, NSError *error) {
		AccountActivityViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		strongSelf.onboarding = status;
		strongSelf.onboardingError = error;
		[strongSelf requestFinishedForGeneration:generation];
	}];
	[IMUserAccountApi userLicenseWithCompletion:^(IMUserLicense *license, NSError *error) {
		AccountActivityViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		strongSelf.license = license;
		strongSelf.licenseError = error;
		[strongSelf requestFinishedForGeneration:generation];
	}];
	[IMUserAccountApi calendarHeatmapFromDate:self.heatmapFromDate
	                                  toDate:self.heatmapToDate
	                                    type:self.heatmapType
	                              completion:^(IMCalendarHeatmap *heatmap, NSError *error) {
		AccountActivityViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		strongSelf.heatmap = heatmap;
		strongSelf.heatmapError = error;
		[strongSelf requestFinishedForGeneration:generation];
	}];
}

- (void)requestFinishedForGeneration:(NSUInteger)generation {
	if (generation != self.generation || self.pendingRequests <= 0) return;
	self.pendingRequests -= 1;
	if (self.pendingRequests != 0) return;
	self.loading = NO;
	[self.refreshControl endRefreshing];
	[self.tableView reloadData];
	if (!self.onboarding && !self.license && !self.heatmap) {
		NSError *error = self.heatmapError ?: self.licenseError ?: self.onboardingError;
		if (error) [self showError:error];
	}
}

- (void)showError:(NSError *)error {
	if (!self.viewIfLoaded.window) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Account Activity")
	                                                                 message:error.localizedDescription ?: _(@"The server could not load account details.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showMutationError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Account Activity")
	                                                                 message:error.localizedDescription ?: _(@"The server rejected this change.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (UITableViewCell *)valueCellWithTitle:(NSString *)title detail:(NSString *)detail accessory:(BOOL)accessory {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 0;
	cell.accessoryType = accessory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	return cell;
}

- (NSString *)displayDate:(NSString *)raw {
	if (raw.length == 0) return @"—";
	static NSDateFormatter *input;
	static NSDateFormatter *output;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
		calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		input = [[NSDateFormatter alloc] init];
		input.locale = locale;
		input.calendar = calendar;
		input.timeZone = calendar.timeZone;
		input.dateFormat = @"yyyy-MM-dd";
		output = [[NSDateFormatter alloc] init];
		output.locale = [NSLocale currentLocale];
		output.dateStyle = NSDateFormatterMediumStyle;
		output.timeStyle = NSDateFormatterNoStyle;
	});
	NSDate *date = [input dateFromString:raw];
	return date ? [output stringFromDate:date] : raw;
}

- (NSString *)heatmapRangeText {
	if (!self.heatmap) return self.heatmapError.localizedDescription ?: _(@"Unavailable");
	return [NSString stringWithFormat:_(@"%@ – %@ · %ld activities"),
	        [self displayDate:self.heatmap.fromDate], [self displayDate:self.heatmap.toDate], (long)self.heatmap.totalCount];
}

- (NSString *)maskedLicenseKey:(NSString *)key {
	if (key.length < 9) return key.length ? key : _(@"Registered");
	return [NSString stringWithFormat:@"%@…%@", [key substringToIndex:4], [key substringFromIndex:key.length - 4]];
}

- (void)onboardingSwitchChanged:(UISwitch *)sender {
	if (self.mutating) return;
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMUserAccountApi setUserOnboarding:sender.isOn completion:^(IMOnboardingStatus *status, NSError *error) {
		AccountActivityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = NO;
		strongSelf.tableView.userInteractionEnabled = YES;
		if (!status || error) {
			[strongSelf.tableView reloadData];
			[strongSelf showMutationError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid onboarding response.")}]];
			return;
		}
		strongSelf.onboarding = status;
		strongSelf.onboardingError = nil;
		[strongSelf.tableView reloadData];
	}];
}

- (void)editLicense {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.license ? _(@"Replace License") : _(@"Register License")
	                                                                 message:_(@"Your activation and license keys are sent securely to the Immich server.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Activation key");
		field.text = self.license.activationKey ?: @"";
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"License key (IMSV/IMCL-…)");
		field.text = self.license.licenseKey ?: @"";
		field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AccountActivityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = YES;
		strongSelf.tableView.userInteractionEnabled = NO;
		[IMUserAccountApi setUserLicenseWithActivationKey:alert.textFields[0].text
	                                           licenseKey:alert.textFields[1].text
	                                          completion:^(IMUserLicense *license, NSError *error) {
			AccountActivityViewController *inner = weakSelf;
			if (!inner) return;
			inner.mutating = NO;
			inner.tableView.userInteractionEnabled = YES;
			if (!license || error) {
				[inner showMutationError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid license response.")}]];
				return;
			}
			inner.license = license;
			inner.licenseError = nil;
			[inner.tableView reloadData];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteLicense {
	if (!self.license) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Remove License?")
	                                                                 message:_(@"This unregisters the product key from your account.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		AccountActivityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = YES;
		strongSelf.tableView.userInteractionEnabled = NO;
		[IMUserAccountApi deleteUserLicenseWithCompletion:^(BOOL success, NSError *error) {
			AccountActivityViewController *inner = weakSelf;
			if (!inner) return;
			inner.mutating = NO;
			inner.tableView.userInteractionEnabled = YES;
			if (!success || error) {
				[inner showMutationError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not remove the license.")}]];
				return;
			}
			inner.license = nil;
			inner.licenseError = nil;
			[inner reloadDataFromServer];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)resetOnboarding {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Reset Onboarding?")
	                                                                 message:_(@"The server will mark this account as not onboarded.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		AccountActivityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = YES;
		strongSelf.tableView.userInteractionEnabled = NO;
		[IMUserAccountApi deleteUserOnboardingWithCompletion:^(BOOL success, NSError *error) {
			AccountActivityViewController *inner = weakSelf;
			if (!inner) return;
			inner.mutating = NO;
			inner.tableView.userInteractionEnabled = YES;
			if (!success || error) {
				[inner showMutationError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not reset onboarding.")}]];
				return;
			}
			inner.onboarding = nil;
			inner.onboardingError = nil;
			[inner reloadDataFromServer];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)actionsTapped {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Account Activity") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Upload activity") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		weakSelf.heatmapType = @"Upload";
		[weakSelf reloadDataFromServer];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Taken activity") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		weakSelf.heatmapType = @"Taken";
		[weakSelf reloadDataFromServer];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Change date range") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf editDateRange];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:weakSelf.license ? _(@"Replace license") : _(@"Register license") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf editLicense];
	}]];
	if (self.license) [sheet addAction:[UIAlertAction actionWithTitle:_(@"Remove license") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [weakSelf deleteLicense]; }]];
	if (self.onboarding) [sheet addAction:[UIAlertAction actionWithTitle:_(@"Reset onboarding") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [weakSelf resetOnboarding]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)editDateRange {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Activity Date Range")
	                                                                 message:_(@"Use UTC dates in yyyy-MM-dd format. Leave a field empty for the server default.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"From (yyyy-MM-dd)");
		field.text = self.heatmapFromDate ?: @"";
		field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
	}];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"To (yyyy-MM-dd)");
		field.text = self.heatmapToDate ?: @"";
		field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Apply") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AccountActivityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *from = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSString *to = [alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		strongSelf.heatmapFromDate = from.length ? from : nil;
		strongSelf.heatmapToDate = to.length ? to : nil;
		[strongSelf reloadDataFromServer];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return IMAccountActivitySectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == IMAccountActivitySectionHeatmap) return self.heatmap ? MIN((NSInteger)self.heatmap.series.count + 1, 1001) : 1;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case IMAccountActivitySectionOnboarding: return _(@"Onboarding");
		case IMAccountActivitySectionLicense: return _(@"License");
		default: return [NSString stringWithFormat:_(@"Activity Heatmap · %@"), self.heatmapType];
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == IMAccountActivitySectionOnboarding) return _(@"Onboarding status is stored on the Immich server and can be reset from Actions.");
	if (section == IMAccountActivitySectionLicense) return _(@"License registration is optional and depends on server entitlement support.");
	return _(@"Activity counts are in UTC. Use Actions to switch between upload and taken dates or choose a range.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == IMAccountActivitySectionOnboarding) {
		NSString *detail = self.onboarding ? (self.onboarding.isOnboarded ? _(@"Completed") : _(@"Not completed")) : (self.onboardingError.localizedDescription ?: _(@"Loading…"));
		UITableViewCell *cell = [self valueCellWithTitle:_(@"Setup status") detail:detail accessory:NO];
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.tag = kOnboardingSwitchTag;
		toggle.on = self.onboarding.isOnboarded;
		toggle.enabled = self.onboarding != nil && !self.mutating;
		[toggle addTarget:self action:@selector(onboardingSwitchChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	if (indexPath.section == IMAccountActivitySectionLicense) {
		if (!self.license) {
			NSString *detail = self.licenseError ? ([IMApiClient HTTPStatusForError:self.licenseError] == 404 ? _(@"No license registered") : self.licenseError.localizedDescription) : _(@"Loading…");
			UITableViewCell *cell = [self valueCellWithTitle:_(@"Product key") detail:detail accessory:YES];
			return cell;
		}
		NSString *detail = [NSString stringWithFormat:_(@"%@ · activated %@"), [self maskedLicenseKey:self.license.licenseKey], [self displayDate:[self.license.activatedAt substringToIndex:MIN((NSUInteger)10, self.license.activatedAt.length)]]];
		return [self valueCellWithTitle:_(@"Product key") detail:detail accessory:YES];
	}
	if (!self.heatmap) {
		return [self valueCellWithTitle:_(@"Summary") detail:self.heatmapError.localizedDescription ?: _(@"Loading…") accessory:NO];
	}
	if (indexPath.row == 0) {
		return [self valueCellWithTitle:_(@"Summary") detail:[self heatmapRangeText] accessory:YES];
	}
	IMCalendarHeatmapEntry *entry = self.heatmap.series[indexPath.row - 1];
	return [self valueCellWithTitle:[self displayDate:entry.date]
	                          detail:[NSString stringWithFormat:_(@"%ld activities"), (long)entry.count]
	                       accessory:NO];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.mutating) return;
	if (indexPath.section == IMAccountActivitySectionOnboarding && self.onboarding) {
		UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
		if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
			UISwitch *toggle = (UISwitch *)cell.accessoryView;
			[toggle setOn:!toggle.isOn animated:YES];
			[self onboardingSwitchChanged:toggle];
		}
	} else if (indexPath.section == IMAccountActivitySectionLicense) {
		[self editLicense];
	} else if (indexPath.section == IMAccountActivitySectionHeatmap && indexPath.row == 0) {
		[self editDateRange];
	}
}

@end
