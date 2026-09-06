#import "UserPreferencesViewController.h"
#import "IMUserPreferencesApi.h"
#import "IMUserPreferences.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMUserPreferencesSection) {
	IMUserPreferencesSectionEmail = 0,
	IMUserPreferencesSectionFeatures,
	IMUserPreferencesSectionDownloads,
	IMUserPreferencesSectionDefaults,
	IMUserPreferencesSectionWebSidebar,
	IMUserPreferencesSectionCount,
};

typedef NS_ENUM(NSInteger, IMUserPreferenceToggle) {
	IMUserPreferenceToggleEmailEnabled = 100,
	IMUserPreferenceToggleAlbumInvite,
	IMUserPreferenceToggleAlbumUpdate,
	IMUserPreferenceToggleCast,
	IMUserPreferenceToggleEmbeddedVideos,
	IMUserPreferenceToggleMemories,
	IMUserPreferenceTogglePeople,
	IMUserPreferenceToggleSharedLinks,
	IMUserPreferenceToggleTags,
	IMUserPreferenceToggleRatings,
	IMUserPreferenceToggleFolders,
	IMUserPreferenceTogglePeopleSidebar,
	IMUserPreferenceToggleSharedLinksSidebar,
	IMUserPreferenceToggleTagsSidebar,
	IMUserPreferenceToggleFoldersSidebar,
	IMUserPreferenceToggleRecentlyAddedSidebar,
};

@interface UserPreferencesViewController ()
@property (nonatomic, strong, nullable) IMUserPreferences *preferences;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic) BOOL loading;
@property (nonatomic) NSUInteger updateGeneration;
@end

@implementation UserPreferencesViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"User Preferences");
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
	if (self.loading) {
		[self.refreshControl endRefreshing];
		return;
	}
	self.loading = YES;
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMUserPreferencesApi preferencesWithCompletion:^(IMUserPreferences *preferences, NSError *error) {
		UserPreferencesViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		[self.spinner stopAnimating];
		[self.refreshControl endRefreshing];
		if (error || !preferences) {
			if (!self.preferences) [self showError:error];
			else [self showError:error];
			return;
		}
		self.preferences = preferences;
		[self.tableView reloadData];
	}];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Preferences")
	                                                                 message:error.localizedDescription ?: _(@"The server could not load your preferences.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (void)showUpdateError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn’t Save Preference")
	                                                                 message:error.localizedDescription ?: _(@"The server rejected this preference change.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)updateSection:(NSString *)section values:(NSDictionary<NSString *, id> *)values {
	NSUInteger generation = ++self.updateGeneration;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMUserPreferencesApi updateSection:section values:values completion:^(IMUserPreferences *preferences, NSError *error) {
		UserPreferencesViewController *self = weakSelf;
		if (!self || generation != self.updateGeneration) return;
		self.tableView.userInteractionEnabled = YES;
		if (error || !preferences) {
			[self.tableView reloadData];
			[self showUpdateError:error];
			return;
		}
		self.preferences = preferences;
		[self.tableView reloadData];
	}];
}

- (UISwitch *)switchForTitle:(NSString *)title
	                          on:(BOOL)on
	                          tag:(NSInteger)tag
	                      enabled:(BOOL)enabled {
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = on;
	toggle.tag = tag;
	toggle.enabled = enabled;
	[toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
	return toggle;
}

- (UITableViewCell *)switchCell:(NSString *)title
	                         detail:(NSString *)detail
	                             on:(BOOL)on
	                             tag:(NSInteger)tag
	                         enabled:(BOOL)enabled {
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
	return IMUserPreferencesSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case IMUserPreferencesSectionEmail: return 3;
		case IMUserPreferencesSectionFeatures: return 6;
		case IMUserPreferencesSectionDownloads: return 3;
		case IMUserPreferencesSectionDefaults: return 3;
		case IMUserPreferencesSectionWebSidebar: return 5;
		default: return 0;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case IMUserPreferencesSectionEmail: return _(@"Email notifications");
		case IMUserPreferencesSectionFeatures: return _(@"Library features");
		case IMUserPreferencesSectionDownloads: return _(@"Playback and downloads");
		case IMUserPreferencesSectionDefaults: return _(@"Defaults");
		case IMUserPreferencesSectionWebSidebar: return _(@"Web sidebar");
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == IMUserPreferencesSectionEmail) return _(@"Email delivery also depends on the server SMTP configuration.");
	if (section == IMUserPreferencesSectionDownloads) return _(@"Download archive limits and embedded-video behavior are controlled by the server.");
	if (section == IMUserPreferencesSectionWebSidebar) return _(@"These switches affect the Immich web sidebar for your account.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	IMUserPreferences *p = self.preferences;
	if (!p) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.text = _(@"Loading…");
		return cell;
	}
	switch (indexPath.section) {
		case IMUserPreferencesSectionEmail:
			switch (indexPath.row) {
				case 0: return [self switchCell:_(@"Email notifications") detail:_(@"Receive account and album email updates.") on:p.emailEnabled tag:IMUserPreferenceToggleEmailEnabled enabled:YES];
				case 1: return [self switchCell:_(@"Album invitations") detail:nil on:p.emailAlbumInvite tag:IMUserPreferenceToggleAlbumInvite enabled:p.emailEnabled];
				default: return [self switchCell:_(@"Album updates") detail:nil on:p.emailAlbumUpdate tag:IMUserPreferenceToggleAlbumUpdate enabled:p.emailEnabled];
			}
		case IMUserPreferencesSectionFeatures:
			switch (indexPath.row) {
				case 0: return [self switchCell:_(@"Memories") detail:_(@"Show on-this-day memories.") on:p.memoriesEnabled tag:IMUserPreferenceToggleMemories enabled:YES];
				case 1: return [self switchCell:_(@"People") detail:_(@"Enable face detection and people browsing.") on:p.peopleEnabled tag:IMUserPreferenceTogglePeople enabled:YES];
				case 2: return [self switchCell:_(@"Shared links") detail:_(@"Allow shared links for this account.") on:p.sharedLinksEnabled tag:IMUserPreferenceToggleSharedLinks enabled:YES];
				case 3: return [self switchCell:_(@"Tags") detail:_(@"Enable tag organization.") on:p.tagsEnabled tag:IMUserPreferenceToggleTags enabled:YES];
				case 4: return [self switchCell:_(@"Ratings") detail:_(@"Enable star ratings.") on:p.ratingsEnabled tag:IMUserPreferenceToggleRatings enabled:YES];
				default: return [self switchCell:_(@"Folders") detail:_(@"Enable folder browsing.") on:p.foldersEnabled tag:IMUserPreferenceToggleFolders enabled:YES];
			}
		case IMUserPreferencesSectionDownloads:
			switch (indexPath.row) {
				case 0: return [self switchCell:_(@"Google Cast") detail:_(@"Allow casting to compatible devices.") on:p.gCastEnabled tag:IMUserPreferenceToggleCast enabled:YES];
				case 1: return [self switchCell:_(@"Embedded videos") detail:_(@"Include embedded videos in downloads.") on:p.includeEmbeddedVideos tag:IMUserPreferenceToggleEmbeddedVideos enabled:YES];
				default: return [self valueCell:_(@"Download archive size") detail:p.archiveSize > 0 ? [NSString stringWithFormat:_(@"%ld bytes"), (long)p.archiveSize] : _(@"Server default")];
			}
		case IMUserPreferencesSectionDefaults:
			if (indexPath.row == 0) return [self valueCell:_(@"Album photo order") detail:[p.defaultAlbumAssetOrder isEqualToString:@"asc"] ? _(@"Oldest first") : _(@"Newest first")];
			if (indexPath.row == 1) return [self valueCell:_(@"Memory duration") detail:[NSString stringWithFormat:_(@"%ld seconds"), (long)p.memoriesDuration]];
			return [self valueCell:_(@"People face threshold") detail:[NSString stringWithFormat:_(@"%ld faces"), (long)p.peopleMinimumFaces]];
		case IMUserPreferencesSectionWebSidebar:
			switch (indexPath.row) {
				case 0: return [self switchCell:_(@"People in sidebar") detail:nil on:p.peopleSidebarWeb tag:IMUserPreferenceTogglePeopleSidebar enabled:p.peopleEnabled];
				case 1: return [self switchCell:_(@"Shared links in sidebar") detail:nil on:p.sharedLinksSidebarWeb tag:IMUserPreferenceToggleSharedLinksSidebar enabled:p.sharedLinksEnabled];
				case 2: return [self switchCell:_(@"Tags in sidebar") detail:nil on:p.tagsSidebarWeb tag:IMUserPreferenceToggleTagsSidebar enabled:p.tagsEnabled];
				case 3: return [self switchCell:_(@"Folders in sidebar") detail:nil on:p.foldersSidebarWeb tag:IMUserPreferenceToggleFoldersSidebar enabled:p.foldersEnabled];
				default: return [self switchCell:_(@"Recently added in sidebar") detail:nil on:p.recentlyAddedSidebarWeb tag:IMUserPreferenceToggleRecentlyAddedSidebar enabled:YES];
			}
		default: return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	}
}

- (void)toggleChanged:(UISwitch *)sender {
	if (!self.preferences) return;
	NSString *section = nil;
	NSString *key = nil;
	switch (sender.tag) {
		case IMUserPreferenceToggleEmailEnabled: section = @"emailNotifications"; key = @"enabled"; break;
		case IMUserPreferenceToggleAlbumInvite: section = @"emailNotifications"; key = @"albumInvite"; break;
		case IMUserPreferenceToggleAlbumUpdate: section = @"emailNotifications"; key = @"albumUpdate"; break;
		case IMUserPreferenceToggleCast: section = @"cast"; key = @"gCastEnabled"; break;
		case IMUserPreferenceToggleEmbeddedVideos: section = @"download"; key = @"includeEmbeddedVideos"; break;
		case IMUserPreferenceToggleMemories: section = @"memories"; key = @"enabled"; break;
		case IMUserPreferenceTogglePeople: section = @"people"; key = @"enabled"; break;
		case IMUserPreferenceToggleSharedLinks: section = @"sharedLinks"; key = @"enabled"; break;
		case IMUserPreferenceToggleTags: section = @"tags"; key = @"enabled"; break;
		case IMUserPreferenceToggleRatings: section = @"ratings"; key = @"enabled"; break;
		case IMUserPreferenceToggleFolders: section = @"folders"; key = @"enabled"; break;
		case IMUserPreferenceTogglePeopleSidebar: section = @"people"; key = @"sidebarWeb"; break;
		case IMUserPreferenceToggleSharedLinksSidebar: section = @"sharedLinks"; key = @"sidebarWeb"; break;
		case IMUserPreferenceToggleTagsSidebar: section = @"tags"; key = @"sidebarWeb"; break;
		case IMUserPreferenceToggleFoldersSidebar: section = @"folders"; key = @"sidebarWeb"; break;
		case IMUserPreferenceToggleRecentlyAddedSidebar: section = @"recentlyAdded"; key = @"sidebarWeb"; break;
		default: return;
	}
	[self updateSection:section values:@{key: @(sender.isOn)}];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.preferences || self.loading) return;
	if (indexPath.section == IMUserPreferencesSectionDefaults && indexPath.row == 0) {
		UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Album photo order") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		__weak typeof(self) weakSelf = self;
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Newest first") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf updateSection:@"albums" values:@{ @"defaultAssetOrder": @"desc" }]; }]];
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Oldest first") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf updateSection:@"albums" values:@{ @"defaultAssetOrder": @"asc" }]; }]];
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[self anchorSheet:sheet atIndexPath:indexPath];
		return;
	}
	if (indexPath.section == IMUserPreferencesSectionDefaults && indexPath.row == 1) {
		UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Memory duration") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		__weak typeof(self) weakSelf = self;
		for (NSNumber *seconds in @[@3, @5, @10, @15]) {
			[sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:_(@"%ld seconds"), seconds.longValue] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf updateSection:@"memories" values:@{ @"duration": seconds }]; }]];
		}
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[self anchorSheet:sheet atIndexPath:indexPath];
		return;
	}
	if (indexPath.section == IMUserPreferencesSectionDefaults && indexPath.row == 2) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"People face threshold") message:_(@"People with fewer detected faces are hidden from the list.") preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.keyboardType = UIKeyboardTypeNumberPad; field.text = [NSString stringWithFormat:@"%ld", (long)self.preferences.peopleMinimumFaces]; field.placeholder = _(@"Minimum faces"); }];
		__weak typeof(self) weakSelf = self;
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
			NSInteger value = alert.textFields.firstObject.text.integerValue;
			if (value < 1 || value > 1000) { [weakSelf showUpdateError:[NSError errorWithDomain:IMUserPreferencesApi.class.description code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Enter a threshold between 1 and 1000.")}]]; return; }
			[weakSelf updateSection:@"people" values:@{ @"minimumFaces": @(value) }];
		}]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	if (indexPath.section == IMUserPreferencesSectionDownloads && indexPath.row == 2) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Download archive size") message:_(@"Enter the maximum archive size in bytes. The value must be between 1 and 9007199254740991.") preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
			field.keyboardType = UIKeyboardTypeNumberPad;
			field.text = self.preferences.archiveSize > 0 ? [NSString stringWithFormat:@"%ld", (long)self.preferences.archiveSize] : @"";
			field.placeholder = _(@"Archive size in bytes");
		}];
		__weak typeof(self) weakSelf = self;
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
			unsigned long long value = text.longLongValue;
			if (!text.length || value < 1 || value > 9007199254740991ULL || ![text isEqualToString:[NSString stringWithFormat:@"%llu", value]]) {
				[weakSelf showUpdateError:[NSError errorWithDomain:IMUserPreferencesApi.class.description code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Enter a valid archive size between 1 and 9007199254740991 bytes.")}]];
				return;
			}
			[weakSelf updateSection:@"download" values:@{ @"archiveSize": @(value) }];
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
