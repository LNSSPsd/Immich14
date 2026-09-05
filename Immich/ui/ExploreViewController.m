#import "ExploreViewController.h"
#import "IMSearchApi.h"
#import "AssetViewController.h"
#import "common.h"

@interface ExploreViewController ()
@property (nonatomic, copy) NSArray<IMSearchExploreGroup *> *groups;
@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@end

@implementation ExploreViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Explore");
	self.groups = @[];
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 58.0;
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.tableView.backgroundView = self.statusLabel;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
	                                                                                          target:self
	                                                                                          action:@selector(reload)];
	[self reload];
}

- (void)dealloc {
	[self.task cancel];
}

- (void)reload {
	if (self.loading) {
		[self.refreshControl endRefreshing];
		return;
	}
	self.loading = YES;
	self.statusLabel.text = self.groups.count ? nil : _(@"Loading explore data…");
	self.navigationItem.rightBarButtonItem.enabled = NO;
	[self.tableView reloadData];
	__weak typeof(self) weakSelf = self;
	self.task = [IMSearchApi exploreDataWithCompletion:^(NSArray<IMSearchExploreGroup *> *_Nullable groups, NSError *_Nullable error) {
		ExploreViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loading = NO;
		strongSelf.task = nil;
		strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
		[strongSelf.refreshControl endRefreshing];
		if (error || !groups) {
			if (!strongSelf.groups.count) strongSelf.statusLabel.text = _(@"Couldn't load Explore. Tap to retry.");
			else [strongSelf showError:error];
			return;
		}
		strongSelf.groups = groups;
		strongSelf.statusLabel.text = groups.count ? nil : _(@"No explore categories are available.");
		[strongSelf.tableView reloadData];
	}];
}

- (NSString *)displayNameForField:(NSString *)field {
	if ([field isEqualToString:@"people"]) return _(@"People");
	if ([field isEqualToString:@"places"]) return _(@"Places");
	if ([field isEqualToString:@"tags"]) return _(@"Tags");
	if ([field isEqualToString:@"years"]) return _(@"Years");
	return field.length ? field : _(@"Explore");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.groups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section < (NSInteger)self.groups.count ? self.groups[(NSUInteger)section].items.count : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section < (NSInteger)self.groups.count ? [self displayNameForField:self.groups[(NSUInteger)section].fieldName] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *const identifier = @"explore-item";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	IMSearchExploreGroup *group = self.groups[(NSUInteger)indexPath.section];
	IMSearchExploreItem *item = group.items[(NSUInteger)indexPath.row];
	cell.textLabel.text = item.value;
	cell.detailTextLabel.text = _(@"Open representative photo");
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.accessibilityLabel = item.value;
	cell.accessibilityValue = cell.detailTextLabel.text;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section >= (NSInteger)self.groups.count) return;
	IMSearchExploreGroup *group = self.groups[(NSUInteger)indexPath.section];
	if (indexPath.row >= (NSInteger)group.items.count) return;
	IMSearchExploreItem *item = group.items[(NSUInteger)indexPath.row];
	AssetViewController *viewer = [AssetViewController viewerWithAssets:@[ item.asset ] startIndex:0];
	[self presentViewController:viewer animated:YES completion:nil];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Explore")
	                                                                 message:error.localizedDescription ?: _(@"The server could not complete this request.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

@end
