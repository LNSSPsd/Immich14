#import "AssetMetadataEditorViewController.h"
#import "IMAssetApi.h"
#import "common.h"

@interface AssetMetadataEditorViewController ()
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, copy) NSDictionary *initialValues;
@property (nonatomic, strong) UITextField *descriptionField;
@property (nonatomic, strong) UITextField *dateField;
@property (nonatomic, strong) UITextField *latitudeField;
@property (nonatomic, strong) UITextField *longitudeField;
@property (nonatomic, strong) UISegmentedControl *ratingControl;
@property (nonatomic, strong) UISegmentedControl *visibilityControl;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic) BOOL saving;
@end

@implementation AssetMetadataEditorViewController

- (instancetype)initWithAssetId:(NSString *)assetId initialValues:(NSDictionary *)initialValues {
	self = [super init];
	if (self) {
		_assetId = [assetId copy];
		_initialValues = [initialValues copy] ?: @{};
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Edit metadata");
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                         target:self
	                                                                                         action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
	                                                                                          target:self
	                                                                                          action:@selector(saveTapped)];

	UIScrollView *scroll = [[UIScrollView alloc] init];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:scroll];
	UIStackView *stack = [[UIStackView alloc] init];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 8;
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
		[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
	]];

	self.descriptionField = [self textFieldWithPlaceholder:_(@"Description")];
	self.descriptionField.text = [self stringValueForKey:@"description" fallbackKey:@"exifDescription"];
	[stack addArrangedSubview:[self labelWithText:_(@"Description")]];
	[stack addArrangedSubview:self.descriptionField];

	self.dateField = [self textFieldWithPlaceholder:_(@"YYYY-MM-DDTHH:mm:ssZ")];
	self.dateField.text = [self stringValueForKey:@"dateTimeOriginal" fallbackKey:@"fileCreatedAt"];
	self.dateField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.dateField.keyboardType = UIKeyboardTypeASCIICapable;
	[stack addArrangedSubview:[self labelWithText:_(@"Date and time")]];
	[stack addArrangedSubview:self.dateField];

	NSDictionary *exif = [self.initialValues[@"exifInfo"] isKindOfClass:[NSDictionary class]] ? self.initialValues[@"exifInfo"] : @{};
	self.latitudeField = [self textFieldWithPlaceholder:_(@"Latitude (-90 to 90)")];
	self.longitudeField = [self textFieldWithPlaceholder:_(@"Longitude (-180 to 180)")];
	self.latitudeField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
	self.longitudeField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
	self.latitudeField.text = [self numberString:exif[@"latitude"]];
	self.longitudeField.text = [self numberString:exif[@"longitude"]];
	[stack addArrangedSubview:[self labelWithText:_(@"Location (optional)")]];
	[stack addArrangedSubview:self.latitudeField];
	[stack addArrangedSubview:self.longitudeField];

	self.ratingControl = [[UISegmentedControl alloc] initWithItems:@[ _(@"Unrated"), @"1", @"2", @"3", @"4", @"5", _(@"Rejected") ]];
	self.ratingControl.selectedSegmentIndex = [self ratingIndex];
	[stack addArrangedSubview:[self labelWithText:_(@"Rating")]];
	[stack addArrangedSubview:self.ratingControl];

	self.visibilityControl = [[UISegmentedControl alloc] initWithItems:@[ _(@"Timeline"), _(@"Archive"), _(@"Hidden"), _(@"Locked") ]];
	NSString *visibility = [self.initialValues[@"visibility"] isKindOfClass:[NSString class]] ? self.initialValues[@"visibility"] : @"timeline";
	self.visibilityControl.selectedSegmentIndex = [visibility isEqualToString:@"archive"] ? 1 : ([visibility isEqualToString:@"hidden"] ? 2 : ([visibility isEqualToString:@"locked"] ? 3 : 0));
	[stack addArrangedSubview:[self labelWithText:_(@"Visibility")]];
	[stack addArrangedSubview:self.visibilityControl];

	UILabel *hint = [self labelWithText:_(@"Changes are saved to your Immich server. The date accepts the ISO-8601 format shown above.")];
	hint.numberOfLines = 0;
	if (@available(iOS 13.0, *)) {
		hint.textColor = UIColor.secondaryLabelColor;
	}
	[stack addArrangedSubview:hint];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.hidesWhenStopped = YES;
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
	                                         [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]]];
}

- (UILabel *)labelWithText:(NSString *)text {
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	label.adjustsFontForContentSizeCategory = YES;
	return label;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.borderStyle = UITextBorderStyleRoundedRect;
	field.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.translatesAutoresizingMaskIntoConstraints = NO;
	[field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
	return field;
}

- (NSString *)stringValueForKey:(NSString *)key fallbackKey:(NSString *)fallback {
	id value = self.initialValues[key];
	if (![value isKindOfClass:[NSString class]] || ((NSString *)value).length == 0) {
		value = self.initialValues[fallback];
	}
	return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (NSString *)numberString:(id)value {
	return [value isKindOfClass:[NSNumber class]] ? [(NSNumber *)value stringValue] : ([value isKindOfClass:[NSString class]] ? value : @"");
}

- (NSInteger)ratingIndex {
	id value = self.initialValues[@"rating"];
	if (![value isKindOfClass:[NSNumber class]]) {
		return 0;
	}
	NSInteger rating = [(NSNumber *)value integerValue];
	return rating < 0 ? 6 : (rating >= 1 && rating <= 5 ? rating : 0);
}

- (void)cancelTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTapped {
	if (self.saving) {
		return;
	}
	double latitude = self.latitudeField.text.doubleValue;
	double longitude = self.longitudeField.text.doubleValue;
	BOOL hasLatitude = self.latitudeField.text.length > 0;
	BOOL hasLongitude = self.longitudeField.text.length > 0;
	if ((hasLatitude && (latitude < -90 || latitude > 90)) || (hasLongitude && (longitude < -180 || longitude > 180))) {
		[self showError:_(@"Enter a valid latitude and longitude.")];
		return;
	}
	if (hasLatitude != hasLongitude) {
		[self showError:_(@"Enter both latitude and longitude, or leave both blank.")];
		return;
	}
	NSMutableDictionary<NSString *, id> *fields = [NSMutableDictionary dictionary];
	fields[@"description"] = self.descriptionField.text ?: @"";
	fields[@"dateTimeOriginal"] = self.dateField.text ?: @"";
	if (hasLatitude) {
		fields[@"latitude"] = @(latitude);
		fields[@"longitude"] = @(longitude);
	}
	fields[@"rating"] = self.ratingControl.selectedSegmentIndex == 0 ? [NSNull null] : (self.ratingControl.selectedSegmentIndex == 6 ? @(-1) : @(self.ratingControl.selectedSegmentIndex));
	NSArray *visibilityValues = @[ @"timeline", @"archive", @"hidden", @"locked" ];
	fields[@"visibility"] = visibilityValues[self.visibilityControl.selectedSegmentIndex];

	self.saving = YES;
	self.navigationItem.leftBarButtonItem.enabled = NO;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMAssetApi updateAssetId:self.assetId fields:fields completion:^(BOOL success, NSError *_Nullable error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.saving = NO;
			[strongSelf.spinner stopAnimating];
			strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
			strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
			if (!success) {
				[strongSelf showError:error.localizedDescription ?: _(@"Couldn't save metadata.")];
				return;
			}
			if (strongSelf.onSaved) strongSelf.onSaved();
			[strongSelf dismissViewControllerAnimated:YES completion:nil];
		});
	}];
}

- (void)showError:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn't save") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
