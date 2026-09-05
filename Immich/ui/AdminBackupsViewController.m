#import "AdminBackupsViewController.h"
#import "IMDatabaseBackupApi.h"
#import "IMDatabaseBackup.h"
#import "IMApiClient.h"
#import "IMQueueApi.h"
#import "common.h"

@interface AdminBackupsViewController ()
@property (nonatomic, copy) NSArray<IMDatabaseBackup *> *backups;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic) NSUInteger generation;
@end

@implementation AdminBackupsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Database Backups");
	self.backups = @[];
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
	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithTitle:_(@"Backup now") style:UIBarButtonItemStylePlain target:self action:@selector(backupNowTapped)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(uploadTapped)]
	];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading && !self.mutating) [self reload];
}

- (void)dealloc {
	self.generation += 1;
}

- (void)reload {
	if (self.loading || self.mutating) {
		[self.refresh endRefreshing];
		return;
	}
	self.loading = YES;
	NSUInteger generation = ++self.generation;
	if (!self.backups.count) self.statusLabel.text = _(@"Loading database backups…");
	__weak typeof(self) weakSelf = self;
	[IMDatabaseBackupApi allBackupsWithCompletion:^(NSArray<IMDatabaseBackup *> *backups, NSError *error) {
		AdminBackupsViewController *self = weakSelf;
		if (!self || generation != self.generation) return;
		self.loading = NO;
		[self.refresh endRefreshing];
		if (error || !backups) {
			if (!self.backups.count) self.statusLabel.text = _(@"Couldn't load backups. Tap to retry.");
			if (error) [self showError:error];
			return;
		}
		self.backups = backups;
		self.statusLabel.text = backups.count ? nil : _(@"No database backups found.");
		[self.tableView reloadData];
	}];
}

- (NSString *)formattedBytes:(unsigned long long)bytes {
	NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
	formatter.countStyle = NSByteCountFormatterCountStyleFile;
	return [formatter stringFromByteCount:(long long)bytes];
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not complete this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Database Backups") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (void)backupNowTapped {
	if (self.mutating) return;
	self.mutating = YES;
	__weak typeof(self) weakSelf = self;
	[IMQueueApi runManualJobNamed:@"backup-database" completion:^(BOOL success, NSError *error) {
		AdminBackupsViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		if (!success || error) {
			[self showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not queue a database backup.")}]];
			return;
		}
		[self showMessage:_(@"A database backup was queued. Pull to refresh when the job finishes.") title:_(@"Backup queued")];
		[self reload];
	}];
}

- (void)uploadTapped {
	if (self.mutating) return;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data", @"public.item"] inMode:UIDocumentPickerModeImport];
	picker.delegate = self;
	picker.allowsMultipleSelection = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	NSURL *url = urls.firstObject;
	if (!url) return;
	BOOL scoped = [url startAccessingSecurityScopedResource];
	NSString *filename = url.lastPathComponent ?: @"backup.sql";
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
		if (scoped) [url stopAccessingSecurityScopedResource];
		dispatch_async(dispatch_get_main_queue(), ^{
			AdminBackupsViewController *self = weakSelf;
			if (!self) return;
			if (!data.length) {
				[self showMessage:_(@"The selected file could not be read or is empty.") title:_(@"Upload failed")];
				return;
			}
			[self uploadData:data filename:filename];
		});
	});
}

- (void)uploadData:(NSData *)data filename:(NSString *)filename {
	if (self.mutating) return;
	self.mutating = YES;
	__weak typeof(self) weakSelf = self;
	[IMDatabaseBackupApi uploadBackupData:data filename:filename completion:^(BOOL success, NSError *error) {
		AdminBackupsViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		if (!success || error) {
			[self showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"The server rejected this backup file.")}]];
			return;
		}
		[self showMessage:_(@"The backup was uploaded successfully.") title:_(@"Upload complete")];
		[self reload];
	}];
}

- (void)shareBackup:(IMDatabaseBackup *)backup {
	if (!backup.filename.length) return;
	self.mutating = YES;
	__weak typeof(self) weakSelf = self;
	[IMDatabaseBackupApi downloadBackup:backup.filename completion:^(NSData *data, NSError *error) {
		AdminBackupsViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		if (!data.length || error) {
			[self showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"The backup could not be downloaded.")}]];
			return;
		}
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"IMDatabaseBackups"];
			[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
			NSString *path = [directory stringByAppendingPathComponent:backup.filename.lastPathComponent];
			BOOL wrote = [data writeToFile:path options:NSDataWritingAtomic error:NULL];
			dispatch_async(dispatch_get_main_queue(), ^{
				AdminBackupsViewController *inner = weakSelf;
				if (!inner) return;
				if (!wrote) { [inner showError:nil]; return; }
				UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
				share.popoverPresentationController.barButtonItem = inner.navigationItem.rightBarButtonItems.firstObject;
				[inner presentViewController:share animated:YES completion:nil];
			});
		});
	}];
}

- (void)restoreTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Prepare database restore?")
	                                                                 message:_(@"This puts the Immich server into maintenance mode. Continue only when you are ready to restore an uploaded backup from the server's restore page.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Continue") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		AdminBackupsViewController *self = weakSelf;
		if (!self || self.mutating) return;
		self.mutating = YES;
		[IMDatabaseBackupApi startRestoreFlowWithCompletion:^(BOOL success, NSError *error) {
			AdminBackupsViewController *inner = weakSelf;
			if (!inner) return;
			inner.mutating = NO;
			if (!success || error) { [inner showError:error]; return; }
			[inner showMessage:_(@"The restore flow has started. Follow the server's maintenance instructions to finish restoring the database.") title:_(@"Restore started")];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)actionsForBackup:(IMDatabaseBackup *)backup atIndexPath:(NSIndexPath *)indexPath {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:backup.filename message:[NSString stringWithFormat:_(@"%@ · %@"), [self formattedBytes:backup.filesize], backup.timezone.length ? backup.timezone : _(@"server time")] preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Download / Share") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf shareBackup:backup]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Prepare restore") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf restoreTapped]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [weakSelf confirmDelete:backup]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)confirmDelete:(IMDatabaseBackup *)backup {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete backup?") message:backup.filename preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		AdminBackupsViewController *self = weakSelf;
		if (!self || self.mutating) return;
		self.mutating = YES;
		[IMDatabaseBackupApi deleteBackups:@[backup.filename] completion:^(BOOL success, NSError *error) {
			AdminBackupsViewController *inner = weakSelf;
			if (!inner) return;
			inner.mutating = NO;
			if (!success || error) [inner showError:error]; else [inner reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.backups.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.backups.count ? [NSString stringWithFormat:_(@"%ld backups"), (long)self.backups.count] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"database-backup"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"database-backup"];
	IMDatabaseBackup *backup = self.backups[indexPath.row];
	cell.textLabel.text = backup.filename.length ? backup.filename : _(@"Unnamed backup");
	NSString *timezone = backup.timezone.length ? backup.timezone : _(@"server time");
	cell.detailTextLabel.text = [NSString stringWithFormat:_(@"%@ · %@"), [self formattedBytes:backup.filesize], timezone];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.accessibilityLabel = cell.textLabel.text;
	cell.accessibilityValue = cell.detailTextLabel.text;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row < (NSInteger)self.backups.count && !self.loading && !self.mutating) [self actionsForBackup:self.backups[indexPath.row] atIndexPath:indexPath];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.row < (NSInteger)self.backups.count) [self confirmDelete:self.backups[indexPath.row]];
}

@end
