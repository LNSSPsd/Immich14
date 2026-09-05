#import "FoldersViewController.h"
#import "IMFolderApi.h"
#import "AssetGridViewController.h"
#import "common.h"

@interface FoldersViewController ()
@property (nonatomic, copy) NSArray<NSString *> *paths;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic) NSUInteger generation;
@end

@implementation FoldersViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Folders");
	self.paths = @[];
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
	[self reload];
}

- (void)dealloc {
	[self.task cancel];
	self.generation += 1;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading && self.paths.count) [self reload];
}

- (void)reload {
	if (self.loading) { [self.refresh endRefreshing]; return; }
	[self.task cancel];
	self.loading = YES;
	NSUInteger generation = ++self.generation;
	if (!self.paths.count) self.statusLabel.text = _(@"Loading folders…");
	__weak typeof(self) weakSelf = self;
	self.task = [IMFolderApi uniquePathsWithCompletion:^(NSArray<NSString *> *paths, NSError *error) {
		FoldersViewController *self = weakSelf;
		if (!self || generation != self.generation) return;
		self.task = nil;
		self.loading = NO;
		[self.refresh endRefreshing];
		if (error || !paths) {
			if (!self.paths.count) self.statusLabel.text = _(@"Couldn't load folders. Tap to retry.");
			if (error) [self showError:error];
			return;
		}
		self.paths = paths;
		self.statusLabel.text = paths.count ? nil : _(@"No folder-backed assets found.");
		[self.tableView reloadData];
	}];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Folders") message:error.localizedDescription ?: _(@"The server could not complete this request.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)displayNameForPath:(NSString *)path {
	NSString *trimmed = [path stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	while ([trimmed hasSuffix:@"/"] && trimmed.length > 1) trimmed = [trimmed substringToIndex:trimmed.length - 1];
	NSString *name = trimmed.lastPathComponent;
	return name.length ? name : trimmed;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.paths.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.paths.count ? [NSString stringWithFormat:_(@"%ld folders"), (long)self.paths.count] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"folder"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"folder"];
	NSString *path = self.paths[indexPath.row];
	cell.textLabel.text = [self displayNameForPath:path];
	cell.detailTextLabel.text = path;
	cell.detailTextLabel.numberOfLines = 2;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.accessibilityLabel = path;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.loading || indexPath.row >= (NSInteger)self.paths.count) return;
	NSString *path = self.paths[indexPath.row];
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	cell.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMFolderApi assetsForOriginalPath:path completion:^(NSArray<IMAsset *> *assets, NSError *error) {
		FoldersViewController *self = weakSelf;
		if (!self) return;
		cell.userInteractionEnabled = YES;
		if (error || !assets) { [self showError:error]; return; }
		AssetGridViewController *grid = [AssetGridViewController gridWithTitle:[self displayNameForPath:path] assets:assets];
		[self.navigationController pushViewController:grid animated:YES];
	}];
}

@end
