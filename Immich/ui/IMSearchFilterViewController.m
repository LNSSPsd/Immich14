#import "IMSearchFilterViewController.h"
#import "common.h"

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
@end

static NSString *IMSearchFilterISODate(NSDate *date) {
	NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
	formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	return [formatter stringFromDate:date];
}

@implementation IMSearchFilterViewController

- (instancetype)initWithApplyHandler:(IMSearchFilterApplyHandler)handler {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_applyHandler = [handler copy];
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

	UILabel *hint = [self labelWithText:_(@"Combine dates, media type, visibility, rating, and display options.")];
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

	self.favoriteSwitch = [[UISwitch alloc] init];
	self.favoriteSwitch.accessibilityLabel = _(@"Favorites only");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Favorites only") control:self.favoriteSwitch]];
	self.notInAlbumSwitch = [[UISwitch alloc] init];
	self.notInAlbumSwitch.accessibilityLabel = _(@"Not in an album");
	[stack addArrangedSubview:[self rowWithTitle:_(@"Not in an album") control:self.notInAlbumSwitch]];
}

- (UILabel *)labelWithText:(NSString *)text {
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	label.adjustsFontForContentSizeCategory = YES;
	return label;
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
	if (self.applyHandler) self.applyHandler(criteria.copy);
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
