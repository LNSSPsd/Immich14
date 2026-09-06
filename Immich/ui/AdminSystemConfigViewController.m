#import "AdminSystemConfigViewController.h"
#import "IMSystemConfigApi.h"
#import "IMSystemConfig.h"
#import "IMSystemConfigStorageTemplateOptions.h"
#import "IMApiClient.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMSystemConfigSection) {
	IMSystemConfigSectionAccess = 0,
	IMSystemConfigSectionServices,
	IMSystemConfigSectionStorage,
	IMSystemConfigSectionServer,
	IMSystemConfigSectionDetails,
	IMSystemConfigSectionCount,
};

typedef NS_ENUM(NSInteger, IMSystemConfigToggle) {
	IMSystemConfigTogglePasswordLogin = 100,
	IMSystemConfigToggleMap,
	IMSystemConfigToggleReverseGeocoding,
	IMSystemConfigToggleMachineLearning,
	IMSystemConfigToggleLibraryWatch,
	IMSystemConfigToggleNewVersionCheck,
	IMSystemConfigToggleTrash,
	IMSystemConfigToggleStorageTemplate,
	IMSystemConfigToggleStorageHash,
};

@interface AdminSystemConfigViewController ()
@property (nonatomic, strong, nullable) IMSystemConfig *config;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic, strong, nullable) IMSystemConfigStorageTemplateOptions *storageTemplateOptions;
@property (nonatomic) BOOL loadingStorageTemplateOptions;
@end

@implementation AdminSystemConfigViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"System Configuration");
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
	UIBarButtonItem *defaults = [[UIBarButtonItem alloc] initWithTitle:_(@"Defaults")
	                                                                style:UIBarButtonItemStylePlain
	                                                               target:self
	                                                               action:@selector(defaultsTapped)];
	UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
	                                                                            target:self
	                                                                            action:@selector(reload)];
	self.navigationItem.rightBarButtonItems = @[refresh, defaults];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading && !self.mutating) [self reload];
}

- (void)reload {
	if (self.loading || self.mutating) {
		[self.refresh endRefreshing];
		return;
	}
	self.loading = YES;
	if (!self.config) self.statusLabel.text = _(@"Loading system configuration…");
	__weak typeof(self) weakSelf = self;
	[IMSystemConfigApi configWithCompletion:^(IMSystemConfig *config, NSError *error) {
		AdminSystemConfigViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loading = NO;
		[strongSelf.refresh endRefreshing];
		if (error || !config) {
			if (!strongSelf.config) strongSelf.statusLabel.text = _(@"Couldn't load system configuration. Tap to retry.");
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain
			                                                   code:2
			                                               userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned invalid system configuration.") }]];
			return;
		}
		strongSelf.config = config;
		strongSelf.statusLabel.text = nil;
		[strongSelf.tableView reloadData];
	}];
}

- (void)showError:(NSError *)error {
	if (!self.viewIfLoaded.window) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"System Configuration")
	                                                                 message:error.localizedDescription ?: _(@"The server rejected this request.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (UISwitch *)switchForTitle:(NSString *)title on:(BOOL)on tag:(NSInteger)tag {
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = on;
	toggle.tag = tag;
	toggle.enabled = !self.mutating;
	toggle.accessibilityLabel = title;
	[toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
	return toggle;
}

- (UITableViewCell *)switchCell:(NSString *)title detail:(nullable NSString *)detail on:(BOOL)on tag:(NSInteger)tag {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 0;
	cell.accessoryView = [self switchForTitle:title on:on tag:tag];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)valueCell:(NSString *)title detail:(NSString *)detail disclosure:(BOOL)disclosure {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 2;
	cell.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
	NSString *section = nil;
	NSString *key = nil;
	switch (sender.tag) {
		case IMSystemConfigTogglePasswordLogin: section = @"passwordLogin"; key = @"enabled"; break;
		case IMSystemConfigToggleMap: section = @"map"; key = @"enabled"; break;
		case IMSystemConfigToggleReverseGeocoding: section = @"reverseGeocoding"; key = @"enabled"; break;
		case IMSystemConfigToggleMachineLearning: section = @"machineLearning"; key = @"enabled"; break;
		case IMSystemConfigToggleLibraryWatch: section = @"library"; break;
		case IMSystemConfigToggleNewVersionCheck: section = @"newVersionCheck"; key = @"enabled"; break;
		case IMSystemConfigToggleTrash: section = @"trash"; key = @"enabled"; break;
		case IMSystemConfigToggleStorageTemplate: section = @"storageTemplate"; key = @"enabled"; break;
		case IMSystemConfigToggleStorageHash: section = @"storageTemplate"; key = @"hashVerificationEnabled"; break;
		default: return;
	}
	if (sender.tag == IMSystemConfigToggleLibraryWatch) {
		NSDictionary *library = [self.config.sections[@"library"] isKindOfClass:[NSDictionary class]] ? self.config.sections[@"library"] : @{};
		NSMutableDictionary *watch = [library[@"watch"] isKindOfClass:[NSDictionary class]] ? [library[@"watch"] mutableCopy] : [NSMutableDictionary dictionary];
		watch[@"enabled"] = @(sender.isOn);
		NSMutableDictionary *merged = [library mutableCopy];
		merged[@"watch"] = watch;
		[self updateSection:section values:merged];
		return;
	}
	[self updateSection:section values:@{key: @(sender.isOn)}];
}

- (void)updateSection:(NSString *)section values:(NSDictionary<NSString *, id> *)values {
	if (!self.config || self.mutating || section.length == 0 || values.count == 0) return;
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMSystemConfigApi updateSection:section values:values completion:^(IMSystemConfig *updated, NSError *error) {
		AdminSystemConfigViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = NO;
		strongSelf.tableView.userInteractionEnabled = YES;
		if (error || !updated) {
			[strongSelf.tableView reloadData];
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned invalid system configuration.")}]];
			return;
		}
		strongSelf.config = updated;
		[strongSelf.tableView reloadData];
	}];
}

- (void)promptForTextSection:(NSString *)section key:(NSString *)key title:(NSString *)title current:(NSString *)current {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = current ?: @"";
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminSystemConfigViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if ([value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
			[strongSelf showError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"The value contains unsupported control characters.") }]];
			return;
		}
		[strongSelf updateSection:section values:@{key: value ?: @""}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForTrashDays {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Trash retention")
	                                                                 message:_(@"Enter the number of days before trashed assets are removed.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = [NSString stringWithFormat:@"%ld", (long)self.config.trashDays];
		field.keyboardType = UIKeyboardTypeNumberPad;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminSystemConfigViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSScanner *scanner = [NSScanner scannerWithString:text];
		unsigned long long number = 0;
		BOOL valid = text.length > 0 && [scanner scanUnsignedLongLong:&number] && scanner.isAtEnd && number <= 9007199254740991ULL;
		if (!valid) {
			[strongSelf showError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Enter a non-negative number of days.")}]];
			return;
		}
		[strongSelf updateSection:@"trash" values:@{ @"days": @(number) }];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)presentStorageTemplateEditor {
	if (self.loading || self.mutating || self.loadingStorageTemplateOptions || !self.config) return;
	if (self.storageTemplateOptions) {
		[self presentStorageTemplateSheet];
		return;
	}
	self.loadingStorageTemplateOptions = YES;
	__weak typeof(self) weakSelf = self;
	[IMSystemConfigApi storageTemplateOptionsWithCompletion:^(IMSystemConfigStorageTemplateOptions *options, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			AdminSystemConfigViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.loadingStorageTemplateOptions = NO;
			if (error || !options) {
				NSInteger status = [IMApiClient HTTPStatusForError:error];
				if ((status == 404 || status == 405) && strongSelf.config) {
					strongSelf.storageTemplateOptions = nil;
					[strongSelf promptForCustomStorageTemplate];
					return;
				}
				[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain
				                                                   code:2
				                                               userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned invalid storage-template options.")}]];
				return;
			}
			strongSelf.storageTemplateOptions = options;
			[strongSelf presentStorageTemplateSheet];
		});
	}];
}

- (void)presentStorageTemplateSheet {
	if (!self.config || self.mutating) return;
	IMSystemConfigStorageTemplateOptions *options = self.storageTemplateOptions;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Storage template")
	                                                                 message:_(@"Choose a server preset or enter a custom template.")
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	for (NSString *preset in options.presetOptions) {
		if (![preset isKindOfClass:[NSString class]] || preset.length == 0) continue;
		[sheet addAction:[UIAlertAction actionWithTitle:preset
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
			[weakSelf saveStorageTemplate:preset];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Custom template")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
		[weakSelf promptForCustomStorageTemplate];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	NSIndexPath *path = [NSIndexPath indexPathForRow:2 inSection:IMSystemConfigSectionStorage];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:path];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.sourceView = cell ?: self.view;
		sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)promptForCustomStorageTemplate {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Custom storage template")
	                                                                 message:_(@"Use the tokens supplied by the Immich server. The server validates the template before saving.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = self.config.storageTemplate ?: @"";
		field.placeholder = _(@"Template, for example {{y}}/{{filename}}");
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
		field.keyboardType = UIKeyboardTypeASCIICapable;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminSystemConfigViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *template = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (template.length == 0 || [template rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
			[strongSelf showError:[NSError errorWithDomain:IMApiErrorDomain
			                                             code:1
			                                         userInfo:@{NSLocalizedDescriptionKey: _(@"Enter a storage template without control characters.")}]];
			return;
		}
		[strongSelf saveStorageTemplate:template];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)saveStorageTemplate:(NSString *)template {
	if (self.mutating || template.length == 0) return;
	[self updateSection:@"storageTemplate" values:@{ @"template": template }];
}

- (void)defaultsTapped {
	if (self.loading || self.mutating) return;
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	[IMSystemConfigApi defaultsWithCompletion:^(IMSystemConfig *defaults, NSError *error) {
		AdminSystemConfigViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loading = NO;
		if (error || !defaults) {
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned invalid system defaults.")}]];
			return;
		}
		NSString *message = [NSString stringWithFormat:_(@"%lu required sections validated.\nMap: %@\nTrash: %@ (%ld days)\nStorage template: %@"),
		                     (unsigned long)defaults.sections.count,
		                     defaults.mapEnabled ? _(@"On") : _(@"Off"),
		                     defaults.trashEnabled ? _(@"On") : _(@"Off"),
		                     (long)defaults.trashDays,
		                     defaults.storageTemplateEnabled ? _(@"On") : _(@"Off")];
		[strongSelf showMessage:message title:_(@"Server defaults")];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.config ? IMSystemConfigSectionCount : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case IMSystemConfigSectionAccess: return 1;
		case IMSystemConfigSectionServices: return 5;
		case IMSystemConfigSectionStorage: return 4;
		case IMSystemConfigSectionServer: return 3;
		case IMSystemConfigSectionDetails: return 1;
		default: return 0;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case IMSystemConfigSectionAccess: return _(@"Authentication");
		case IMSystemConfigSectionServices: return _(@"Services");
		case IMSystemConfigSectionStorage: return _(@"Storage and cleanup");
		case IMSystemConfigSectionServer: return _(@"Server");
		case IMSystemConfigSectionDetails: return _(@"Validation");
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == IMSystemConfigSectionAccess) return _(@"Changing authentication settings can affect other users. The complete server snapshot is preserved on every update.");
	if (section == IMSystemConfigSectionDetails) return _(@"Unknown fields from newer Immich servers are retained when a setting is changed.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	IMSystemConfig *c = self.config;
	if (indexPath.section == IMSystemConfigSectionAccess) {
		return [self switchCell:_(@"Password login") detail:nil on:c.passwordLoginEnabled tag:IMSystemConfigTogglePasswordLogin];
	}
	if (indexPath.section == IMSystemConfigSectionServices) {
		switch (indexPath.row) {
			case 0: return [self switchCell:_(@"Map") detail:nil on:c.mapEnabled tag:IMSystemConfigToggleMap];
			case 1: return [self switchCell:_(@"Reverse geocoding") detail:nil on:c.reverseGeocodingEnabled tag:IMSystemConfigToggleReverseGeocoding];
			case 2: return [self switchCell:_(@"Machine learning") detail:nil on:c.machineLearningEnabled tag:IMSystemConfigToggleMachineLearning];
			case 3: return [self switchCell:_(@"Library watcher") detail:nil on:c.libraryWatchEnabled tag:IMSystemConfigToggleLibraryWatch];
			default: return [self switchCell:_(@"New-version checks") detail:nil on:c.newVersionCheckEnabled tag:IMSystemConfigToggleNewVersionCheck];
		}
	}
	if (indexPath.section == IMSystemConfigSectionStorage) {
		switch (indexPath.row) {
			case 0: return [self switchCell:_(@"Trash") detail:nil on:c.trashEnabled tag:IMSystemConfigToggleTrash];
			case 1: return [self valueCell:_(@"Trash retention") detail:[NSString stringWithFormat:_(@"%ld days"), (long)c.trashDays] disclosure:YES];
			case 2: {
				UITableViewCell *cell = [self switchCell:_(@"Storage template") detail:c.storageTemplate.length ? c.storageTemplate : _(@"Not configured") on:c.storageTemplateEnabled tag:IMSystemConfigToggleStorageTemplate];
				cell.selectionStyle = UITableViewCellSelectionStyleDefault;
				cell.accessibilityHint = _(@"Tap to choose a preset or edit the template. Use the switch to enable or disable it.");
				return cell;
			}
			default: return [self switchCell:_(@"Verify storage hashes") detail:nil on:c.storageHashVerificationEnabled tag:IMSystemConfigToggleStorageHash];
		}
	}
	if (indexPath.section == IMSystemConfigSectionServer) {
		switch (indexPath.row) {
			case 0: return [self valueCell:_(@"External domain") detail:c.externalDomain.length ? c.externalDomain : _(@"Not configured") disclosure:YES];
			case 1: return [self valueCell:_(@"Login page message") detail:c.loginPageMessage.length ? c.loginPageMessage : _(@"None") disclosure:YES];
			default: return [self valueCell:_(@"Public users") detail:c.serverPublicUsers ? _(@"On") : _(@"Off") disclosure:NO];
		}
	}
	return [self valueCell:_(@"Required sections") detail:[NSString stringWithFormat:_(@"%lu validated"), (unsigned long)c.sections.count] disclosure:NO];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.config || self.mutating) return;
	if (indexPath.section == IMSystemConfigSectionStorage && indexPath.row == 1) {
		[self promptForTrashDays];
	} else if (indexPath.section == IMSystemConfigSectionStorage && indexPath.row == 2) {
		[self presentStorageTemplateEditor];
	} else if (indexPath.section == IMSystemConfigSectionServer && indexPath.row == 0) {
		[self promptForTextSection:@"server" key:@"externalDomain" title:_(@"External domain") current:self.config.externalDomain];
	} else if (indexPath.section == IMSystemConfigSectionServer && indexPath.row == 1) {
		[self promptForTextSection:@"server" key:@"loginPageMessage" title:_(@"Login page message") current:self.config.loginPageMessage];
	}
}

@end
