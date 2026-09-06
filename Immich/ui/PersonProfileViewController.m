#import "PersonProfileViewController.h"
#import "IMPeopleApi.h"
#import "IMPersonStatistics.h"
#import "IMSearchApi.h"
#import "IMApiClient.h"
#import "AssetGridViewController.h"
#import "PersonMergeViewController.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMPersonProfileFieldRow) {
	IMPersonProfileFieldName = 0,
	IMPersonProfileFieldBirthDate,
	IMPersonProfileFieldFavorite,
	IMPersonProfileFieldHidden,
	IMPersonProfileFieldColor,
	IMPersonProfileFieldFeaturedPhoto,
	IMPersonProfileFieldCount,
};

typedef NS_ENUM(NSInteger, IMPersonProfileSection) {
	IMPersonProfileSectionFields = 0,
	IMPersonProfileSectionStatistics,
	IMPersonProfileSectionActions,
};

@interface PersonProfileViewController ()
@property (nonatomic, copy) NSString *personId;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) IMPersonProfileSavedHandler onSaved;
@property (nonatomic, strong, nullable) IMPersonProfile *profile;
@property (nonatomic, strong, nullable) IMPersonStatistics *statistics;
@property (nonatomic, copy) NSString *editedName;
@property (nonatomic, copy, nullable) NSString *editedBirthDate;
@property (nonatomic, copy, nullable) NSString *editedColor;
@property (nonatomic, copy, nullable) NSString *editedFeatureFaceAssetId;
	@property (nonatomic) BOOL editedFavorite;
@property (nonatomic) BOOL editedHidden;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL saving;
@property (nonatomic) NSUInteger loadGeneration;
@property (nonatomic, strong, nullable) NSURLSessionTask *profileTask;
@property (nonatomic, strong, nullable) NSURLSessionTask *statisticsTask;
@property (nonatomic, strong, nullable) NSURLSessionTask *thumbnailTask;
@property (nonatomic, strong, nullable) UIImage *thumbnailImage;
@property (nonatomic) BOOL skipNextAppearanceReload;
@end

@implementation PersonProfileViewController

- (instancetype)initWithPersonId:(NSString *)personId
                      displayName:(NSString *)displayName
                         onSaved:(IMPersonProfileSavedHandler)onSaved {
	self = [self initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_personId = [personId copy];
		_displayName = [displayName copy];
		_onSaved = [onSaved copy];
		_editedName = [displayName copy] ?: @"";
	}
	return self;
}

- (void)dealloc {
	[self.profileTask cancel];
	[self.statisticsTask cancel];
	[self.thumbnailTask cancel];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.displayName.length ? self.displayName : _(@"Person");
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 52.0;
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reloadProfile) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
	                                                                                          target:self
	                                                                                          action:@selector(saveTapped)];
	self.navigationItem.rightBarButtonItem.enabled = NO;

	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.userInteractionEnabled = YES;
	if (@available(iOS 13.0, *)) self.statusLabel.textColor = UIColor.secondaryLabelColor;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reloadProfile)]];
	self.tableView.backgroundView = self.statusLabel;
	[self reloadProfile];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.skipNextAppearanceReload) {
		self.skipNextAppearanceReload = NO;
		return;
	}
	if (self.isViewLoaded && !self.loading && !self.saving && self.profile) [self reloadProfile];
}

- (void)reloadProfile {
	if (self.loading || self.saving) {
		[self.refresh endRefreshing];
		return;
	}
	[self.profileTask cancel];
	[self.statisticsTask cancel];
	self.profileTask = nil;
	self.statisticsTask = nil;
	self.loading = YES;
	self.profile = nil;
	self.statistics = nil;
	self.statusLabel.text = _(@"Loading person…");
	[self.tableView reloadData];
	NSUInteger generation = ++self.loadGeneration;
	__weak typeof(self) weakSelf = self;
	self.profileTask = [IMPeopleApi personWithId:self.personId completion:^(IMPersonProfile *person, NSError *error) {
		PersonProfileViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.loadGeneration) return;
		strongSelf.profileTask = nil;
		if (error || !person) {
			strongSelf.loading = NO;
			[strongSelf.refresh endRefreshing];
			strongSelf.statusLabel.text = _(@"Couldn't load this person. Tap to retry.");
			[strongSelf showError:error];
			return;
		}
		strongSelf.profile = person;
		strongSelf.editedName = person.name ?: @"";
		strongSelf.editedBirthDate = person.birthDate;
		strongSelf.editedColor = person.color;
		strongSelf.editedFeatureFaceAssetId = nil;
		strongSelf.thumbnailImage = nil;
		strongSelf.editedFavorite = person.isFavorite;
		strongSelf.editedHidden = person.isHidden;
		strongSelf.title = person.name.length ? person.name : (strongSelf.displayName.length ? strongSelf.displayName : _(@"Person"));
		[strongSelf loadThumbnail];
		strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
		[strongSelf.tableView reloadData];
		strongSelf.statisticsTask = [IMPeopleApi statisticsForPersonId:strongSelf.personId completion:^(IMPersonStatistics *statistics, NSError *statisticsError) {
			PersonProfileViewController *inner = weakSelf;
			if (!inner || generation != inner.loadGeneration) return;
			inner.statisticsTask = nil;
			inner.loading = NO;
			[inner.refresh endRefreshing];
			if (statisticsError || !statistics) {
				inner.statusLabel.text = nil;
				[inner.tableView reloadData];
				[inner showError:statisticsError];
				return;
			}
			inner.statistics = statistics;
			inner.statusLabel.text = nil;
			[inner.tableView reloadData];
		}];
	}];
}

- (void)loadThumbnail {
	[self.thumbnailTask cancel];
	self.thumbnailTask = nil;
	if (!self.personId.length) return;
	NSUInteger generation = self.loadGeneration;
	__weak typeof(self) weakSelf = self;
	self.thumbnailTask = [IMSearchApi thumbnailDataForPersonId:self.personId completion:^(NSData *data, NSError *error) {
		PersonProfileViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.loadGeneration) return;
		strongSelf.thumbnailTask = nil;
		if (error || data.length == 0) {
			[strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:IMPersonProfileFieldFeaturedPhoto inSection:IMPersonProfileSectionFields]]
			                                  withRowAnimation:UITableViewRowAnimationNone];
			return;
		}
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			UIImage *image = [UIImage imageWithData:data];
			dispatch_async(dispatch_get_main_queue(), ^{
				PersonProfileViewController *inner = weakSelf;
				if (!inner || generation != inner.loadGeneration) return;
				inner.thumbnailImage = image;
				[inner.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:IMPersonProfileFieldFeaturedPhoto inSection:IMPersonProfileSectionFields]]
				                                  withRowAnimation:UITableViewRowAnimationNone];
			});
		});
	}];
}

- (void)showError:(NSError *)error {
	if (!self.viewIfLoaded.window) return;
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not complete this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Person") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)valueOrUnset:(NSString *)value {
	return value.length ? value : _(@"Not set");
}

- (void)editName {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Rename Person") message:_(@"Leave the name empty to make this person unnamed.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = self.editedName ?: @"";
		field.placeholder = _(@"Name");
		field.autocapitalizationType = UITextAutocapitalizationTypeWords;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		PersonProfileViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.editedName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
		[strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:IMPersonProfileFieldName inSection:IMPersonProfileSectionFields]] withRowAnimation:UITableViewRowAnimationNone];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)isValidBirthDate:(NSString *)value {
	if (value.length == 0) return YES;
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	formatter.dateFormat = @"yyyy-MM-dd";
	formatter.lenient = NO;
	NSDate *date = [formatter dateFromString:value];
	if (!date || ![formatter stringFromDate:date].length || ![[formatter stringFromDate:date] isEqualToString:value]) return NO;
	return [date compare:[NSDate date]] != NSOrderedDescending;
}

- (void)editBirthDate {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Date of birth") message:_(@"Use YYYY-MM-DD, or leave it empty to clear the date.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = self.editedBirthDate ?: @"";
		field.placeholder = _(@"YYYY-MM-DD");
		field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		PersonProfileViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
		if (![strongSelf isValidBirthDate:value]) {
			[strongSelf showValidation:_(@"Enter a valid date on or before today.")];
			return;
		}
		strongSelf.editedBirthDate = value.length ? value : nil;
		[strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:IMPersonProfileFieldBirthDate inSection:IMPersonProfileSectionFields]] withRowAnimation:UITableViewRowAnimationNone];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)isValidColor:(NSString *)value {
	if (value.length == 0) return YES;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$" options:0 error:nil];
	return [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] != nil;
}

- (void)editColor {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Person color") message:_(@"Enter a hex color, for example #4A90E2, or leave it empty to clear.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = self.editedColor ?: @"";
		field.placeholder = _(@"#RRGGBB");
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.keyboardType = UIKeyboardTypeASCIICapable;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		PersonProfileViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
		if (![strongSelf isValidColor:value]) {
			[strongSelf showValidation:_(@"Enter a valid hexadecimal color.")];
			return;
		}
		strongSelf.editedColor = value.length ? value : nil;
		[strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:IMPersonProfileFieldColor inSection:IMPersonProfileSectionFields]] withRowAnimation:UITableViewRowAnimationNone];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseFeaturedPhoto {
	if (self.saving || self.loading) return;
	__weak typeof(self) weakSelf = self;
	[self.tableView setUserInteractionEnabled:NO];
	[IMSearchApi metadataSearchWithPersonId:self.personId page:1 completion:^(NSArray<IMAsset *> *assets, NSString *nextPage, NSError *error) {
		PersonProfileViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.tableView.userInteractionEnabled = YES;
		if (error || !assets) {
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"The person’s photos could not be loaded.")}]];
			return;
		}
		AssetGridViewController *grid = [AssetGridViewController gridWithTitle:_(@"Choose featured photo") assets:assets];
		grid.nextPageToken = nextPage;
		__weak PersonProfileViewController *weakProfile = strongSelf;
		grid.pageLoader = ^NSURLSessionTask *_Nullable(NSInteger page, void (^pageCompletion)(NSArray<IMAsset *> *_Nullable, NSString *_Nullable, NSError *_Nullable)) {
			PersonProfileViewController *inner = weakProfile;
			if (!inner) return nil;
			return [IMSearchApi metadataSearchWithPersonId:inner.personId page:page completion:pageCompletion];
		};
		grid.selectionHandler = ^(IMAsset *asset) {
			PersonProfileViewController *inner = weakSelf;
			if (!inner || !asset.assetId.length) return;
			inner.editedFeatureFaceAssetId = asset.assetId;
			inner.skipNextAppearanceReload = YES;
			[inner.navigationController popViewControllerAnimated:YES];
			[inner.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:IMPersonProfileFieldFeaturedPhoto inSection:IMPersonProfileSectionFields]]
			                                  withRowAnimation:UITableViewRowAnimationNone];
			inner.navigationItem.rightBarButtonItem.enabled = YES;
		};
		[strongSelf.navigationController pushViewController:grid animated:YES];
	}];
}

- (void)showValidation:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Invalid value") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)favoriteChanged:(UISwitch *)sender {
	self.editedFavorite = sender.isOn;
}

- (void)hiddenChanged:(UISwitch *)sender {
	self.editedHidden = sender.isOn;
}

- (void)saveTapped {
	if (self.saving || !self.profile) return;
	NSString *name = [self.editedName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
	NSString *birthDate = self.editedBirthDate ?: @"";
	NSString *color = self.editedColor ?: @"";
	if (![self isValidBirthDate:birthDate]) {
		[self showValidation:_(@"Enter a valid date on or before today.")];
		return;
	}
	if (![self isValidColor:color]) {
		[self showValidation:_(@"Enter a valid hexadecimal color.")];
		return;
	}
	self.saving = YES;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	[self.refresh endRefreshing];
	NSUInteger generation = self.loadGeneration;
	__weak typeof(self) weakSelf = self;
	[IMPeopleApi updatePersonId:self.personId
	                         name:name
	                    birthDate:birthDate
	                       hidden:@(self.editedHidden)
		                       favorite:@(self.editedFavorite)
		                          color:color
	             featureFaceAssetId:self.editedFeatureFaceAssetId
	                    completion:^(IMPersonProfile *updated, NSError *error) {
		PersonProfileViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.loadGeneration) return;
		strongSelf.saving = NO;
		strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
		if (error || !updated) {
			[strongSelf showError:error];
			return;
		}
		strongSelf.profile = updated;
		strongSelf.editedName = updated.name ?: @"";
		strongSelf.editedBirthDate = updated.birthDate;
		strongSelf.editedColor = updated.color;
		strongSelf.editedFeatureFaceAssetId = nil;
		strongSelf.thumbnailImage = nil;
		strongSelf.editedFavorite = updated.isFavorite;
		strongSelf.editedHidden = updated.isHidden;
		strongSelf.title = updated.name.length ? updated.name : (strongSelf.displayName.length ? strongSelf.displayName : _(@"Person"));
		[strongSelf.tableView reloadData];
		[strongSelf loadThumbnail];
		if (strongSelf.onSaved) strongSelf.onSaved(updated);
	}];
}

- (void)deleteTapped {
	if (self.saving || !self.profile) return;
	NSString *name = self.profile.name.length ? self.profile.name : _(@"Unnamed person");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete person?") message:name preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		PersonProfileViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.saving = YES;
		strongSelf.navigationItem.rightBarButtonItem.enabled = NO;
		[IMPeopleApi deletePersonId:strongSelf.personId completion:^(BOOL success, NSError *error) {
			PersonProfileViewController *inner = weakSelf;
			if (!inner) return;
			inner.saving = NO;
			if (!success || error) {
				inner.navigationItem.rightBarButtonItem.enabled = YES;
				[inner showError:error];
				return;
			}
			if (inner.navigationController) [inner.navigationController popViewControllerAnimated:YES];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.profile ? 3 : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == IMPersonProfileSectionFields) return IMPersonProfileFieldCount;
	if (section == IMPersonProfileSectionStatistics) return 1;
	if (section == IMPersonProfileSectionActions) return 2;
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == IMPersonProfileSectionFields) return _(@"Person details");
	if (section == IMPersonProfileSectionStatistics) return _(@"Statistics");
	if (section == IMPersonProfileSectionActions) return _(@"Actions");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *identifier = @"person-profile";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
	cell.accessoryView = nil;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.imageView.image = nil;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.accessibilityValue = nil;
	if (@available(iOS 13.0, *)) cell.textLabel.textColor = UIColor.labelColor;
	else cell.textLabel.textColor = UIColor.blackColor;
	if (indexPath.section == IMPersonProfileSectionFields) {
		NSArray<NSString *> *titles = @[ _(@"Name"), _(@"Date of birth"), _(@"Favorite"), _(@"Hidden"), _(@"Color"), _(@"Featured photo") ];
		cell.textLabel.text = titles[indexPath.row];
		if (indexPath.row == IMPersonProfileFieldName) {
			cell.detailTextLabel.text = self.editedName.length ? self.editedName : _(@"Unnamed");
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else if (indexPath.row == IMPersonProfileFieldBirthDate) {
			cell.detailTextLabel.text = [self valueOrUnset:self.editedBirthDate];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else if (indexPath.row == IMPersonProfileFieldFavorite) {
			UISwitch *toggle = [[UISwitch alloc] init];
			toggle.on = self.editedFavorite;
			[toggle addTarget:self action:@selector(favoriteChanged:) forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = toggle;
			cell.accessibilityValue = self.editedFavorite ? _(@"On") : _(@"Off");
		} else if (indexPath.row == IMPersonProfileFieldHidden) {
			UISwitch *toggle = [[UISwitch alloc] init];
			toggle.on = self.editedHidden;
			[toggle addTarget:self action:@selector(hiddenChanged:) forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = toggle;
			cell.accessibilityValue = self.editedHidden ? _(@"On") : _(@"Off");
		} else if (indexPath.row == IMPersonProfileFieldColor) {
			cell.detailTextLabel.text = [self valueOrUnset:self.editedColor];
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else {
			cell.detailTextLabel.text = self.editedFeatureFaceAssetId.length ? _(@"New photo selected") : (self.profile.thumbnailPath.length ? _(@"Current photo") : _(@"Not set"));
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.imageView.image = self.thumbnailImage;
		}
		return cell;
	}
	if (indexPath.section == IMPersonProfileSectionStatistics) {
		cell.textLabel.text = _(@"Assets");
		cell.detailTextLabel.text = self.statistics ? [NSString stringWithFormat:_(@"%ld"), (long)self.statistics.assets] : _(@"Loading…");
		return cell;
	}
	if (indexPath.row == 0) {
		cell.textLabel.text = _(@"Merge another person");
		cell.textLabel.textColor = UIColor.labelColor;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		cell.textLabel.text = _(@"Delete person");
		cell.textLabel.textColor = UIColor.systemRedColor;
	}
	cell.accessibilityTraits = UIAccessibilityTraitButton;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == IMPersonProfileSectionFields) {
		if (indexPath.row == IMPersonProfileFieldName) [self editName];
		else if (indexPath.row == IMPersonProfileFieldBirthDate) [self editBirthDate];
		else if (indexPath.row == IMPersonProfileFieldColor) [self editColor];
		else if (indexPath.row == IMPersonProfileFieldFeaturedPhoto) [self chooseFeaturedPhoto];
	} else if (indexPath.section == IMPersonProfileSectionActions) {
		if (indexPath.row == 0) {
			PersonMergeViewController *merge = [[PersonMergeViewController alloc] initWithTargetPersonId:self.personId targetName:self.profile.name];
			[self.navigationController pushViewController:merge animated:YES];
		} else {
			[self deleteTapped];
		}
	}
}

@end
