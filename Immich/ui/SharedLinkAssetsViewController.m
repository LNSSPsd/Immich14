#import "SharedLinkAssetsViewController.h"
#import "IMSharedLinkApi.h"
#import "IMAssetApi.h"
#import "TimelineCell.h"
#import "common.h"

static const CGFloat kSharedLinkAssetSpacing = 2.0;
static const NSInteger kSharedLinkAssetColumns = 4;

@interface SharedLinkAssetsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) IMSharedLink *link;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedAssetIds;
@property (nonatomic, strong) NSSet<NSString *> *excludedAssetIds;
@property (nonatomic, copy) IMSharedLinkAssetPickerCompletion pickerCompletion;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIToolbar *actionToolbar;
@property (nonatomic, strong) UIBarButtonItem *removeButton;
@property (nonatomic, strong) UIBarButtonItem *addButton;
@property (nonatomic) BOOL pickerMode;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic) BOOL didLoad;
@property (nonatomic) BOOL hasAppeared;
- (void)showError:(NSError *)error;
- (void)updateToolbar;
- (void)reloadAfterMutationWithMessage:(nullable NSString *)message;
- (void)addAssets:(NSArray<IMAsset *> *)assets;
- (void)removeSelectedAssets;
- (void)loadAllAssets;
@end

@implementation SharedLinkAssetsViewController

+ (instancetype)managerForLink:(IMSharedLink *)link {
	SharedLinkAssetsViewController *vc = [[self alloc] init];
	vc.link = link;
	vc.assets = link.assets ?: @[];
	return vc;
}

+ (instancetype)pickerWithExcludedAssetIds:(NSSet<NSString *> *)excludedAssetIds
                                completion:(IMSharedLinkAssetPickerCompletion)completion {
	SharedLinkAssetsViewController *vc = [[self alloc] init];
	vc.pickerMode = YES;
	vc.excludedAssetIds = [excludedAssetIds copy] ?: [NSSet set];
	vc.pickerCompletion = [completion copy];
	return vc;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_assets = @[];
		_selectedAssetIds = [NSMutableSet set];
		_excludedAssetIds = [NSSet set];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.pickerMode ? _(@"Add Photos") : _(@"Link Photos");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}

	if (self.pickerMode) {
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
		                                                                                       target:self
		                                                                                       action:@selector(cancelTapped)];
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
		                                                                                        target:self
		                                                                                        action:@selector(doneTapped)];
	} else {
		self.addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
		                                                                target:self
		                                                                action:@selector(addTapped)];
		self.navigationItem.rightBarButtonItem = self.addButton;
	}

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = kSharedLinkAssetSpacing;
	layout.minimumLineSpacing = kSharedLinkAssetSpacing;
	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	self.collectionView.allowsMultipleSelection = YES;
	if (@available(iOS 13.0, *)) {
		self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.collectionView.backgroundColor = UIColor.whiteColor;
	}
	[self.collectionView registerClass:[TimelineCell class] forCellWithReuseIdentifier:TimelineCellReuseIdentifier];
	[self.view addSubview:self.collectionView];

	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.text = self.pickerMode ? _(@"Loading your photos…") : nil;
	if (@available(iOS 13.0, *)) {
		self.statusLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.statusLabel.textColor = UIColor.grayColor;
	}
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.collectionView.backgroundView = self.statusLabel;

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	if (!self.pickerMode) {
		self.actionToolbar = [[UIToolbar alloc] init];
		self.actionToolbar.translatesAutoresizingMaskIntoConstraints = NO;
		self.actionToolbar.hidden = YES;
		self.removeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
		                                                                  target:self
		                                                                  action:@selector(removeTapped)];
		UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
		                                                                        target:nil
		                                                                        action:nil];
		[self.actionToolbar setItems:@[flex, self.removeButton]];
		[self.view addSubview:self.actionToolbar];
		[NSLayoutConstraint activateConstraints:@[
			[self.actionToolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
			[self.actionToolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
			[self.actionToolbar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
			[self.collectionView.bottomAnchor constraintEqualToAnchor:self.actionToolbar.topAnchor],
		]];
		[self reload];
	} else {
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
		[self loadAllAssets];
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!self.pickerMode) {
		if (self.hasAppeared) [self reload];
		self.hasAppeared = YES;
		[self updateToolbar];
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.actionToolbar) self.actionToolbar.hidden = YES;
}

- (void)reload {
	if (self.pickerMode) {
		[self loadAllAssets];
		return;
	}
	if (self.loading || self.mutating || !self.link.linkId.length) return;
	self.loading = YES;
	self.didLoad = YES;
	self.statusLabel.text = self.assets.count ? nil : _(@"Loading link photos…");
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMSharedLinkApi linkForId:self.link.linkId completion:^(IMSharedLink *link, NSError *error) {
		SharedLinkAssetsViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		[self.spinner stopAnimating];
		if (error || !link) {
			if (!self.assets.count) self.statusLabel.text = _(@"Couldn't load link photos. Tap to retry.");
			else [self showError:error];
			return;
		}
		self.link = link;
		self.assets = link.assets ?: @[];
		[self.selectedAssetIds removeAllObjects];
		self.statusLabel.text = self.assets.count ? nil : _(@"This link has no photos. Tap + to add some.");
		[self.collectionView reloadData];
		[self updateToolbar];
	}];
}

- (void)loadAllAssets {
	if (self.loading) return;
	self.loading = YES;
	[self.spinner startAnimating];
	self.statusLabel.text = _(@"Loading your photos…");
	__weak typeof(self) weakSelf = self;
	[IMAssetApi timeBucketsWithCompletion:^(NSArray<NSString *> *dates, NSArray<NSNumber *> *counts, NSError *error) {
		SharedLinkAssetsViewController *self = weakSelf;
		if (!self) return;
		if (error || !dates) {
			self.loading = NO;
			[self.spinner stopAnimating];
			self.statusLabel.text = _(@"Couldn't load photos. Tap to retry.");
			if (error) [self showError:error];
			return;
		}
		NSMutableArray *bucketAssets = [NSMutableArray arrayWithCapacity:dates.count];
		for (NSUInteger i = 0; i < dates.count; i++) [bucketAssets addObject:[NSNull null]];
		dispatch_group_t group = dispatch_group_create();
		for (NSUInteger i = 0; i < dates.count; i++) {
			NSString *date = dates[i];
			dispatch_group_enter(group);
			[IMAssetApi assetsInTimeBucket:date completion:^(NSArray<IMAsset *> *assets, NSError *bucketError) {
				if (!bucketError && assets) bucketAssets[i] = assets;
				dispatch_group_leave(group);
			}];
		}
		dispatch_group_notify(group, dispatch_get_main_queue(), ^{
			SharedLinkAssetsViewController *inner = weakSelf;
			if (!inner) return;
			NSMutableArray<IMAsset *> *all = [NSMutableArray array];
			for (id value in bucketAssets) if ([value isKindOfClass:NSArray.class]) [all addObjectsFromArray:value];
			NSMutableArray<IMAsset *> *filtered = [NSMutableArray arrayWithCapacity:all.count];
			for (IMAsset *asset in all) if (![inner.excludedAssetIds containsObject:asset.assetId]) [filtered addObject:asset];
			inner.assets = filtered;
			inner.loading = NO;
			[inner.spinner stopAnimating];
			inner.statusLabel.text = inner.assets.count ? nil : _(@"No additional photos are available.");
			[inner.collectionView reloadData];
		});
	}];
}

- (void)cancelTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doneTapped {
	NSMutableArray<IMAsset *> *selected = [NSMutableArray array];
	for (IMAsset *asset in self.assets) if ([self.selectedAssetIds containsObject:asset.assetId]) [selected addObject:asset];
	IMSharedLinkAssetPickerCompletion completion = self.pickerCompletion;
	[self dismissViewControllerAnimated:YES completion:^{
		if (completion) completion(selected);
	}];
}

- (void)addTapped {
	if (self.loading || self.mutating || !self.link.linkId.length) return;
	NSMutableSet *excluded = [NSMutableSet set];
	for (IMAsset *asset in self.assets) if (asset.assetId.length) [excluded addObject:asset.assetId];
	__weak typeof(self) weakSelf = self;
	SharedLinkAssetsViewController *picker = [SharedLinkAssetsViewController pickerWithExcludedAssetIds:excluded
	                                                                                             completion:^(NSArray<IMAsset *> *assets) {
		SharedLinkAssetsViewController *self = weakSelf;
		if (!self || !assets.count) return;
		[self addAssets:assets];
	}];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)addAssets:(NSArray<IMAsset *> *)assets {
	if (self.mutating || !assets.count) return;
	self.mutating = YES;
	self.collectionView.userInteractionEnabled = NO;
	self.addButton.enabled = NO;
	NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:assets.count];
	for (IMAsset *asset in assets) if (asset.assetId.length) [ids addObject:asset.assetId];
	__weak typeof(self) weakSelf = self;
	[IMSharedLinkApi addAssetIds:ids toLinkId:self.link.linkId completion:^(BOOL success, NSError *error) {
		SharedLinkAssetsViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		self.collectionView.userInteractionEnabled = YES;
		self.addButton.enabled = YES;
		if (!success && error) [self showError:error];
		[self reloadAfterMutationWithMessage:success ? nil : _(@"Some photos could not be added to this link.")];
	}];
}

- (void)removeTapped {
	if (self.mutating || self.selectedAssetIds.count == 0) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Remove photos from link?")
	                                                                 message:_(@"The original photos will stay in your library.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		SharedLinkAssetsViewController *self = weakSelf;
		if (!self) return;
		[self removeSelectedAssets];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)removeSelectedAssets {
	if (self.mutating || !self.selectedAssetIds.count) return;
	self.mutating = YES;
	self.collectionView.userInteractionEnabled = NO;
	NSArray<NSString *> *ids = self.selectedAssetIds.allObjects;
	__weak typeof(self) weakSelf = self;
	[IMSharedLinkApi removeAssetIds:ids fromLinkId:self.link.linkId completion:^(BOOL success, NSError *error) {
		SharedLinkAssetsViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		self.collectionView.userInteractionEnabled = YES;
		if (!success && error) [self showError:error];
		[self reloadAfterMutationWithMessage:success ? nil : _(@"Some photos could not be removed from this link.")];
	}];
}

- (void)reloadAfterMutationWithMessage:(NSString *)message {
	[self.selectedAssetIds removeAllObjects];
	[self updateToolbar];
	[self reload];
	if (message.length) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (self.viewIfLoaded.window) {
				[self showError:[NSError errorWithDomain:@"IMSharedLinkError"
				                                  code:2
				                              userInfo:@{ NSLocalizedDescriptionKey : message }]];
			}
		});
	}
}

- (void)updateToolbar {
	self.actionToolbar.hidden = self.selectedAssetIds.count == 0;
	self.removeButton.enabled = self.selectedAssetIds.count > 0 && !self.mutating;
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not complete this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Shared Link Photos")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.assets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier forIndexPath:indexPath];
	IMAsset *asset = self.assets[indexPath.item];
	cell.selectionModeEnabled = YES;
	[cell configureWithAsset:asset];
	cell.selected = [self.selectedAssetIds containsObject:asset.assetId];
	return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width;
	CGFloat side = (width - (kSharedLinkAssetColumns - 1) * kSharedLinkAssetSpacing) / kSharedLinkAssetColumns;
	return CGSizeMake(MAX(1, side), MAX(1, side));
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	IMAsset *asset = self.assets[indexPath.item];
	if (!asset.assetId.length) return;
	if ([self.selectedAssetIds containsObject:asset.assetId]) {
		[self.selectedAssetIds removeObject:asset.assetId];
		[collectionView deselectItemAtIndexPath:indexPath animated:NO];
	} else {
		[self.selectedAssetIds addObject:asset.assetId];
	}
	[(TimelineCell *)[collectionView cellForItemAtIndexPath:indexPath] setSelected:[self.selectedAssetIds containsObject:asset.assetId]];
	[self updateToolbar];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.item >= (NSInteger)self.assets.count) return;
	IMAsset *asset = self.assets[indexPath.item];
	[self.selectedAssetIds removeObject:asset.assetId];
	[self updateToolbar];
}

@end
