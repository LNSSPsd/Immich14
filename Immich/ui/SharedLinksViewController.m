#import "SharedLinksViewController.h"
#import "IMSharedLinkApi.h"
#import "SharedLinkEditorViewController.h"
#import "SharedLinkAssetsViewController.h"
#import "common.h"

@interface SharedLinksViewController ()
@property (nonatomic, copy) NSArray<IMSharedLink *> *links;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation SharedLinksViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Shared Links");
	self.links = @[];
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
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
	if (self.loading || self.mutating) {
		[self.refreshControl endRefreshing];
		return;
	}
	self.loading = YES;
	if (!self.links.count) self.statusLabel.text = _(@"Loading links…");
	__weak typeof(self) weakSelf = self;
	[IMSharedLinkApi allLinksWithCompletion:^(NSArray<IMSharedLink *> *links, NSError *error) {
		SharedLinksViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		[self.refreshControl endRefreshing];
		if (error) {
			if (!self.links.count) self.statusLabel.text = _(@"Couldn't load links. Tap to retry.");
			else [self showError:error];
			return;
		}
		self.links = links ?: @[];
		self.statusLabel.text = self.links.count ? nil : _(@"No shared links. Create one from a photo or album.");
		[self.tableView reloadData];
	}];
}

- (NSString *)displayTitleForLink:(IMSharedLink *)link {
	if ([link.type isEqualToString:@"ALBUM"]) return link.title.length ? link.title : _(@"Public album");
	return link.linkDescription.length ? link.linkDescription : _(@"Individual share");
}

- (NSString *)capabilitySummaryForLink:(IMSharedLink *)link {
	NSMutableArray<NSString *> *capabilities = [NSMutableArray array];
	if (link.allowUpload) [capabilities addObject:_(@"Uploads")];
	if (link.allowDownload) [capabilities addObject:_(@"Downloads")];
	if (link.showMetadata) [capabilities addObject:_(@"Metadata")];
	if (link.password.length) [capabilities addObject:_(@"Password")];
	if ([link.type isEqualToString:@"INDIVIDUAL"]) [capabilities addObject:_(@"Individual photos")];
	return capabilities.count ? [capabilities componentsJoinedByString:@" · "] : _(@"No public permissions");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.links.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"link"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"link"];
	IMSharedLink *link = self.links[indexPath.row];
	cell.textLabel.text = [self displayTitleForLink:link];
	NSString *expiry = link.expiresAt.length ? [NSString stringWithFormat:_(@"Expires %@"), link.expiresAt] : _(@"Never expires");
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", expiry, [self capabilitySummaryForLink:link]];
	cell.detailTextLabel.numberOfLines = 2;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.loading || self.mutating || indexPath.row >= (NSInteger)self.links.count) return;
	IMSharedLink *link = self.links[indexPath.row];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[self displayTitleForLink:link]
	                                                                 message:[self capabilitySummaryForLink:link]
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Share") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		SharedLinksViewController *self = weakSelf;
		if (!self) return;
		NSURL *url = [IMSharedLinkApi publicURLForLink:link];
		if (!url) {
			[self showError:nil];
			return;
		}
		UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
		share.popoverPresentationController.sourceView = self.view;
		share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
		[self presentViewController:share animated:YES completion:nil];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Edit") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf editLink:link];
	}]];
	if ([link.type isEqualToString:@"INDIVIDUAL"]) {
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Manage Photos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			SharedLinksViewController *self = weakSelf;
			if (!self) return;
			[self.navigationController pushViewController:[SharedLinkAssetsViewController managerForLink:link] animated:YES];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Revoke") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf revokeLink:link];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)editLink:(IMSharedLink *)link {
	__weak typeof(self) weakSelf = self;
	__weak SharedLinkEditorViewController *weakEditor = nil;
	SharedLinkEditorViewController *editor = [SharedLinkEditorViewController editorForLink:link
	                                                                                saveHandler:^(NSDictionary<NSString *,id> *fields) {
		SharedLinksViewController *self = weakSelf;
		if (!self) return;
		self.mutating = YES;
		[IMSharedLinkApi updateLinkId:link.linkId fields:fields linkCompletion:^(IMSharedLink *updated, NSError *error) {
			SharedLinksViewController *inner = weakSelf;
			if (!inner) return;
			inner.mutating = NO;
			if (!updated || error) {
				[weakEditor setSaving:NO];
				[inner showError:error];
				return;
			}
			[inner.navigationController popViewControllerAnimated:YES];
			[inner reload];
		}];
	}];
	weakEditor = editor;
	[self.navigationController pushViewController:editor animated:YES];
}

- (void)revokeLink:(IMSharedLink *)link {
	if (self.mutating) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Revoke Shared Link?")
	                                                                 message:_(@"Anyone using this link will lose access.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Revoke") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		SharedLinksViewController *self = weakSelf;
		if (!self || self.mutating) return;
		self.mutating = YES;
		[IMSharedLinkApi removeLinkId:link.linkId completion:^(BOOL success, NSError *error) {
			SharedLinksViewController *inner = weakSelf;
			if (!inner) return;
			inner.mutating = NO;
			if (!success) [inner showError:error];
			else [inner reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return !self.loading && !self.mutating;
}

- (void)tableView:(UITableView *)tableView
 commitEditingStyle:(UITableViewCellEditingStyle)style
 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (style == UITableViewCellEditingStyleDelete && !self.loading && !self.mutating && indexPath.row < (NSInteger)self.links.count) {
		[self revokeLink:self.links[indexPath.row]];
	}
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Shared Links")
	                                                                 message:error.localizedDescription ?: _(@"The server could not complete this request.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
