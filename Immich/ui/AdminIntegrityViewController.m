#import "AdminIntegrityViewController.h"
#import "IMIntegrityApi.h"
#import "common.h"

static const NSInteger IMIntegritySummarySection = 0;
static const NSInteger IMIntegrityPageSize = 100;

@interface AdminIntegrityViewController ()
@property (nonatomic, strong, nullable) IMIntegrityReportSummary *summary;
@property (nonatomic, copy) NSArray<IMIntegrityReportItem *> *items;
@property (nonatomic, copy) NSArray<NSString *> *reportTypes;
@property (nonatomic, copy) NSString *selectedType;
@property (nonatomic, copy, nullable) NSString *nextCursor;
@property (nonatomic, strong) UISegmentedControl *typeControl;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong, nullable) NSError *summaryError;
@property (nonatomic, strong, nullable) NSError *reportError;
@property (nonatomic, strong, nullable) NSURLSessionTask *summaryTask;
@property (nonatomic, strong, nullable) NSURLSessionTask *reportTask;
@property (nonatomic, strong, nullable) NSURLSessionTask *csvTask;
@property (nonatomic, strong) UIBarButtonItem *csvButton;
@property (nonatomic, strong) NSMutableSet<NSString *> *deletingReportIDs;
@property (nonatomic) BOOL loadingSummary;
@property (nonatomic) BOOL loadingReports;
@property (nonatomic) NSUInteger summaryGeneration;
@property (nonatomic) NSUInteger reportGeneration;
@end

@implementation AdminIntegrityViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Integrity Reports");
	self.items = @[];
	self.reportTypes = IMIntegrityReportTypes();
	self.selectedType = self.reportTypes.firstObject ?: IMIntegrityReportTypeUntrackedFile;
	self.deletingReportIDs = [NSMutableSet set];
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 56.0;
	self.tableView.allowsSelectionDuringEditing = NO;
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.tableView.backgroundView = self.statusLabel;

	NSArray<NSString *> *segmentTitles = @[ _(@"Untracked"), _(@"Missing"), _(@"Checksum") ];
	self.typeControl = [[UISegmentedControl alloc] initWithItems:segmentTitles];
	self.typeControl.selectedSegmentIndex = 0;
	[self.typeControl addTarget:self action:@selector(typeChanged:) forControlEvents:UIControlEventValueChanged];
	self.typeControl.accessibilityLabel = _(@"Integrity report type");
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 56.0)];
	header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.typeControl.frame = CGRectInset(header.bounds, 16.0, 8.0);
	self.typeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
	[header addSubview:self.typeControl];
	self.tableView.tableHeaderView = header;

	UIBarButtonItem *refreshButton =
	    [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                   target:self
                                                   action:@selector(reload)];
	self.csvButton = [[UIBarButtonItem alloc] initWithTitle:_(@"CSV")
                                                       style:UIBarButtonItemStylePlain
                                                      target:self
                                                      action:@selector(exportCSV)];
	self.navigationItem.rightBarButtonItems = @[ refreshButton, self.csvButton ];
	[self reload];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	UIView *header = self.tableView.tableHeaderView;
	if (!header) {
		return;
	}
	CGFloat width = CGRectGetWidth(self.tableView.bounds);
	if (fabs(CGRectGetWidth(header.frame) - width) > 0.5) {
		header.frame = CGRectMake(0, 0, width, 56.0);
		self.typeControl.frame = CGRectInset(header.bounds, 16.0, 8.0);
		self.tableView.tableHeaderView = header;
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!self.summary && !self.loadingSummary && !self.loadingReports) {
		[self reload];
	}
}

- (void)dealloc {
	self.summaryGeneration += 1;
	self.reportGeneration += 1;
	[self.summaryTask cancel];
	[self.reportTask cancel];
	[self.csvTask cancel];
}

- (void)showError:(NSError *_Nullable)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not complete this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Integrity Reports")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) {
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (void)exportCSV {
	if (self.csvTask || self.selectedType.length == 0) {
		return;
	}
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"IMIntegrity"];
	if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
	                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:NULL]) {
		[self showError:nil];
		return;
	}
	NSString *filename = [NSString stringWithFormat:@"integrity-%@-%@.csv", self.selectedType, [NSUUID UUID].UUIDString];
	NSURL *destinationURL = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:filename]];
	self.csvButton.enabled = NO;
	NSString *type = [self.selectedType copy];
	__weak typeof(self) weakSelf = self;
	self.csvTask = [IMIntegrityApi reportCSVForType:type
	                                   destinationURL:destinationURL
	                                        completion:^(NSURL *fileURL, NSError *error) {
		AdminIntegrityViewController *strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.csvTask = nil;
		strongSelf.csvButton.enabled = YES;
		if (error || !fileURL) {
			[strongSelf showError:error];
			return;
		}
		UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ]
		                                                                    applicationActivities:nil];
		if (share.popoverPresentationController) {
			share.popoverPresentationController.barButtonItem = strongSelf.csvButton;
		}
		[strongSelf presentViewController:share animated:YES completion:nil];
	}];
}

- (NSString *)displayNameForType:(NSString *)type {
	if ([type isEqualToString:IMIntegrityReportTypeUntrackedFile]) {
		return _(@"Untracked files");
	}
	if ([type isEqualToString:IMIntegrityReportTypeMissingFile]) {
		return _(@"Missing files");
	}
	if ([type isEqualToString:IMIntegrityReportTypeChecksumMismatch]) {
		return _(@"Checksum mismatches");
	}
	return type.length ? type : _(@"Integrity findings");
}

- (NSInteger)countForSummaryType:(NSString *)type {
	if ([type isEqualToString:IMIntegrityReportTypeUntrackedFile]) {
		return self.summary.untrackedFileCount;
	}
	if ([type isEqualToString:IMIntegrityReportTypeMissingFile]) {
		return self.summary.missingFileCount;
	}
	if ([type isEqualToString:IMIntegrityReportTypeChecksumMismatch]) {
		return self.summary.checksumMismatchCount;
	}
	return 0;
}

- (BOOL)summaryIsEmpty {
	return self.summary && self.summary.untrackedFileCount == 0 && self.summary.missingFileCount == 0 &&
	       self.summary.checksumMismatchCount == 0;
}

- (void)updateStatusLabel {
	NSString *status = nil;
	if (self.loadingSummary || (self.loadingReports && self.items.count == 0)) {
		status = _(@"Loading integrity reports…");
	} else if (self.summaryError && !self.summary && self.items.count == 0) {
		status = _(@"Couldn't load integrity reports. Tap to retry.");
	} else if (self.reportError && self.items.count == 0) {
		status = [NSString stringWithFormat:_(@"Couldn't load %@. Tap to retry."), [self displayNameForType:self.selectedType]];
	} else if ([self summaryIsEmpty] && self.items.count == 0) {
		status = _(@"No integrity issues found.");
	} else if (!self.reportError && self.items.count == 0 && self.summary) {
		status = [NSString stringWithFormat:_(@"No %@ found."), [self displayNameForType:self.selectedType]];
	}
	self.statusLabel.text = status;
	self.statusLabel.accessibilityLabel = status;
}

- (void)reload {
	if (self.loadingSummary || self.loadingReports) {
		[self.refreshControl endRefreshing];
		return;
	}
	[self.summaryTask cancel];
	[self.reportTask cancel];
	self.summary = nil;
	self.summaryError = nil;
	self.reportError = nil;
	self.items = @[];
	self.nextCursor = nil;
	[self.tableView reloadData];
	[self loadSummary];
	[self loadReportsReset:YES];
}

- (void)loadSummary {
	self.loadingSummary = YES;
	[self updateStatusLabel];
	[self.tableView reloadData];
	NSUInteger generation = ++self.summaryGeneration;
	__weak typeof(self) weakSelf = self;
	self.summaryTask = [IMIntegrityApi summaryWithCompletion:^(IMIntegrityReportSummary *summary, NSError *error) {
		AdminIntegrityViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.summaryGeneration) {
			return;
		}
		strongSelf.loadingSummary = NO;
		strongSelf.summaryTask = nil;
		strongSelf.summary = summary;
		strongSelf.summaryError = error;
		[strongSelf updateStatusLabel];
		[strongSelf.tableView reloadData];
		[strongSelf endRefreshIfIdle];
	}];
}

- (void)loadReportsReset:(BOOL)reset {
	[self.reportTask cancel];
	self.loadingReports = YES;
	self.reportError = nil;
	if (reset) {
		self.items = @[];
		self.nextCursor = nil;
	}
	[self updateStatusLabel];
	[self.tableView reloadData];
	NSUInteger generation = ++self.reportGeneration;
	NSString *type = [self.selectedType copy];
	__weak typeof(self) weakSelf = self;
	self.reportTask = [IMIntegrityApi reportForType:type
	                                         cursor:nil
	                                          limit:IMIntegrityPageSize
	                                     completion:^(IMIntegrityReportPage *page, NSError *error) {
		AdminIntegrityViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.reportGeneration || ![strongSelf.selectedType isEqualToString:type]) {
			return;
		}
		strongSelf.loadingReports = NO;
		strongSelf.reportTask = nil;
		strongSelf.reportError = error;
		if (page) {
			strongSelf.items = page.items;
			strongSelf.nextCursor = page.nextCursor;
		}
		[strongSelf updateStatusLabel];
		[strongSelf.tableView reloadData];
		[strongSelf endRefreshIfIdle];
	}];
}

- (void)loadMore {
	if (self.loadingReports || self.nextCursor.length == 0) {
		return;
	}
	self.loadingReports = YES;
	self.reportError = nil;
	[self updateStatusLabel];
	[self.tableView reloadData];
	NSUInteger generation = ++self.reportGeneration;
	NSString *type = [self.selectedType copy];
	NSString *cursor = [self.nextCursor copy];
	__weak typeof(self) weakSelf = self;
	self.reportTask = [IMIntegrityApi reportForType:type
	                                         cursor:cursor
	                                          limit:IMIntegrityPageSize
	                                     completion:^(IMIntegrityReportPage *page, NSError *error) {
		AdminIntegrityViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.reportGeneration || ![strongSelf.selectedType isEqualToString:type]) {
			return;
		}
		strongSelf.loadingReports = NO;
		strongSelf.reportTask = nil;
		strongSelf.reportError = error;
		if (page) {
			NSMutableArray<IMIntegrityReportItem *> *merged = [strongSelf.items mutableCopy];
			NSMutableSet<NSString *> *knownIDs = [NSMutableSet setWithCapacity:merged.count];
			for (IMIntegrityReportItem *item in merged) {
				if (item.reportId.length) {
					[knownIDs addObject:item.reportId];
				}
			}
			for (IMIntegrityReportItem *item in page.items) {
				if (item.reportId.length == 0 || ![knownIDs containsObject:item.reportId]) {
					[merged addObject:item];
					if (item.reportId.length) {
						[knownIDs addObject:item.reportId];
					}
				}
			}
			strongSelf.items = [merged copy];
			strongSelf.nextCursor = page.nextCursor;
		}
		[strongSelf updateStatusLabel];
		[strongSelf.tableView reloadData];
		[strongSelf endRefreshIfIdle];
	}];
}

- (void)endRefreshIfIdle {
	if (!self.loadingSummary && !self.loadingReports) {
		[self.refreshControl endRefreshing];
	}
}

- (void)typeChanged:(UISegmentedControl *)sender {
	NSInteger index = sender.selectedSegmentIndex;
	if (index < 0 || index >= (NSInteger)self.reportTypes.count) {
		return;
	}
	NSString *type = self.reportTypes[(NSUInteger)index];
	if ([type isEqualToString:self.selectedType] && (self.loadingReports || self.items.count)) {
		return;
	}
	self.selectedType = type;
	[self loadReportsReset:YES];
	[self.tableView reloadData];
}

- (void)showItemDetails:(IMIntegrityReportItem *)item {
	NSString *path = item.path.length ? item.path : _(@"(unknown path)");
	NSMutableString *message = [NSMutableString stringWithFormat:_(@"Path: %@\nReport ID: %@"), path, item.reportId];
	if (item.assetId.length) {
		[message appendFormat:_(@"\nAsset ID: %@"), item.assetId];
	}
	if (item.fileAssetId.length) {
		[message appendFormat:_(@"\nFile asset ID: %@"), item.fileAssetId];
	}
	if (item.createdAt.length) {
		[message appendFormat:_(@"\nCreated: %@"), item.createdAt];
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:[self displayNameForType:item.type]
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete finding")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *action) {
		[weakSelf confirmDeleteReport:item];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Copy path") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[UIPasteboard generalPasteboard].string = path;
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteReport:(IMIntegrityReportItem *)item {
	if (!item.reportId.length || [self.deletingReportIDs containsObject:item.reportId]) {
		return;
	}
	NSString *path = item.path.length ? item.path : _(@"(unknown path)");
	UIAlertController *confirm = [UIAlertController alertControllerWithTitle:_(@"Delete integrity finding?")
	                                                                    message:[NSString stringWithFormat:_(@"%@\nThe server will apply the matching file or asset action."), path]
	                                                             preferredStyle:UIAlertControllerStyleAlert];
	[confirm addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[confirm addAction:[UIAlertAction actionWithTitle:_(@"Delete")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *action) {
		AdminIntegrityViewController *strongSelf = weakSelf;
		if (!strongSelf || [strongSelf.deletingReportIDs containsObject:item.reportId]) {
			return;
		}
		[strongSelf.deletingReportIDs addObject:item.reportId];
		[IMIntegrityApi deleteReportId:item.reportId completion:^(BOOL success, NSError *error) {
			AdminIntegrityViewController *inner = weakSelf;
			if (!inner) {
				return;
			}
			[inner.deletingReportIDs removeObject:item.reportId];
			if (!success || error) {
				[inner showError:error];
				return;
			}
			[inner reload];
		}];
	}]];
	[self presentViewController:confirm animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == IMIntegritySummarySection) {
		return self.summary ? (NSInteger)self.reportTypes.count : (self.summaryError ? 1 : 0);
	}
	return (NSInteger)self.items.count +
	       ((self.reportError || self.nextCursor.length || (self.loadingReports && self.items.count == 0)) ? 1 : 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == IMIntegritySummarySection) {
		return (self.summary || self.summaryError) ? _(@"Summary") : nil;
	}
	if (self.items.count || self.nextCursor.length || self.reportError || self.loadingReports) {
		return [NSString stringWithFormat:_(@"%@ findings"), [self displayNameForType:self.selectedType]];
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *summaryIdentifier = @"integrity-summary";
	static NSString *itemIdentifier = @"integrity-item";
	static NSString *moreIdentifier = @"integrity-more";
	if (indexPath.section == IMIntegritySummarySection) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:summaryIdentifier];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:summaryIdentifier];
		}
		if (!self.summary) {
			cell.textLabel.text = _(@"Summary unavailable");
			cell.detailTextLabel.text = _(@"Tap to retry");
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.accessibilityLabel = cell.textLabel.text;
			cell.accessibilityValue = cell.detailTextLabel.text;
			return cell;
		}
		NSString *type = self.reportTypes[(NSUInteger)indexPath.row];
		cell.textLabel.text = [self displayNameForType:type];
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)[self countForSummaryType:type]];
		cell.accessoryType = [type isEqualToString:self.selectedType] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
		cell.accessibilityLabel = cell.textLabel.text;
		cell.accessibilityValue = cell.detailTextLabel.text;
		return cell;
	}
	if (indexPath.row >= (NSInteger)self.items.count) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:moreIdentifier];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:moreIdentifier];
		}
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		BOOL initialLoading = self.loadingReports && self.items.count == 0 && !self.reportError;
		cell.textLabel.textColor = self.reportError ? UIColor.systemRedColor : (initialLoading ? UIColor.secondaryLabelColor : UIColor.linkColor);
		cell.textLabel.text = initialLoading
		    ? _(@"Loading findings…")
		    : self.reportError
		    ? (self.items.count ? _(@"Couldn't load more. Tap to retry.") : _(@"Couldn't load findings. Tap to retry."))
		    : (self.loadingReports ? _(@"Loading more…") : _(@"Load more…"));
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.accessibilityLabel = cell.textLabel.text;
		return cell;
	}
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:itemIdentifier];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:itemIdentifier];
	}
	IMIntegrityReportItem *item = self.items[(NSUInteger)indexPath.row];
	cell.textLabel.text = item.path.length ? item.path : _(@"(unknown path)");
	cell.textLabel.numberOfLines = 2;
	NSString *detail = item.assetId.length ? [NSString stringWithFormat:_(@"Asset %@"), item.assetId]
	                                      : item.fileAssetId.length ? [NSString stringWithFormat:_(@"File asset %@"), item.fileAssetId]
	                                                                : item.reportId;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 2;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.textLabel.textColor = UIColor.labelColor;
	cell.accessibilityLabel = cell.textLabel.text;
	cell.accessibilityValue = detail;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == IMIntegritySummarySection) {
		if (!self.summary) {
			[self reload];
		} else if (indexPath.row >= 0 && indexPath.row < (NSInteger)self.reportTypes.count) {
			self.typeControl.selectedSegmentIndex = indexPath.row;
			[self typeChanged:self.typeControl];
		}
		return;
	}
	if (indexPath.row >= (NSInteger)self.items.count) {
		if (self.loadingReports && !self.reportError) {
			return;
		}
		if (self.reportError) {
			if (self.items.count && self.nextCursor.length) {
				[self loadMore];
			} else {
				[self loadReportsReset:YES];
			}
		} else {
			[self loadMore];
		}
		return;
	}
	if (indexPath.row >= 0 && indexPath.row < (NSInteger)self.items.count) {
		[self showItemDetails:self.items[(NSUInteger)indexPath.row]];
	}
}

@end
