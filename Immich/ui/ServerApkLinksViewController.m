#import "ServerApkLinksViewController.h"
#import "IMServerApi.h"
#import "IMServerApkLinks.h"
#import "IMApiClient.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMServerApkRow) {
	IMServerApkRowUniversal = 0,
	IMServerApkRowARM64,
	IMServerApkRowARMv7,
	IMServerApkRowX8664,
	IMServerApkRowCount,
};

@interface ServerApkLinksViewController ()
@property (nonatomic, strong, nullable) IMServerApkLinks *links;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@end

@implementation ServerApkLinksViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Android Downloads");
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
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
	                                                                                          target:self
	                                                                                          action:@selector(reload)];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading) {
		[self reload];
	}
}

- (void)reload {
	if (self.loading) {
		[self.refresh endRefreshing];
		return;
	}
	self.loading = YES;
	if (!self.links) {
		self.statusLabel.text = _(@"Loading Android download links…");
	}
	__weak typeof(self) weakSelf = self;
	[IMServerApi serverApkLinksWithCompletion:^(IMServerApkLinks *links, NSError *error) {
		ServerApkLinksViewController *self = weakSelf;
		if (!self) {
			return;
		}
		self.loading = NO;
		[self.refresh endRefreshing];
		if (error || !links) {
			if (!self.links) {
				self.statusLabel.text = _(@"Couldn't load Android download links. Tap to retry.");
			} else if (error) {
				[self showError:error];
			}
			return;
		}
		self.links = links;
		self.statusLabel.text = nil;
		[self.tableView reloadData];
	}];
}

- (NSString *)titleForRow:(NSInteger)row {
	switch (row) {
		case IMServerApkRowUniversal: return _(@"Universal");
		case IMServerApkRowARM64: return _(@"ARM64 (recommended)");
		case IMServerApkRowARMv7: return _(@"ARMv7");
		case IMServerApkRowX8664: return _(@"x86_64");
		default: return @"";
	}
}

- (nullable NSString *)URLStringForRow:(NSInteger)row {
	switch (row) {
		case IMServerApkRowUniversal: return self.links.universal;
		case IMServerApkRowARM64: return self.links.arm64v8a;
		case IMServerApkRowARMv7: return self.links.armeabiv7a;
		case IMServerApkRowX8664: return self.links.x86_64;
		default: return nil;
	}
}

- (NSString *)detailForURLString:(NSString *)string {
	NSURL *url = [NSURL URLWithString:string];
	if (!url) {
		return _(@"Download APK");
	}
	NSString *host = url.host.length ? url.host : _(@"Download APK");
	NSString *filename = url.lastPathComponent;
	return filename.length ? [NSString stringWithFormat:@"%@ · %@", host, filename] : host;
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not return Android download links.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Android Downloads")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) {
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (void)showActionsForRow:(NSInteger)row {
	NSString *string = [self URLStringForRow:row];
	if (!string.length) {
		return;
	}
	NSURL *url = [NSURL URLWithString:string];
	if (!url) {
		[self showError:nil];
		return;
	}
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[self titleForRow:row]
	                                                                  message:string
	                                                           preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Open download") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		ServerApkLinksViewController *self = weakSelf;
		if (!self) {
			return;
		}
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
			if (!success) {
				dispatch_async(dispatch_get_main_queue(), ^{ [self showError:nil]; });
			}
		}];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Copy link") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[UIPasteboard generalPasteboard].string = string;
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.links ? IMServerApkRowCount : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"apk-link"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"apk-link"];
	}
	cell.textLabel.text = [self titleForRow:indexPath.row];
	cell.detailTextLabel.text = [self detailForURLString:[self URLStringForRow:indexPath.row] ?: @""];
	cell.detailTextLabel.numberOfLines = 2;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (!self.loading && indexPath.row < IMServerApkRowCount) {
		[self showActionsForRow:indexPath.row];
	}
}

@end
