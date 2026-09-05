#import "AdminUserPreferencesViewController.h"
#import "IMAdminApi.h"
#import "IMApiClient.h"
#import "IMAdminUserPreferences.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMAdminPreferencesSection) {
	IMAdminPreferencesSectionEmail = 0,
	IMAdminPreferencesSectionFeatures,
	IMAdminPreferencesSectionSidebar,
	IMAdminPreferencesSectionDefaults,
	IMAdminPreferencesSectionPlayback,
	IMAdminPreferencesSectionPurchase,
	IMAdminPreferencesSectionCount,
};

typedef NS_ENUM(NSInteger, IMAdminPreferenceToggle) {
	IMAdminPreferenceToggleEmailEnabled = 100,
	IMAdminPreferenceToggleAlbumInvite,
	IMAdminPreferenceToggleAlbumUpdate,
	IMAdminPreferenceToggleMemories,
	IMAdminPreferenceTogglePeople,
	IMAdminPreferenceToggleSharedLinks,
	IMAdminPreferenceToggleTags,
	IMAdminPreferenceToggleRatings,
	IMAdminPreferenceToggleFolders,
	IMAdminPreferenceTogglePeopleSidebar,
	IMAdminPreferenceToggleSharedLinksSidebar,
	IMAdminPreferenceToggleTagsSidebar,
	IMAdminPreferenceToggleFoldersSidebar,
	IMAdminPreferenceToggleRecentlyAddedSidebar,
	IMAdminPreferenceToggleCast,
	IMAdminPreferenceToggleEmbeddedVideos,
	IMAdminPreferenceToggleSupportBadge,
};

@interface AdminUserPreferencesViewController ()
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy, nullable) NSString *userName;
@property (nonatomic, strong, nullable) IMAdminUserPreferences *preferences;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic) BOOL loading;
@property (nonatomic) NSUInteger updateGeneration;
@end

@implementation AdminUserPreferencesViewController

- (instancetype)initWithUserId:(NSString *)userId userName:(NSString *)userName {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_userId = [userId copy];
		_userName = [userName copy];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.userName.length ? [NSString stringWithFormat:_(@"%@’s Preferences"), self.userName] : _(@"User Preferences");
	if (@available(iOS 13.0, *)) self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	else self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reloadPreferences) forControlEvents:UIControlEventValueChanged];
	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.hidesWhenStopped = YES;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
	[self reloadPreferences];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading) [self reloadPreferences];
}

- (void)reloadPreferences {
	if (self.loading || self.userId.length == 0) {
		[self.refreshControl endRefreshing];
		return;
	}
	self.loading = YES;
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMAdminApi preferencesForUserId:self.userId completion:^(IMAdminUserPreferences *preferences, NSError *error) {
		AdminUserPreferencesViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loading = NO;
		[strongSelf.spinner stopAnimating];
		[strongSelf.refreshControl endRefreshing];
		if (error || !preferences) {
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{ NSLocalizedDescriptionKey: _(@"The server returned invalid user preferences.") }]];
			return;
		}
		strongSelf.preferences = preferences;
		[strongSelf.tableView reloadData];
	}];
}

- (void)showError:(NSError *)error {
	if (!self.viewIfLoaded.window) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"User Preferences")
	                                                                 message:error.localizedDescription ?: _(@"The server rejected this request.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)updateSection:(NSString *)section values:(NSDictionary<NSString *, id> *)values {
	if (!self.preferences || section.length == 0 || values.count == 0) return;
	NSMutableDictionary *sectionValues = [NSMutableDictionary dictionary];
	id existing = self.preferences.rawDictionary[section];
	if ([existing isKindOfClass:[NSDictionary class]]) [sectionValues addEntriesFromDictionary:existing];
	[sectionValues addEntriesFromDictionary:values];
	NSDictionary *body = @{ section: sectionValues };
	NSUInteger generation = ++self.updateGeneration;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMAdminApi updatePreferencesForUserId:self.userId values:body completion:^(IMAdminUserPreferences *preferences, NSError *error) {
		AdminUserPreferencesViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.updateGeneration) return;
		strongSelf.tableView.userInteractionEnabled = YES;
		if (error || !preferences) {
			[strongSelf.tableView reloadData];
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{ NSLocalizedDescriptionKey: _(@"The server returned invalid user preferences.") }]];
			return;
		}
		strongSelf.preferences = preferences;
		[strongSelf.tableView reloadData];
	}];
}

- (UISwitch *)switchForTitle:(NSString *)title on:(BOOL)on tag:(NSInteger)tag enabled:(BOOL)enabled {
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = on;
	toggle.tag = tag;
	toggle.enabled = enabled;
	toggle.accessibilityLabel = title;
	[toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
	return toggle;
}

- (UITableViewCell *)switchCell:(NSString *)title detail:(nullable NSString *)detail on:(BOOL)on tag:(NSInteger)tag enabled:(BOOL)enabled {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 0;
	cell.accessoryView = [self switchForTitle:title on:on tag:tag enabled:enabled];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (UITableViewCell *)valueCell:(NSString *)title detail:(NSString *)detail {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return IMAdminPreferencesSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case IMAdminPreferencesSectionEmail: return 3;
		case IMAdminPreferencesSectionFeatures: return 6;
		case IMAdminPreferencesSectionSidebar: return 5;
		case IMAdminPreferencesSectionDefaults: return 3;
		case IMAdminPreferencesSectionPlayback: return 3;
		case IMAdminPreferencesSectionPurchase: return 1;
		default: return 0;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case IMAdminPreferencesSectionEmail: return _(@"Email notifications");
		case IMAdminPreferencesSectionFeatures: return _(@"Library features");
		case IMAdminPreferencesSectionSidebar: return _(@"Web sidebar");
		case IMAdminPreferencesSectionDefaults: return _(@"Defaults");
		case IMAdminPreferencesSectionPlayback: return _(@"Playback and downloads");
		case IMAdminPreferencesSectionPurchase: return _(@"Purchase");
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == IMAdminPreferencesSectionEmail) return _(@"Email delivery also depends on the server SMTP configuration.");
	if (section == IMAdminPreferencesSectionPurchase) return self.preferences.hideBuyButtonUntil.length ? [NSString stringWithFormat:_(@"Buy button hidden until %@."), self.preferences.hideBuyButtonUntil] : nil;
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	IMAdminUserPreferences *p = self.preferences;
	if (!p) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.text = _(@"Loading…");
		return cell;
	}
	switch (indexPath.section) {
		case IMAdminPreferencesSectionEmail:
			switch (indexPath.row) {
				case 0: return [self switchCell:_(@"Email notifications") detail:_(@"Receive account and album email updates.") on:p.emailEnabled tag:IMAdminPreferenceToggleEmailEnabled enabled:YES];
				case 1: return [self switchCell:_(@"Album invitations") detail:nil on:p.emailAlbumInvite tag:IMAdminPreferenceToggleAlbumInvite enabled:p.emailEnabled];
				default: return [self switchCell:_(@"Album updates") detail:nil on:p.emailAlbumUpdate tag:IMAdminPreferenceToggleAlbumUpdate enabled:p.emailEnabled];
			}
		case IMAdminPreferencesSectionFeatures:
			switch (indexPath.row) {
				case 0: return [self switchCell:_(@"Memories") detail:_(@"Show on-this-day memories.") on:p.memoriesEnabled tag:IMAdminPreferenceToggleMemories enabled:YES];
				case 1: return [self switchCell:_(@"People") detail:_(@"Enable face detection and people browsing.") on:p.peopleEnabled tag:IMAdminPreferenceTogglePeople enabled:YES];
				case 2: return [self switchCell:_(@"Shared links") detail:_(@"Allow shared links for this account.") on:p.sharedLinksEnabled tag:IMAdminPreferenceToggleSharedLinks enabled:YES];
				case 3: return [self switchCell:_(@"Tags") detail:_(@"Enable tag organization.") on:p.tagsEnabled tag:IMAdminPreferenceToggleTags enabled:YES];
				case 4: return [self switchCell:_(@"Ratings") detail:_(@"Enable star ratings.") on:p.ratingsEnabled tag:IMAdminPreferenceToggleRatings enabled:YES];
				default: return [self switchCell:_(@"Folders") detail:_(@"Enable folder browsing.") on:p.foldersEnabled tag:IMAdminPreferenceToggleFolders enabled:YES];
			}
		case IMAdminPreferencesSectionSidebar:
			switch (indexPath.row) {
				case 0: return [self switchCell:_(@"People in sidebar") detail:nil on:p.peopleSidebarWeb tag:IMAdminPreferenceTogglePeopleSidebar enabled:p.peopleEnabled];
				case 1: return [self switchCell:_(@"Shared links in sidebar") detail:nil on:p.sharedLinksSidebarWeb tag:IMAdminPreferenceToggleSharedLinksSidebar enabled:p.sharedLinksEnabled];
				case 2: return [self switchCell:_(@"Tags in sidebar") detail:nil on:p.tagsSidebarWeb tag:IMAdminPreferenceToggleTagsSidebar enabled:p.tagsEnabled];
				case 3: return [self switchCell:_(@"Folders in sidebar") detail:nil on:p.foldersSidebarWeb tag:IMAdminPreferenceToggleFoldersSidebar enabled:p.foldersEnabled];
				default: return [self switchCell:_(@"Recently added in sidebar") detail:nil on:p.recentlyAddedSidebarWeb tag:IMAdminPreferenceToggleRecentlyAddedSidebar enabled:YES];
			}
		case IMAdminPreferencesSectionDefaults:
			if (indexPath.row == 0) return [self valueCell:_(@"Album photo order") detail:[p.defaultAlbumAssetOrder isEqualToString:@"asc"] ? _(@"Oldest first") : _(@"Newest first")];
			if (indexPath.row == 1) return [self valueCell:_(@"Memory duration") detail:[NSString stringWithFormat:_(@"%ld seconds"), (long)p.memoriesDuration]];
			return [self valueCell:_(@"People face threshold") detail:p.peopleMinimumFaces > 0 ? [NSString stringWithFormat:_(@"%ld faces"), (long)p.peopleMinimumFaces] : _(@"Server default")];
		case IMAdminPreferencesSectionPlayback:
			if (indexPath.row == 0) return [self switchCell:_(@"Google Cast") detail:_(@"Allow this account to cast to compatible devices.") on:p.gCastEnabled tag:IMAdminPreferenceToggleCast enabled:YES];
			if (indexPath.row == 1) return [self switchCell:_(@"Embedded videos") detail:_(@"Include embedded videos in downloads.") on:p.includeEmbeddedVideos tag:IMAdminPreferenceToggleEmbeddedVideos enabled:YES];
			return [self valueCell:_(@"Download archive size") detail:[NSString stringWithFormat:_(@"%ld bytes"), (long)p.archiveSize]];
		case IMAdminPreferencesSectionPurchase:
			return [self switchCell:_(@"Support badge") detail:_(@"Show the Immich support badge.") on:p.showSupportBadge tag:IMAdminPreferenceToggleSupportBadge enabled:YES];
		default: return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	}
}

- (void)toggleChanged:(UISwitch *)sender {
	if (!self.preferences) return;
	NSString *section = nil;
	NSString *key = nil;
	switch (sender.tag) {
		case IMAdminPreferenceToggleEmailEnabled: section = @"emailNotifications"; key = @"enabled"; break;
		case IMAdminPreferenceToggleAlbumInvite: section = @"emailNotifications"; key = @"albumInvite"; break;
		case IMAdminPreferenceToggleAlbumUpdate: section = @"emailNotifications"; key = @"albumUpdate"; break;
		case IMAdminPreferenceToggleMemories: section = @"memories"; key = @"enabled"; break;
		case IMAdminPreferenceTogglePeople: section = @"people"; key = @"enabled"; break;
		case IMAdminPreferenceToggleSharedLinks: section = @"sharedLinks"; key = @"enabled"; break;
		case IMAdminPreferenceToggleTags: section = @"tags"; key = @"enabled"; break;
		case IMAdminPreferenceToggleRatings: section = @"ratings"; key = @"enabled"; break;
		case IMAdminPreferenceToggleFolders: section = @"folders"; key = @"enabled"; break;
		case IMAdminPreferenceTogglePeopleSidebar: section = @"people"; key = @"sidebarWeb"; break;
		case IMAdminPreferenceToggleSharedLinksSidebar: section = @"sharedLinks"; key = @"sidebarWeb"; break;
		case IMAdminPreferenceToggleTagsSidebar: section = @"tags"; key = @"sidebarWeb"; break;
		case IMAdminPreferenceToggleFoldersSidebar: section = @"folders"; key = @"sidebarWeb"; break;
		case IMAdminPreferenceToggleRecentlyAddedSidebar: section = @"recentlyAdded"; key = @"sidebarWeb"; break;
		case IMAdminPreferenceToggleCast: section = @"cast"; key = @"gCastEnabled"; break;
		case IMAdminPreferenceToggleEmbeddedVideos: section = @"download"; key = @"includeEmbeddedVideos"; break;
		case IMAdminPreferenceToggleSupportBadge: section = @"purchase"; key = @"showSupportBadge"; break;
		default: return;
	}
	[self updateSection:section values:@{ key: @(sender.isOn) }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.preferences || self.loading) return;
	if (indexPath.section == IMAdminPreferencesSectionDefaults && indexPath.row == 0) {
		UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Album photo order") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		__weak typeof(self) weakSelf = self;
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Newest first") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf updateSection:@"albums" values:@{ @"defaultAssetOrder": @"desc" }]; }]];
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Oldest first") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf updateSection:@"albums" values:@{ @"defaultAssetOrder": @"asc" }]; }]];
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[self anchorSheet:sheet atIndexPath:indexPath];
		return;
	}
	if (indexPath.section == IMAdminPreferencesSectionDefaults && indexPath.row == 1) {
		UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Memory duration") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		__weak typeof(self) weakSelf = self;
		for (NSNumber *seconds in @[@3, @5, @10, @15]) {
			[sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:_(@"%ld seconds"), seconds.longValue] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf updateSection:@"memories" values:@{ @"duration": seconds }]; }]];
		}
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[self anchorSheet:sheet atIndexPath:indexPath];
		return;
	}
	if (indexPath.section == IMAdminPreferencesSectionDefaults && indexPath.row == 2) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"People face threshold") message:_(@"People with fewer detected faces are hidden from the list.") preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
			field.keyboardType = UIKeyboardTypeNumberPad;
			if (self.preferences.peopleMinimumFaces > 0) field.text = [NSString stringWithFormat:@"%ld", (long)self.preferences.peopleMinimumFaces];
			field.placeholder = _(@"Minimum faces");
		}];
		__weak typeof(self) weakSelf = self;
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
			NSInteger value = alert.textFields.firstObject.text.integerValue;
			if (value < 1 || value > 1000) {
				[weakSelf showError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: _(@"Enter a threshold between 1 and 1000.") }]];
				return;
			}
			[weakSelf updateSection:@"people" values:@{ @"minimumFaces": @(value) }];
		}]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	if (indexPath.section == IMAdminPreferencesSectionPlayback && indexPath.row == 2) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Download archive size") message:_(@"Set the maximum archive size in bytes.") preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
			field.keyboardType = UIKeyboardTypeNumberPad;
			field.text = [NSString stringWithFormat:@"%ld", (long)MAX(1, self.preferences.archiveSize)];
			field.placeholder = _(@"Bytes");
		}];
		__weak typeof(self) weakSelf = self;
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
			NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
			NSScanner *scanner = [NSScanner scannerWithString:text];
			scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@""];
			unsigned long long parsed = 0;
			BOOL valid = text.length > 0 && [scanner scanUnsignedLongLong:&parsed] && scanner.isAtEnd && parsed >= 1 && parsed <= 9007199254740991ULL;
			if (!valid) {
				[weakSelf showError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: _(@"Enter a positive archive size in bytes.") }]];
				return;
			}
			[weakSelf updateSection:@"download" values:@{ @"archiveSize": @(parsed) }];
		}]];
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (void)anchorSheet:(UIAlertController *)sheet atIndexPath:(NSIndexPath *)indexPath {
	if (sheet.popoverPresentationController) {
		UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
		sheet.popoverPresentationController.sourceView = cell ?: self.view;
		sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

@end
