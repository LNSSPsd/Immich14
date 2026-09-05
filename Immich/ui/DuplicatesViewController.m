#import "DuplicatesViewController.h"
#import "IMDuplicateApi.h"
#import "IMDuplicate.h"
#import "IMApiClient.h"
#import "IMThumbCache.h"
#import "IMPrefs.h"
#import "AssetViewController.h"
#import "common.h"

typedef void (^IMDuplicateGroupAction)(IMDuplicate *duplicate);
typedef void (^IMDuplicateAssetAction)(IMDuplicate *duplicate, NSInteger index);

@interface IMDuplicateGroupCell : UITableViewCell
- (void)configureWithDuplicate:(IMDuplicate *)duplicate
                dismissHandler:(nullable IMDuplicateGroupAction)dismissHandler
                  deleteHandler:(nullable IMDuplicateGroupAction)deleteHandler
                   assetHandler:(nullable IMDuplicateAssetAction)assetHandler;
@end

@interface IMDuplicateGroupCell ()
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIScrollView *assetScrollView;
@property (nonatomic, strong) UIStackView *assetStackView;
@property (nonatomic, strong) UIStackView *actionStackView;
@property (nonatomic, strong) UIButton *dismissButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) NSMutableArray<IMThumbCacheTask *> *thumbnailTasks;
@property (nonatomic, strong) IMDuplicate *duplicate;
@property (nonatomic, copy, nullable) IMDuplicateGroupAction dismissHandler;
@property (nonatomic, copy, nullable) IMDuplicateGroupAction deleteHandler;
@property (nonatomic, copy, nullable) IMDuplicateAssetAction assetHandler;
@end

@implementation IMDuplicateGroupCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) {
		return nil;
	}
	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.thumbnailTasks = [NSMutableArray array];
	self.contentView.layoutMargins = UIEdgeInsetsMake(12, 16, 12, 16);

	self.countLabel = [[UILabel alloc] init];
	self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.countLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	self.countLabel.numberOfLines = 1;

	self.hintLabel = [[UILabel alloc] init];
	self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.hintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	self.hintLabel.numberOfLines = 2;
	if (@available(iOS 13.0, *)) {
		self.hintLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.hintLabel.textColor = UIColor.grayColor;
	}

	self.assetScrollView = [[UIScrollView alloc] init];
	self.assetScrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.assetScrollView.alwaysBounceHorizontal = YES;
	self.assetScrollView.showsHorizontalScrollIndicator = YES;
	self.assetScrollView.directionalLockEnabled = YES;

	self.assetStackView = [[UIStackView alloc] init];
	self.assetStackView.translatesAutoresizingMaskIntoConstraints = NO;
	self.assetStackView.axis = UILayoutConstraintAxisHorizontal;
	self.assetStackView.alignment = UIStackViewAlignmentCenter;
	self.assetStackView.spacing = 8;
	[self.assetScrollView addSubview:self.assetStackView];

	self.actionStackView = [[UIStackView alloc] init];
	self.actionStackView.translatesAutoresizingMaskIntoConstraints = NO;
	self.actionStackView.axis = UILayoutConstraintAxisHorizontal;
	self.actionStackView.alignment = UIStackViewAlignmentFill;
	self.actionStackView.distribution = UIStackViewDistributionFillEqually;
	self.actionStackView.spacing = 8;

	self.dismissButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.dismissButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.dismissButton setTitle:_(@"Keep All") forState:UIControlStateNormal];
	[self.dismissButton addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchUpInside];
	self.dismissButton.accessibilityHint = _(@"Remove this group from duplicate results without deleting photos.");
	self.dismissButton.layer.cornerRadius = 8;
	self.dismissButton.layer.borderWidth = 1;
	if (@available(iOS 13.0, *)) {
		self.dismissButton.layer.borderColor = UIColor.separatorColor.CGColor;
	} else {
		self.dismissButton.layer.borderColor = UIColor.lightGrayColor.CGColor;
	}

	self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.deleteButton setTitle:_(@"Delete Extras") forState:UIControlStateNormal];
	[self.deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
	self.deleteButton.accessibilityHint = _(@"Keep the suggested copy and delete the other photos.");
	self.deleteButton.layer.cornerRadius = 8;
	self.deleteButton.layer.borderWidth = 1;
	if (@available(iOS 13.0, *)) {
		self.deleteButton.layer.borderColor = UIColor.systemRedColor.CGColor;
		self.deleteButton.tintColor = UIColor.systemRedColor;
	} else {
		self.deleteButton.layer.borderColor = UIColor.redColor.CGColor;
		self.deleteButton.tintColor = UIColor.redColor;
	}

	[self.actionStackView addArrangedSubview:self.dismissButton];
	[self.actionStackView addArrangedSubview:self.deleteButton];
	[self.contentView addSubview:self.countLabel];
	[self.contentView addSubview:self.hintLabel];
	[self.contentView addSubview:self.assetScrollView];
	[self.contentView addSubview:self.actionStackView];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[self.countLabel.topAnchor constraintEqualToAnchor:margins.topAnchor],
		[self.countLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[self.countLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[self.hintLabel.topAnchor constraintEqualToAnchor:self.countLabel.bottomAnchor constant:2],
		[self.hintLabel.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[self.hintLabel.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[self.assetScrollView.topAnchor constraintEqualToAnchor:self.hintLabel.bottomAnchor constant:8],
		[self.assetScrollView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[self.assetScrollView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[self.assetScrollView.heightAnchor constraintEqualToConstant:112],
		[self.assetStackView.topAnchor constraintEqualToAnchor:self.assetScrollView.contentLayoutGuide.topAnchor],
		[self.assetStackView.bottomAnchor constraintEqualToAnchor:self.assetScrollView.contentLayoutGuide.bottomAnchor],
		[self.assetStackView.leadingAnchor constraintEqualToAnchor:self.assetScrollView.contentLayoutGuide.leadingAnchor],
		[self.assetStackView.trailingAnchor constraintEqualToAnchor:self.assetScrollView.contentLayoutGuide.trailingAnchor],
		[self.assetStackView.heightAnchor constraintEqualToAnchor:self.assetScrollView.frameLayoutGuide.heightAnchor],
		[self.actionStackView.topAnchor constraintEqualToAnchor:self.assetScrollView.bottomAnchor constant:10],
		[self.actionStackView.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[self.actionStackView.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[self.actionStackView.heightAnchor constraintEqualToConstant:38],
		[self.actionStackView.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
	]];
	return self;
}

- (void)cancelThumbnailTasks {
	for (IMThumbCacheTask *task in self.thumbnailTasks) {
		[task cancel];
	}
	[self.thumbnailTasks removeAllObjects];
}

- (void)removeAssetViews {
	for (UIView *view in [self.assetStackView.arrangedSubviews copy]) {
		[self.assetStackView removeArrangedSubview:view];
		[view removeFromSuperview];
	}
}

- (void)configureWithDuplicate:(IMDuplicate *)duplicate
                dismissHandler:(IMDuplicateGroupAction)dismissHandler
                  deleteHandler:(IMDuplicateGroupAction)deleteHandler
                   assetHandler:(IMDuplicateAssetAction)assetHandler {
	[self cancelThumbnailTasks];
	[self removeAssetViews];
	self.duplicate = duplicate;
	self.dismissHandler = dismissHandler;
	self.deleteHandler = deleteHandler;
	self.assetHandler = assetHandler;

	NSUInteger count = duplicate.assets.count;
	self.countLabel.text = count == 1
	    ? _(@"1 item")
	    : [NSString stringWithFormat:_(@"%ld items"), (long)count];
	NSArray<NSString *> *keepIDs = [duplicate assetIdsToKeep];
	BOOL hasServerSuggestion = duplicate.suggestedKeepAssetIds.count > 0;
	self.hintLabel.text = hasServerSuggestion
	    ? _(@"Suggested copies to keep are marked.")
	    : _(@"No suggestion was provided; the first copy will be kept.");
	self.deleteButton.enabled = [duplicate assetIdsToTrash].count > 0;
	self.deleteButton.alpha = self.deleteButton.enabled ? 1.0 : 0.45;

	NSSet<NSString *> *keepSet = [NSSet setWithArray:keepIDs];
	NSUInteger index = 0;
	for (IMAsset *asset in duplicate.assets) {
		if (asset.assetId.length == 0) {
			index++;
			continue;
		}
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.translatesAutoresizingMaskIntoConstraints = NO;
		button.tag = (NSInteger)index;
		button.accessibilityLabel = [NSString stringWithFormat:_(@"Photo %ld of %ld"), (long)(index + 1), (long)count];
		button.accessibilityValue = [keepSet containsObject:asset.assetId] ? _(@"Suggested to keep") : _(@"Suggested to delete");
		button.layer.cornerRadius = 8;
		button.clipsToBounds = YES;
		[button addTarget:self action:@selector(assetTapped:) forControlEvents:UIControlEventTouchUpInside];

		UIImageView *imageView = [[UIImageView alloc] init];
		imageView.translatesAutoresizingMaskIntoConstraints = NO;
		imageView.contentMode = UIViewContentModeScaleAspectFill;
		imageView.clipsToBounds = YES;
		if (@available(iOS 13.0, *)) {
			imageView.image = [UIImage systemImageNamed:@"photo"];
			imageView.tintColor = UIColor.secondaryLabelColor;
		} else {
			imageView.backgroundColor = UIColor.groupTableViewBackgroundColor;
		}
		[button addSubview:imageView];
		[NSLayoutConstraint activateConstraints:@[
			[button.widthAnchor constraintEqualToConstant:104],
			[button.heightAnchor constraintEqualToConstant:104],
			[imageView.topAnchor constraintEqualToAnchor:button.topAnchor],
			[imageView.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
			[imageView.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
			[imageView.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
		]];

		if ([keepSet containsObject:asset.assetId]) {
			UILabel *keepLabel = [[UILabel alloc] init];
			keepLabel.translatesAutoresizingMaskIntoConstraints = NO;
			keepLabel.text = _(@"KEEP");
			keepLabel.font = [UIFont boldSystemFontOfSize:10];
			keepLabel.textColor = UIColor.whiteColor;
			keepLabel.textAlignment = NSTextAlignmentCenter;
			keepLabel.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.9];
			[button addSubview:keepLabel];
			[NSLayoutConstraint activateConstraints:@[
				[keepLabel.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
				[keepLabel.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
				[keepLabel.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
				[keepLabel.heightAnchor constraintEqualToConstant:20],
			]];
		}

		[self.assetStackView addArrangedSubview:button];
		__weak UIImageView *weakImageView = imageView;
		IMThumbCacheTask *task = [[IMThumbCache shared] thumbnailForAssetId:asset.assetId
		                                                                  size:IMPrefs.shared.thumbnailQuality
		                                                            completion:^(UIImage *_Nullable image) {
			if (image) {
				weakImageView.image = image;
			}
		}];
		if (task) {
			[self.thumbnailTasks addObject:task];
		}
		index++;
	}
	self.assetScrollView.hidden = self.assetStackView.arrangedSubviews.count == 0;
	self.hintLabel.hidden = self.assetScrollView.hidden;
}

- (void)dismissTapped {
	if (self.dismissHandler && self.duplicate) {
		self.dismissHandler(self.duplicate);
	}
}

- (void)deleteTapped {
	if (self.deleteHandler && self.duplicate && self.deleteButton.enabled) {
		self.deleteHandler(self.duplicate);
	}
}

- (void)assetTapped:(UIButton *)sender {
	if (self.assetHandler && self.duplicate) {
		self.assetHandler(self.duplicate, sender.tag);
	}
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self cancelThumbnailTasks];
	[self removeAssetViews];
	self.duplicate = nil;
	self.dismissHandler = nil;
	self.deleteHandler = nil;
	self.assetHandler = nil;
	self.countLabel.text = nil;
	self.hintLabel.text = nil;
}

@end

@interface DuplicatesViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSArray<IMDuplicate *> *duplicates;
@property (nonatomic, strong, nullable) NSURLSessionTask *loadTask;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic) BOOL hasAppeared;
@end

@implementation DuplicatesViewController

static NSString *const kDuplicateCellReuseIdentifier = @"IMDuplicateGroupCell";

- (instancetype)init {
	self = [super init];
	if (self) {
		_duplicates = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Duplicates");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 220;
	[self.tableView registerClass:[IMDuplicateGroupCell class] forCellReuseIdentifier:kDuplicateCellReuseIdentifier];
	[self.view addSubview:self.tableView];

	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.userInteractionEnabled = YES;
	if (@available(iOS 13.0, *)) {
		self.statusLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.statusLabel.textColor = UIColor.grayColor;
	}
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.tableView.backgroundView = self.statusLabel;

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
	                                                                                           target:self
	                                                                                           action:@selector(reload)];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.hasAppeared) {
		[self reload];
	}
	self.hasAppeared = YES;
}

- (void)reload {
	if (self.loading || self.mutating) {
		return;
	}
	self.loading = YES;
	self.loadTask = nil;
	[self.spinner startAnimating];
	if (self.duplicates.count == 0) {
		self.statusLabel.text = _(@"Loading duplicates…");
	}
	__weak typeof(self) weakSelf = self;
	self.loadTask = [IMDuplicateApi duplicatesWithCompletion:^(NSArray<IMDuplicate *> *_Nullable duplicates, NSError *_Nullable error) {
		DuplicatesViewController *strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.loading = NO;
		strongSelf.loadTask = nil;
		[strongSelf.spinner stopAnimating];
		if (error || !duplicates) {
			strongSelf.statusLabel.text = strongSelf.duplicates.count > 0
			    ? _(@"Could not refresh duplicates. Tap to retry.")
			    : _(@"Could not load duplicates. Tap to retry.");
			[strongSelf.tableView reloadData];
			if (error && strongSelf.duplicates.count > 0) {
				[strongSelf showError:error];
			}
			return;
		}
		strongSelf.duplicates = duplicates;
		strongSelf.statusLabel.text = duplicates.count > 0 ? nil : _(@"No duplicate groups found.");
		[strongSelf.tableView reloadData];
	}];
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length > 0
	    ? error.localizedDescription
	    : _(@"The server could not complete this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Duplicates")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)dismissDuplicate:(IMDuplicate *)duplicate {
	if (self.mutating || duplicate.duplicateId.length == 0) {
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Keep all copies?")
	                                                                 message:_(@"This group will be removed from duplicate results. No photos will be deleted.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Keep All") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf performDismissForDuplicate:duplicate];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)performDismissForDuplicate:(IMDuplicate *)duplicate {
	if (self.mutating) {
		return;
	}
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMDuplicateApi dismissDuplicateId:duplicate.duplicateId completion:^(BOOL success, NSError *_Nullable error) {
		DuplicatesViewController *strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.mutating = NO;
		strongSelf.tableView.userInteractionEnabled = YES;
		if (!success) {
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain
			                                                  code:0
			                                              userInfo:@{ NSLocalizedDescriptionKey: _(@"Could not dismiss this duplicate group.") }]];
			return;
		}
		[strongSelf reload];
	}];
}

- (void)deleteDuplicate:(IMDuplicate *)duplicate {
	if (self.mutating) {
		return;
	}
	NSArray<NSString *> *keepIDs = [duplicate assetIdsToKeep];
	NSArray<NSString *> *trashIDs = [duplicate assetIdsToTrash];
	if (trashIDs.count == 0) {
		[self showError:[NSError errorWithDomain:IMApiErrorDomain
	                                          code:0
	                                      userInfo:@{ NSLocalizedDescriptionKey: _(@"There are no extra copies to delete.") }]];
		return;
	}
	NSString *itemWord = trashIDs.count == 1 ? _(@"other item") : _(@"other items");
	NSString *message = keepIDs.count == 1
	    ? [NSString stringWithFormat:_(@"Keep the suggested copy and remove %ld %@ from your library?"),
	                                 (long)trashIDs.count, itemWord]
	    : [NSString stringWithFormat:_(@"Keep the suggested copies and remove %ld %@ from your library?"),
	                                 (long)trashIDs.count, itemWord];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete extra copies?")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete Extras") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf performResolveForDuplicate:duplicate keepIDs:keepIDs trashIDs:trashIDs];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)performResolveForDuplicate:(IMDuplicate *)duplicate
                            keepIDs:(NSArray<NSString *> *)keepIDs
                           trashIDs:(NSArray<NSString *> *)trashIDs {
	if (self.mutating) {
		return;
	}
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMDuplicateApi resolveDuplicateId:duplicate.duplicateId
	                       keepAssetIds:keepIDs
	                      trashAssetIds:trashIDs
	                         completion:^(BOOL success, NSError *_Nullable error) {
		DuplicatesViewController *strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.mutating = NO;
		strongSelf.tableView.userInteractionEnabled = YES;
		if (!success) {
			[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain
			                                                  code:0
			                                              userInfo:@{ NSLocalizedDescriptionKey: _(@"Could not resolve this duplicate group.") }]];
			return;
		}
		[strongSelf reload];
	}];
}

- (void)showAssetAtIndex:(NSInteger)index inDuplicate:(IMDuplicate *)duplicate {
	if (index < 0 || index >= (NSInteger)duplicate.assets.count) {
		return;
	}
	AssetViewController *viewer = [AssetViewController viewerWithAssets:duplicate.assets startIndex:index];
	[self presentViewController:viewer animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.duplicates.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	IMDuplicateGroupCell *cell = [tableView dequeueReusableCellWithIdentifier:kDuplicateCellReuseIdentifier forIndexPath:indexPath];
	if (indexPath.row >= (NSInteger)self.duplicates.count) {
		return cell;
	}
	IMDuplicate *duplicate = self.duplicates[indexPath.row];
	__weak typeof(self) weakSelf = self;
	[cell configureWithDuplicate:duplicate
	               dismissHandler:^(IMDuplicate *group) {
		[weakSelf dismissDuplicate:group];
	}
	                 deleteHandler:^(IMDuplicate *group) {
		[weakSelf deleteDuplicate:group];
	}
	                  assetHandler:^(IMDuplicate *group, NSInteger index) {
		[weakSelf showAssetAtIndex:index inDuplicate:group];
	}];
	return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

@end
