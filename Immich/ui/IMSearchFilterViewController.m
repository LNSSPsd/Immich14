#import "IMSearchFilterViewController.h"
#import "IMAlbumApi.h"
#import "IMSearchApi.h"
#import "IMTagApi.h"
#import "common.h"

@interface IMSearchAlbumPickerViewController : UITableViewController
@property (nonatomic, copy) NSArray<IMAlbum *> *albums;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedAlbumIds;
@property (nonatomic, copy, nullable) void (^completion)(NSSet<NSString *> *selectedIds);
- (instancetype)initWithAlbums:(NSArray<IMAlbum *> *)albums
                    selectedIds:(NSSet<NSString *> *)selectedIds
                      completion:(nullable void (^)(NSSet<NSString *> *selectedIds))completion;
@end

@implementation IMSearchAlbumPickerViewController

- (instancetype)initWithAlbums:(NSArray<IMAlbum *> *)albums
                    selectedIds:(NSSet<NSString *> *)selectedIds
                      completion:(void (^)(NSSet<NSString *> *selectedIds))completion {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_albums = [albums copy];
		_selectedAlbumIds = [selectedIds mutableCopy] ?: [NSMutableSet set];
		_completion = [completion copy];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Albums");
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                          target:self
	                                                                                          action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                                                                                           target:self
	                                                                                           action:@selector(doneTapped)];
	self.navigationItem.rightBarButtonItem.accessibilityLabel = _(@"Apply album filter");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.albums.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *const reuseIdentifier = @"SearchAlbumFilterCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
	}
	IMAlbum *album = self.albums[indexPath.row];
	cell.textLabel.text = album.name;
	cell.detailTextLabel.text = [NSString stringWithFormat:_(@"%ld photos"), (long)album.assetCount];
	BOOL selected = [self.selectedAlbumIds containsObject:album.albumId];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.accessibilityTraits = selected ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	IMAlbum *album = self.albums[indexPath.row];
	if ([self.selectedAlbumIds containsObject:album.albumId]) {
		[self.selectedAlbumIds removeObject:album.albumId];
	} else if (album.albumId.length > 0) {
		[self.selectedAlbumIds addObject:album.albumId];
	}
	[tableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)cancelTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doneTapped {
	if (self.completion) self.completion([self.selectedAlbumIds copy]);
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface IMSearchMultiSelectPickerViewController : UITableViewController
@property (nonatomic, copy) NSString *pickerTitle;
@property (nonatomic, copy) NSArray<NSString *> *itemIds;
@property (nonatomic, copy) NSArray<NSString *> *itemTitles;
@property (nonatomic, copy) NSArray<NSString *> *itemDetails;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIds;
@property (nonatomic, copy, nullable) void (^completion)(NSSet<NSString *> *selectedIds);
- (instancetype)initWithTitle:(NSString *)title
                         itemIds:(NSArray<NSString *> *)itemIds
                       itemTitles:(NSArray<NSString *> *)itemTitles
                      itemDetails:(NSArray<NSString *> *)itemDetails
                       selectedIds:(NSSet<NSString *> *)selectedIds
                       completion:(nullable void (^)(NSSet<NSString *> *selectedIds))completion;
@end

@implementation IMSearchMultiSelectPickerViewController

- (instancetype)initWithTitle:(NSString *)title
                         itemIds:(NSArray<NSString *> *)itemIds
                       itemTitles:(NSArray<NSString *> *)itemTitles
                      itemDetails:(NSArray<NSString *> *)itemDetails
                       selectedIds:(NSSet<NSString *> *)selectedIds
                       completion:(void (^)(NSSet<NSString *> *selectedIds))completion {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_pickerTitle = [title copy];
		_itemIds = [itemIds copy];
		_itemTitles = [itemTitles copy];
		_itemDetails = [itemDetails copy];
		_selectedIds = [selectedIds mutableCopy] ?: [NSMutableSet set];
		_completion = [completion copy];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.pickerTitle;
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                          target:self
	                                                                                          action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                                                                                           target:self
	                                                                                           action:@selector(doneTapped)];
	self.navigationItem.rightBarButtonItem.accessibilityLabel = [NSString stringWithFormat:_(@"Apply %@ filter"), self.pickerTitle.lowercaseString];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return MIN(self.itemIds.count, self.itemTitles.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *const reuseIdentifier = @"SearchMultiSelectFilterCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
		cell.textLabel.adjustsFontForContentSizeCategory = YES;
		cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
	}
	NSString *itemId = self.itemIds[indexPath.row];
	cell.textLabel.text = self.itemTitles[indexPath.row];
	cell.detailTextLabel.text = indexPath.row < self.itemDetails.count ? self.itemDetails[indexPath.row] : nil;
	BOOL selected = [self.selectedIds containsObject:itemId];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.accessibilityTraits = selected ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *itemId = self.itemIds[indexPath.row];
	if ([self.selectedIds containsObject:itemId]) [self.selectedIds removeObject:itemId];
	else if (itemId.length > 0) [self.selectedIds addObject:itemId];
	[tableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)cancelTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doneTapped {
	if (self.completion) self.completion([self.selectedIds copy]);
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface IMSearchFilterViewController ()
@property (nonatomic, copy) IMSearchFilterApplyHandler applyHandler;
@property (nonatomic, strong) UISwitch *afterSwitch;
@property (nonatomic, strong) UISwitch *beforeSwitch;
@property (nonatomic, strong) UIDatePicker *afterPicker;
@property (nonatomic, strong) UIDatePicker *beforePicker;
@property (nonatomic, strong) UISegmentedControl *typeControl;
@property (nonatomic, strong) UISegmentedControl *visibilityControl;
@property (nonatomic, strong) UISegmentedControl *ratingControl;
@property (nonatomic, strong) UISwitch *favoriteSwitch;
@property (nonatomic, strong) UISwitch *notInAlbumSwitch;
@property (nonatomic, strong) UISwitch *motionSwitch;
@property (nonatomic, strong) UISwitch *offlineSwitch;
@property (nonatomic, strong) UISwitch *withStackedSwitch;
@property (nonatomic, strong) UITextField *originalFileNameField;
@property (nonatomic, strong) UITextField *cityField;
@property (nonatomic, strong) UITextField *stateField;
@property (nonatomic, strong) UITextField *countryField;
@property (nonatomic, strong) UITextField *makeField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *lensModelField;
@property (nonatomic, strong) UIButton *albumButton;
@property (nonatomic, copy) NSArray<IMAlbum *> *albums;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedAlbumIds;
@property (nonatomic, strong) UIButton *peopleButton;
@property (nonatomic, copy) NSArray<IMPerson *> *people;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedPersonIds;
@property (nonatomic, strong) UIButton *tagButton;
@property (nonatomic, copy) NSArray<IMTag *> *tags;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTagIds;
@property (nonatomic) BOOL peopleLoadInFlight;
@property (nonatomic) BOOL tagsLoadInFlight;
@end

static NSString *IMSearchFilterISODate(NSDate *date) {
	NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
	formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	return [formatter stringFromDate:date];
}

static NSString *IMSearchFilterTrimmedText(UITextField *field) {
	NSString *value = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return value.length > 0 ? value : nil;
}

@implementation IMSearchFilterViewController

- (instancetype)initWithApplyHandler:(IMSearchFilterApplyHandler)handler {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_applyHandler = [handler copy];
		_albums = [IMAlbumApi cachedAlbums];
		_selectedAlbumIds = [NSMutableSet set];
		_people = [IMSearchApi cachedPeople];
		_selectedPersonIds = [NSMutableSet set];
		_tags = @[];
		_selectedTagIds = [NSMutableSet set];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Filter photos");
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                         target:self
	                                                                                         action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                                                                                          target:self
	                                                                                          action:@selector(applyTapped)];

	UIScrollView *scroll = [[UIScrollView alloc] init];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:scroll];
	UIStackView *stack = [[UIStackView alloc] init];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 10;
	stack.layoutMargins = UIEdgeInsetsMake(20, 20, 28, 20);
	stack.layoutMarginsRelativeArrangement = YES;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[scroll addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
		[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
	]];

	UILabel *hint = [self labelWithText:_(@"Combine dates, media type, visibility, rating, people, tags, album membership, and display options.")];
	hint.numberOfLines = 0;
	if (@available(iOS 13.0, *)) hint.textColor = UIColor.secondaryLabelColor;
	[stack addArrangedSubview:hint];

	self.typeControl = [[UISegmentedControl alloc] initWithItems:@[ _(@"All"), _(@"Photos"), _(@"Videos") ]];
	self.typeControl.selectedSegmentIndex = 0;
	self.typeControl.accessibilityLabel = _(@"Media type");
	[stack addArrangedSubview:[self labelWithText:_(@"Media type")]];
	[stack addArrangedSubview:self.typeControl];

	self.visibilityControl = [[UISegmentedControl alloc] initWithItems:@[ _(@"All"), _(@"Timeline"), _(@"Archive"), _(@"Hidden"), _(@"Locked") ]];
	self.visibilityControl.selectedSegmentIndex = 0;
	self.visibilityControl.accessibilityLabel = _(@"Visibility");
	[stack addArrangedSubview:[self labelWithText:_(@"Visibility")]];
	[stack addArrangedSubview:self.visibilityControl];

	self.ratingControl = [[UISegmentedControl alloc] initWithItems:@[ _(@"Any"), _(@"Unrated"), @"1", @"2", @"3", @"4", @"5" ]];
	self.ratingControl.selectedSegmentIndex = 0;
	self.ratingControl.accessibilityLabel = _(@"Rating");
	[stack addArrangedSubview:[self labelWithText:_(@"Rating")]];
	[stack addArrangedSubview:self.ratingControl];

	self.afterSwitch = [[UISwitch alloc] init];
	self.afterSwitch.accessibilityLabel = _(@"Use taken-after date");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Taken after") control:self.afterSwitch]];
	self.afterPicker = [self datePicker];
	self.afterPicker.date = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:-30 toDate:[NSDate date] options:0];
	self.afterPicker.enabled = NO;
	[stack addArrangedSubview:self.afterPicker];
	[self.afterSwitch addTarget:self action:@selector(dateSwitchChanged:) forControlEvents:UIControlEventValueChanged];

	self.beforeSwitch = [[UISwitch alloc] init];
	self.beforeSwitch.accessibilityLabel = _(@"Use taken-before date");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Taken before") control:self.beforeSwitch]];
	self.beforePicker = [self datePicker];
	self.beforePicker.enabled = NO;
	[stack addArrangedSubview:self.beforePicker];
	[self.beforeSwitch addTarget:self action:@selector(dateSwitchChanged:) forControlEvents:UIControlEventValueChanged];

	[stack addArrangedSubview:[self labelWithText:_(@"Metadata text")]];
	[stack addArrangedSubview:[self labelWithText:_(@"Original filename")]];
	self.originalFileNameField = [self textFieldWithPlaceholder:_(@"Filter by original filename")
	                                             accessibilityLabel:_(@"Original filename")];
	[stack addArrangedSubview:self.originalFileNameField];
	[stack addArrangedSubview:[self labelWithText:_(@"City")]];
	self.cityField = [self textFieldWithPlaceholder:_(@"Filter by city") accessibilityLabel:_(@"City")];
	[stack addArrangedSubview:self.cityField];
	[stack addArrangedSubview:[self labelWithText:_(@"State or province")]];
	self.stateField = [self textFieldWithPlaceholder:_(@"Filter by state or province") accessibilityLabel:_(@"State or province")];
	[stack addArrangedSubview:self.stateField];
	[stack addArrangedSubview:[self labelWithText:_(@"Country")]];
	self.countryField = [self textFieldWithPlaceholder:_(@"Filter by country") accessibilityLabel:_(@"Country")];
	[stack addArrangedSubview:self.countryField];
	[stack addArrangedSubview:[self labelWithText:_(@"Camera make")]];
	self.makeField = [self textFieldWithPlaceholder:_(@"Filter by camera make") accessibilityLabel:_(@"Camera make")];
	[stack addArrangedSubview:self.makeField];
	[stack addArrangedSubview:[self labelWithText:_(@"Camera model")]];
	self.modelField = [self textFieldWithPlaceholder:_(@"Filter by camera model") accessibilityLabel:_(@"Camera model")];
	[stack addArrangedSubview:self.modelField];
	[stack addArrangedSubview:[self labelWithText:_(@"Lens model")]];
	self.lensModelField = [self textFieldWithPlaceholder:_(@"Filter by lens model") accessibilityLabel:_(@"Lens model")];
	[stack addArrangedSubview:self.lensModelField];

	self.favoriteSwitch = [[UISwitch alloc] init];
	self.favoriteSwitch.accessibilityLabel = _(@"Favorites only");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Favorites only") control:self.favoriteSwitch]];
	self.notInAlbumSwitch = [[UISwitch alloc] init];
	self.notInAlbumSwitch.accessibilityLabel = _(@"Not in an album");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Not in an album") control:self.notInAlbumSwitch]];
	self.motionSwitch = [[UISwitch alloc] init];
	self.motionSwitch.accessibilityLabel = _(@"Motion photos only");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Motion photos only") control:self.motionSwitch]];
	self.offlineSwitch = [[UISwitch alloc] init];
	self.offlineSwitch.accessibilityLabel = _(@"Offline assets only");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Offline assets only") control:self.offlineSwitch]];
	self.withStackedSwitch = [[UISwitch alloc] init];
	self.withStackedSwitch.accessibilityLabel = _(@"Include stacked assets");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Include stacked assets") control:self.withStackedSwitch]];

	[stack addArrangedSubview:[self labelWithText:_(@"Album membership")]];
	self.albumButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.albumButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.albumButton setTitle:_(@"Any album") forState:UIControlStateNormal];
	self.albumButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	self.albumButton.titleLabel.adjustsFontForContentSizeCategory = YES;
	self.albumButton.accessibilityLabel = _(@"Album membership filter");
	[self.albumButton addTarget:self action:@selector(albumButtonTapped) forControlEvents:UIControlEventTouchUpInside];
	[stack addArrangedSubview:self.albumButton];

	[stack addArrangedSubview:[self labelWithText:_(@"People")]];
	self.peopleButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.peopleButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.peopleButton setTitle:_(@"Any person") forState:UIControlStateNormal];
	self.peopleButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	self.peopleButton.titleLabel.adjustsFontForContentSizeCategory = YES;
	self.peopleButton.accessibilityLabel = _(@"People filter");
	[self.peopleButton addTarget:self action:@selector(peopleButtonTapped) forControlEvents:UIControlEventTouchUpInside];
	[stack addArrangedSubview:self.peopleButton];

	[stack addArrangedSubview:[self labelWithText:_(@"Tags")]];
	self.tagButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.tagButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.tagButton setTitle:_(@"Any tag") forState:UIControlStateNormal];
	self.tagButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	self.tagButton.titleLabel.adjustsFontForContentSizeCategory = YES;
	self.tagButton.accessibilityLabel = _(@"Tags filter");
	[self.tagButton addTarget:self action:@selector(tagButtonTapped) forControlEvents:UIControlEventTouchUpInside];
	[stack addArrangedSubview:self.tagButton];

	if (self.albums.count == 0) {
		__weak typeof(self) weakSelf = self;
		[IMAlbumApi allAlbumsWithCompletion:^(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error) {
			if (albums.count == 0 || error) return;
			IMSearchFilterViewController *strongSelf = weakSelf;
			if (strongSelf) strongSelf.albums = albums;
		}];
	}
	if (self.people.count == 0) {
		[self loadPeople];
	}
	[self loadTags];
}

- (UILabel *)labelWithText:(NSString *)text {
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	label.adjustsFontForContentSizeCategory = YES;
	return label;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder accessibilityLabel:(NSString *)accessibilityLabel {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.accessibilityLabel = accessibilityLabel;
	field.borderStyle = UITextBorderStyleRoundedRect;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	field.adjustsFontForContentSizeCategory = YES;
	field.returnKeyType = UIReturnKeyNext;
	field.translatesAutoresizingMaskIntoConstraints = NO;
	[field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
	return field;
}

- (UIView *)rowWithTitle:(NSString *)title control:(UIControl *)control {
	UIView *row = [[UIView alloc] init];
	UILabel *label = [self labelWithText:title];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	control.translatesAutoresizingMaskIntoConstraints = NO;
	[row addSubview:label];
	[row addSubview:control];
	[NSLayoutConstraint activateConstraints:@[
		[label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
		[label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
		[label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12],
		[control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
		[control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
		[row.heightAnchor constraintGreaterThanOrEqualToConstant:44],
	]];
	return row;
}

- (UIDatePicker *)datePicker {
	UIDatePicker *picker = [[UIDatePicker alloc] init];
	picker.datePickerMode = UIDatePickerModeDate;
	if (@available(iOS 13.4, *)) picker.preferredDatePickerStyle = UIDatePickerStyleWheels;
	picker.maximumDate = [NSDate date];
	picker.translatesAutoresizingMaskIntoConstraints = NO;
	picker.accessibilityLabel = _(@"Date");
	return picker;
}

- (void)dateSwitchChanged:(UISwitch *)sender {
	if (sender == self.afterSwitch) self.afterPicker.enabled = sender.isOn;
	if (sender == self.beforeSwitch) self.beforePicker.enabled = sender.isOn;
}

- (void)albumButtonTapped {
	NSArray<IMAlbum *> *albums = [self.albums sortedArrayUsingComparator:^NSComparisonResult(IMAlbum *a, IMAlbum *b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	if (albums.count == 0) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Album membership")
		                                                                 message:_(@"No albums are available for this account.")
		                                                          preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	__weak typeof(self) weakSelf = self;
	IMSearchAlbumPickerViewController *picker = [[IMSearchAlbumPickerViewController alloc]
		initWithAlbums:albums
		selectedIds:self.selectedAlbumIds
		completion:^(NSSet<NSString *> *selectedIds) {
			IMSearchFilterViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.selectedAlbumIds = [selectedIds mutableCopy];
			NSString *title;
			if (selectedIds.count == 0) {
				title = _(@"Any album");
			} else if (selectedIds.count == 1) {
				IMAlbum *album = nil;
				for (IMAlbum *candidate in albums) {
					if ([selectedIds containsObject:candidate.albumId]) { album = candidate; break; }
				}
				title = album.name.length ? album.name : _(@"1 album selected");
			} else {
				title = [NSString stringWithFormat:_(@"%ld albums selected"), (long)selectedIds.count];
			}
			[strongSelf.albumButton setTitle:title forState:UIControlStateNormal];
		}];
	UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:picker];
	navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigationController animated:YES completion:nil];
}

- (void)loadPeople {
	if (self.peopleLoadInFlight) return;
	self.peopleLoadInFlight = YES;
	__weak typeof(self) weakSelf = self;
	[IMSearchApi allPeopleWithCompletion:^(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error) {
		IMSearchFilterViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.peopleLoadInFlight = NO;
		if (error || people.count == 0) return;
		strongSelf.people = people;
	}];
}

- (void)loadTags {
	if (self.tagsLoadInFlight) return;
	self.tagsLoadInFlight = YES;
	__weak typeof(self) weakSelf = self;
	[IMTagApi allTagsWithCompletion:^(NSArray<IMTag *> *_Nullable tags, NSError *_Nullable error) {
		IMSearchFilterViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.tagsLoadInFlight = NO;
		if (error || tags.count == 0) return;
		strongSelf.tags = tags;
	}];
}

- (void)presentEmptySelectionAlertForTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)peopleButtonTapped {
	NSArray<IMPerson *> *people = [self.people sortedArrayUsingComparator:^NSComparisonResult(IMPerson *a, IMPerson *b) {
		NSString *aName = a.name.length ? a.name : _(@"Unnamed person");
		NSString *bName = b.name.length ? b.name : _(@"Unnamed person");
		NSComparisonResult result = [aName localizedCaseInsensitiveCompare:bName];
		return result == NSOrderedSame ? [a.personId compare:b.personId] : result;
	}];
	NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:people.count];
	NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:people.count];
	NSMutableArray<NSString *> *details = [NSMutableArray arrayWithCapacity:people.count];
	for (IMPerson *person in people) {
		if (person.personId.length == 0) continue;
		[ids addObject:person.personId];
		[titles addObject:person.name.length ? person.name : _(@"Unnamed person")];
		[details addObject:person.isHidden ? _(@"Hidden") : @""];
	}
	if (ids.count == 0) {
		[self loadPeople];
		[self presentEmptySelectionAlertForTitle:_(@"People") message:_(@"No people are available for this account.")];
		return;
	}
	__weak typeof(self) weakSelf = self;
	IMSearchMultiSelectPickerViewController *picker = [[IMSearchMultiSelectPickerViewController alloc]
		initWithTitle:_(@"People")
		itemIds:ids
		itemTitles:titles
		itemDetails:details
		selectedIds:self.selectedPersonIds
		completion:^(NSSet<NSString *> *selectedIds) {
			IMSearchFilterViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.selectedPersonIds = [selectedIds mutableCopy];
			NSString *title;
			if (selectedIds.count == 0) title = _(@"Any person");
			else if (selectedIds.count == 1) {
				NSUInteger index = [ids indexOfObject:[[selectedIds allObjects] firstObject]];
				title = index != NSNotFound ? titles[index] : _(@"1 person selected");
			} else title = [NSString stringWithFormat:_(@"%ld people selected"), (long)selectedIds.count];
			[strongSelf.peopleButton setTitle:title forState:UIControlStateNormal];
		}];
	UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:picker];
	navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigationController animated:YES completion:nil];
}

- (void)tagButtonTapped {
	NSArray<IMTag *> *tags = [self.tags sortedArrayUsingComparator:^NSComparisonResult(IMTag *a, IMTag *b) {
		NSString *aName = a.name.length ? a.name : (a.value.length ? a.value : _(@"Unnamed tag"));
		NSString *bName = b.name.length ? b.name : (b.value.length ? b.value : _(@"Unnamed tag"));
		NSComparisonResult result = [aName localizedCaseInsensitiveCompare:bName];
		return result == NSOrderedSame ? [a.tagId compare:b.tagId] : result;
	}];
	NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:tags.count];
	NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:tags.count];
	NSMutableArray<NSString *> *details = [NSMutableArray arrayWithCapacity:tags.count];
	for (IMTag *tag in tags) {
		if (tag.tagId.length == 0) continue;
		[ids addObject:tag.tagId];
		[titles addObject:tag.name.length ? tag.name : (tag.value.length ? tag.value : _(@"Unnamed tag"))];
		[details addObject:tag.parentId.length ? _(@"Nested tag") : @""];
	}
	if (ids.count == 0) {
		[self loadTags];
		[self presentEmptySelectionAlertForTitle:_(@"Tags") message:_(@"No tags are available for this account.")];
		return;
	}
	__weak typeof(self) weakSelf = self;
	IMSearchMultiSelectPickerViewController *picker = [[IMSearchMultiSelectPickerViewController alloc]
		initWithTitle:_(@"Tags")
		itemIds:ids
		itemTitles:titles
		itemDetails:details
		selectedIds:self.selectedTagIds
		completion:^(NSSet<NSString *> *selectedIds) {
			IMSearchFilterViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.selectedTagIds = [selectedIds mutableCopy];
			NSString *title;
			if (selectedIds.count == 0) title = _(@"Any tag");
			else if (selectedIds.count == 1) {
				NSUInteger index = [ids indexOfObject:[[selectedIds allObjects] firstObject]];
				title = index != NSNotFound ? titles[index] : _(@"1 tag selected");
			} else title = [NSString stringWithFormat:_(@"%ld tags selected"), (long)selectedIds.count];
			[strongSelf.tagButton setTitle:title forState:UIControlStateNormal];
		}];
	UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:picker];
	navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:navigationController animated:YES completion:nil];
}

- (void)cancelTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyTapped {
	NSDate *afterDate = self.afterPicker.date;
	NSDate *beforeDate = self.beforePicker.date;
	if (self.afterSwitch.isOn && self.beforeSwitch.isOn && [afterDate compare:beforeDate] == NSOrderedDescending) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Invalid date range")
	                                                                 message:_(@"The start date must be before the end date.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	NSMutableDictionary<NSString *, id> *criteria = [NSMutableDictionary dictionary];
	if (self.afterSwitch.isOn) criteria[@"takenAfter"] = IMSearchFilterISODate(afterDate);
	if (self.beforeSwitch.isOn) {
		NSDate *endOfDay = [[NSCalendar currentCalendar] dateByAddingUnit:NSCalendarUnitDay value:1 toDate:beforeDate options:0];
		endOfDay = [endOfDay dateByAddingTimeInterval:-0.001];
		criteria[@"takenBefore"] = IMSearchFilterISODate(endOfDay);
	}
	if (self.typeControl.selectedSegmentIndex == 1) criteria[@"type"] = @"IMAGE";
	if (self.typeControl.selectedSegmentIndex == 2) criteria[@"type"] = @"VIDEO";
	if (self.visibilityControl.selectedSegmentIndex > 0) {
		criteria[@"visibility"] = @[ @"timeline", @"archive", @"hidden", @"locked" ][self.visibilityControl.selectedSegmentIndex - 1];
	}
	if (self.ratingControl.selectedSegmentIndex == 1) criteria[@"rating"] = [NSNull null];
	if (self.ratingControl.selectedSegmentIndex >= 2) criteria[@"rating"] = @(self.ratingControl.selectedSegmentIndex - 1);
	if (self.favoriteSwitch.isOn) criteria[@"isFavorite"] = @YES;
	if (self.notInAlbumSwitch.isOn) criteria[@"isNotInAlbum"] = @YES;
	if (self.motionSwitch.isOn) criteria[@"isMotion"] = @YES;
	if (self.offlineSwitch.isOn) criteria[@"isOffline"] = @YES;
	if (self.withStackedSwitch.isOn) criteria[@"withStacked"] = @YES;
	NSString *originalFileName = IMSearchFilterTrimmedText(self.originalFileNameField);
	if (originalFileName) criteria[@"originalFileName"] = originalFileName;
	NSString *city = IMSearchFilterTrimmedText(self.cityField);
	if (city) criteria[@"city"] = city;
	NSString *state = IMSearchFilterTrimmedText(self.stateField);
	if (state) criteria[@"state"] = state;
	NSString *country = IMSearchFilterTrimmedText(self.countryField);
	if (country) criteria[@"country"] = country;
	NSString *make = IMSearchFilterTrimmedText(self.makeField);
	if (make) criteria[@"make"] = make;
	NSString *model = IMSearchFilterTrimmedText(self.modelField);
	if (model) criteria[@"model"] = model;
	NSString *lensModel = IMSearchFilterTrimmedText(self.lensModelField);
	if (lensModel) criteria[@"lensModel"] = lensModel;
	if (self.selectedAlbumIds.count > 0) {
		criteria[@"albumIds"] = [[self.selectedAlbumIds allObjects] sortedArrayUsingSelector:@selector(compare:)];
	}
	if (self.selectedPersonIds.count > 0) {
		criteria[@"personIds"] = [[self.selectedPersonIds allObjects] sortedArrayUsingSelector:@selector(compare:)];
	}
	if (self.selectedTagIds.count > 0) {
		criteria[@"tagIds"] = [[self.selectedTagIds allObjects] sortedArrayUsingSelector:@selector(compare:)];
	}
	if (self.applyHandler) self.applyHandler(criteria.copy);
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
