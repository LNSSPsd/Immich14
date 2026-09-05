#import "SharedLinkEditorViewController.h"
#import "common.h"

@interface SharedLinkEditorViewController ()
@property (nonatomic, strong, nullable) IMSharedLink *link;
@property (nonatomic, copy) NSString *contextTitle;
@property (nonatomic, copy) IMSharedLinkEditorSaveHandler saveHandler;
@property (nonatomic, strong) UITextField *descriptionField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UITextField *slugField;
@property (nonatomic, strong) UITextField *expiryField;
@property (nonatomic, strong) UISwitch *metadataSwitch;
@property (nonatomic, strong) UISwitch *downloadSwitch;
@property (nonatomic, strong) UISwitch *uploadSwitch;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic) BOOL saving;
@property (nonatomic) BOOL isNew;
@end

@implementation SharedLinkEditorViewController

+ (instancetype)editorForNewLinkWithTitle:(NSString *)title
                               saveHandler:(IMSharedLinkEditorSaveHandler)saveHandler {
	SharedLinkEditorViewController *vc = [[self alloc] initWithStyle:UITableViewStyleInsetGrouped];
	vc.contextTitle = title.length ? [title copy] : _(@"Create Shared Link");
	vc.saveHandler = [saveHandler copy];
	vc.isNew = YES;
	return vc;
}

+ (instancetype)editorForLink:(IMSharedLink *)link
                   saveHandler:(IMSharedLinkEditorSaveHandler)saveHandler {
	SharedLinkEditorViewController *vc = [[self alloc] initWithStyle:UITableViewStyleInsetGrouped];
	vc.link = link;
	vc.contextTitle = link.title.length ? [link.title copy] : _(@"Shared link");
	vc.saveHandler = [saveHandler copy];
	vc.isNew = NO;
	return vc;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.isNew ? _(@"Create Shared Link") : _(@"Edit Shared Link");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	}

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                       target:self
	                                                                                       action:@selector(cancelTapped)];
	self.saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
	                                                                target:self
	                                                                action:@selector(saveTapped)];
	self.navigationItem.rightBarButtonItem = self.saveButton;

	self.descriptionField = [self textFieldWithPlaceholder:_(@"Description") secure:NO];
	self.descriptionField.text = self.link.linkDescription ?: @"";
	self.descriptionField.accessibilityLabel = _(@"Description");
	self.passwordField = [self textFieldWithPlaceholder:_(@"Password (leave blank to remove)") secure:YES];
	self.passwordField.text = self.link.password ?: @"";
	self.passwordField.accessibilityLabel = _(@"Password");
	self.slugField = [self textFieldWithPlaceholder:_(@"Custom URL slug") secure:NO];
	self.slugField.text = self.link.slug ?: @"";
	self.slugField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.slugField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.slugField.accessibilityLabel = _(@"Custom URL slug");
	self.expiryField = [self textFieldWithPlaceholder:_(@"Expiry (ISO-8601, blank for never)") secure:NO];
	self.expiryField.text = self.link.expiresAt ?: @"";
	self.expiryField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.expiryField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.expiryField.accessibilityLabel = _(@"Expiration date");

	self.metadataSwitch = [[UISwitch alloc] init];
	self.downloadSwitch = [[UISwitch alloc] init];
	self.uploadSwitch = [[UISwitch alloc] init];
	self.metadataSwitch.on = self.isNew ? YES : self.link.showMetadata;
	self.downloadSwitch.on = self.isNew ? YES : self.link.allowDownload;
	self.uploadSwitch.on = self.isNew ? NO : self.link.allowUpload;
	[self.metadataSwitch addTarget:self action:@selector(metadataChanged:) forControlEvents:UIControlEventValueChanged];
	[self.downloadSwitch addTarget:self action:@selector(optionChanged:) forControlEvents:UIControlEventValueChanged];
	[self.uploadSwitch addTarget:self action:@selector(optionChanged:) forControlEvents:UIControlEventValueChanged];
	[self metadataChanged:self.metadataSwitch];

	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	self.tableView.delegate = self;
	self.tableView.dataSource = self;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder secure:(BOOL)secure {
	UITextField *field = [[UITextField alloc] init];
	field.translatesAutoresizingMaskIntoConstraints = NO;
	field.placeholder = placeholder;
	field.borderStyle = UITextBorderStyleNone;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.secureTextEntry = secure;
	field.returnKeyType = UIReturnKeyDone;
	return field;
}

- (UITableViewCell *)fieldCellWithField:(UITextField *)field {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	[cell.contentView addSubview:field];
	[NSLayoutConstraint activateConstraints:@[
		[field.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
		[field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
		[field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
		[field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
	]];
	return cell;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title
                                  detail:(nullable NSString *)detail
                                  switch:(UISwitch *)toggle {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 0;
	cell.accessoryView = toggle;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessibilityTraits = UIAccessibilityTraitButton;
	return cell;
}

- (void)metadataChanged:(UISwitch *)sender {
	if (!sender.isOn) self.downloadSwitch.on = NO;
	self.downloadSwitch.enabled = sender.isOn;
	if (self.tableView.window) {
		[self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:2]]
		                     withRowAnimation:UITableViewRowAnimationNone];
	}
}

- (void)optionChanged:(UISwitch *)sender {
	(void)sender;
}

- (void)setSaving:(BOOL)saving {
	_saving = saving;
	self.saveButton.enabled = !saving;
	self.navigationItem.leftBarButtonItem.enabled = !saving;
	self.tableView.userInteractionEnabled = !saving;
	if (saving) {
		self.saveButton.title = _(@"Saving…");
	} else {
		self.saveButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
		                                                               target:self
		                                                               action:@selector(saveTapped)];
		self.navigationItem.rightBarButtonItem = self.saveButton;
	}
}

- (void)cancelTapped {
	if (self.navigationController.presentingViewController) {
		[self.navigationController dismissViewControllerAnimated:YES completion:nil];
	} else {
		[self.navigationController popViewControllerAnimated:YES];
	}
}

- (NSString *)trimmed:(UITextField *)field {
	NSString *text = [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return text ?: @"";
}

- (void)saveTapped {
	if (self.saving || !self.saveHandler) return;
	NSString *description = [self trimmed:self.descriptionField];
	NSString *password = [self trimmed:self.passwordField];
	NSString *slug = [self trimmed:self.slugField];
	NSString *expiry = [self trimmed:self.expiryField];
	if (slug.length > 0 && [slug containsString:@"\n"]) {
		[self showValidationError:_(@"The custom slug cannot contain a newline.")];
		return;
	}
	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	fields[@"description"] = description.length ? description : NSNull.null;
	fields[@"password"] = password.length ? password : NSNull.null;
	fields[@"slug"] = slug.length ? slug : NSNull.null;
	fields[@"expiresAt"] = expiry.length ? expiry : NSNull.null;
	fields[@"showMetadata"] = @(self.metadataSwitch.isOn);
	fields[@"allowDownload"] = @(self.downloadSwitch.isOn && self.metadataSwitch.isOn);
	fields[@"allowUpload"] = @(self.uploadSwitch.isOn);
	[self setSaving:YES];
	self.saveHandler(fields);
}

- (void)showValidationError:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Invalid Shared Link")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 1 : (section == 1 ? 4 : 3);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return self.isNew ? _(@"Share") : _(@"Link");
	if (section == 1) return _(@"Details");
	return _(@"Public access");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) return self.contextTitle;
	if (section == 1) return _(@"Use an ISO-8601 date such as 2026-12-31T23:59:00Z. Leave it blank for no expiration.");
	if (!self.metadataSwitch.isOn) return _(@"Downloads are disabled while metadata is hidden.");
	return _(@"These permissions apply to anyone with the link.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.textLabel.text = self.isNew ? _(@"Create a public link") : _(@"Public link settings");
		cell.detailTextLabel.text = self.contextTitle;
		cell.detailTextLabel.numberOfLines = 0;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	if (indexPath.section == 1) {
		UITextField *field = @[self.descriptionField, self.passwordField, self.slugField, self.expiryField][indexPath.row];
		return [self fieldCellWithField:field];
	}
	NSArray *titles = @[_(@"Show metadata"), _(@"Allow downloads"), _(@"Allow uploads")];
	NSArray *details = @[_(@"Include EXIF and other asset metadata."),
	                     _(@"Let visitors save the shared files."),
	                     _(@"Let visitors upload files to this link.")];
	NSArray *switches = @[self.metadataSwitch, self.downloadSwitch, self.uploadSwitch];
	return [self switchCellWithTitle:titles[indexPath.row] detail:details[indexPath.row] switch:switches[indexPath.row]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 1) {
		UITextField *field = @[self.descriptionField, self.passwordField, self.slugField, self.expiryField][indexPath.row];
		[field becomeFirstResponder];
	}
}

@end
