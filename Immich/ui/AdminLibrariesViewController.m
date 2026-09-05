#import "AdminLibrariesViewController.h"
#import "IMLibraryApi.h"
#import "IMLibrary.h"
#import "IMSession.h"
#import "common.h"

@interface AdminLibrariesViewController ()
@property (nonatomic, copy) NSArray<IMLibrary *> *libraries;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation AdminLibrariesViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"External Libraries");
	self.libraries = @[];
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createTapped)];
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.tableView.backgroundView = self.statusLabel;
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading && !self.mutating) [self reload];
}

- (void)reload {
	if (self.loading || self.mutating) { [self.refresh endRefreshing]; return; }
	self.loading = YES;
	if (!self.libraries.count) self.statusLabel.text = _(@"Loading libraries…");
	__weak typeof(self) weakSelf = self;
	[IMLibraryApi allLibrariesWithCompletion:^(NSArray<IMLibrary *> *libraries, NSError *error) {
		AdminLibrariesViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		[self.refresh endRefreshing];
		if (error || !libraries) {
			if (!self.libraries.count) self.statusLabel.text = _(@"Couldn't load libraries. Tap to retry.");
			[self showError:error];
			return;
		}
		self.libraries = libraries;
		self.statusLabel.text = self.libraries.count ? nil : _(@"No external libraries configured.");
		[self.tableView reloadData];
	}];
}

- (NSString *)formattedBytes:(unsigned long long)bytes {
	NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
	formatter.countStyle = NSByteCountFormatterCountStyleFile;
	return [formatter stringFromByteCount:(long long)bytes];
}

- (NSArray<NSString *> *)linesFromText:(NSString *)text {
	NSMutableArray *lines = [NSMutableArray array];
	for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
		NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (trimmed.length) [lines addObject:trimmed];
	}
	return lines;
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"External Libraries")
	                                                                 message:error.localizedDescription ?: _(@"The server could not complete this request.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)createTapped {
	[self promptForLibrary:nil];
}

- (void)promptForLibrary:(IMLibrary *)library {
	BOOL editing = library != nil;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:editing ? _(@"Edit Library") : _(@"Create Library") message:_(@"Enter one import path per line. Exclusion patterns are optional.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Library name"); field.text = library.name ?: @""; }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Import paths"); field.text = [library.importPaths componentsJoinedByString:@"\n"]; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Exclusion patterns (optional)"); field.text = [library.exclusionPatterns componentsJoinedByString:@"\n"]; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:editing ? _(@"Save") : _(@"Create") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminLibrariesViewController *self = weakSelf;
		if (!self) return;
		NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		NSArray *paths = [self linesFromText:alert.textFields[1].text ?: @""];
		NSArray *exclusions = [self linesFromText:alert.textFields[2].text ?: @""];
		if (!name.length || (!editing && !paths.count)) {
			[self showMessage:_(@"Enter a name and at least one import path.") title:_(@"Invalid Library")];
			return;
		}
		self.mutating = YES;
		if (editing) {
			[IMLibraryApi updateLibraryId:library.libraryId name:name importPaths:paths exclusionPatterns:exclusions completion:^(IMLibrary *updated, NSError *error) {
				AdminLibrariesViewController *inner = weakSelf;
				if (!inner) return;
				inner.mutating = NO;
				if (error || !updated) [inner showError:error]; else [inner reload];
			}];
		} else {
			[IMLibraryApi createLibraryWithName:name ownerId:IMSession.shared.userId ?: @"" importPaths:paths exclusionPatterns:exclusions completion:^(IMLibrary *created, NSError *error) {
				AdminLibrariesViewController *inner = weakSelf;
				if (!inner) return;
				inner.mutating = NO;
				if (error || !created) [inner showError:error]; else [inner reload];
			}];
		}
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)libraryActions:(IMLibrary *)library atIndexPath:(NSIndexPath *)indexPath {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:library.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Scan now") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AdminLibrariesViewController *self = weakSelf; if (!self) return; self.mutating = YES;
		[IMLibraryApi scanLibraryId:library.libraryId completion:^(BOOL success, NSError *error) { AdminLibrariesViewController *inner = weakSelf; if (!inner) return; inner.mutating = NO; if (!success) [inner showError:error]; else [inner showMessage:_(@"The library scan was queued.") title:_(@"Scan queued")]; }];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Statistics") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[IMLibraryApi statisticsForLibraryId:library.libraryId completion:^(IMLibraryStats *stats, NSError *error) {
			AdminLibrariesViewController *self = weakSelf; if (!self) return;
			dispatch_async(dispatch_get_main_queue(), ^{ if (error || !stats) [self showError:error]; else [self showMessage:[NSString stringWithFormat:_(@"%ld total (%ld photos, %ld videos)\n%@"), (long)stats.total, (long)stats.photos, (long)stats.videos, [self formattedBytes:stats.usage]] title:_(@"Library Statistics")]; });
		}];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Validate paths") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[IMLibraryApi validateLibraryId:library.libraryId importPaths:library.importPaths completion:^(NSArray<IMLibraryValidation *> *results, NSError *error) {
			AdminLibrariesViewController *self = weakSelf; if (!self) return;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (error || !results) { [self showError:error]; return; }
				NSMutableArray *lines = [NSMutableArray array];
				for (IMLibraryValidation *result in results) [lines addObject:[NSString stringWithFormat:@"%@ %@%@", result.valid ? @"✓" : @"✗", result.importPath, result.message.length ? [NSString stringWithFormat:@" — %@", result.message] : @""]];
				[self showMessage:lines.count ? [lines componentsJoinedByString:@"\n"] : _(@"No paths were returned by the server.") title:_(@"Path Validation")];
			});
		}];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Edit") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf promptForLibrary:library]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [weakSelf deleteLibrary:library]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
	if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = cell ?: self.view; sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds; }
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)deleteLibrary:(IMLibrary *)library {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete library?") message:_(@"Imported assets already in Immich will remain in your account.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		AdminLibrariesViewController *self = weakSelf; if (!self) return; self.mutating = YES;
		[IMLibraryApi deleteLibraryId:library.libraryId completion:^(BOOL success, NSError *error) { AdminLibrariesViewController *inner = weakSelf; if (!inner) return; inner.mutating = NO; if (!success) [inner showError:error]; else [inner reload]; }];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.libraries.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"library"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"library"];
	IMLibrary *library = self.libraries[indexPath.row];
	cell.textLabel.text = library.name.length ? library.name : _(@"Unnamed library");
	NSString *paths = library.importPaths.count ? [library.importPaths componentsJoinedByString:@", "] : _(@"No import paths");
	cell.detailTextLabel.text = [NSString stringWithFormat:_(@"%ld assets · %@\n%@"), (long)library.assetCount, paths, library.refreshedAt.length ? [NSString stringWithFormat:_(@"Refreshed %@"), library.refreshedAt] : _(@"Not scanned yet")];
	cell.detailTextLabel.numberOfLines = 2;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row < (NSInteger)self.libraries.count && !self.loading && !self.mutating) [self libraryActions:self.libraries[indexPath.row] atIndexPath:indexPath];
}

@end
