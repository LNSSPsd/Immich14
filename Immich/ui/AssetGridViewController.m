#import "AssetGridViewController.h"
#import "TimelineCell.h"
#import "AssetViewController.h"
#import "common.h"

@interface AssetGridViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, IMZoomTransitionSource>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@property (nonatomic, strong, nullable) NSURLSessionTask *pageTask;
@end

@implementation AssetGridViewController

static const NSInteger kColumns = 4;
static const CGFloat kCellSpacing = 2;

+ (instancetype)gridWithTitle:(NSString *)title assets:(NSArray<IMAsset *> *)assets {
	AssetGridViewController *vc = [[AssetGridViewController alloc] init];
	vc.title = title;
	vc.assets = assets;
	return vc;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_assets = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = kCellSpacing;
	layout.minimumLineSpacing = kCellSpacing;

	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	if (@available(iOS 13.0, *)) {
		self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.collectionView.backgroundColor = UIColor.whiteColor;
	}
	[self.collectionView registerClass:[TimelineCell class] forCellWithReuseIdentifier:TimelineCellReuseIdentifier];
	[self.view addSubview:self.collectionView];

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.text = _(@"No photos here.");
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	if (@available(iOS 13.0, *)) {
		self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.emptyLabel.textColor = UIColor.grayColor;
	}
	self.emptyLabel.hidden = self.assets.count > 0;
	[self.view addSubview:self.emptyLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.assets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                   cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier
	                                                                forIndexPath:indexPath];
	[cell configureWithAsset:self.assets[indexPath.item]];
	return cell;
}

#pragma mark - Pagination

- (void)loadNextPageIfNeeded {
	if (self.pageTask || !self.pageLoader || self.nextPageToken.length == 0) {
		return;
	}
	NSInteger page = self.nextPageToken.integerValue;
	if (page < 1) {
		self.nextPageToken = nil;
		return;
	}
	__weak typeof(self) weakSelf = self;
	self.pageTask = self.pageLoader(page, ^(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.pageTask = nil;
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
			return;
		}
		if (error || !assets) {
			return;
		}
		strongSelf.assets = [strongSelf.assets arrayByAddingObjectsFromArray:assets];
		strongSelf.nextPageToken = nextPage;
		[strongSelf.collectionView reloadData];
		strongSelf.emptyLabel.hidden = strongSelf.assets.count > 0;
	});
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width;
	CGFloat side = (width - (kColumns - 1) * kCellSpacing) / kColumns;
	return CGSizeMake(side, side);
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView
        willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.item + kColumns * 6 >= (NSInteger)self.assets.count) {
		[self loadNextPageIfNeeded];
	}
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];
	if (indexPath.item < (NSInteger)self.assets.count && self.selectionHandler) {
		self.selectionHandler(self.assets[indexPath.item]);
		return;
	}
	AssetViewController *viewer = [AssetViewController viewerWithAssets:self.assets startIndex:indexPath.item];
	viewer.zoomSource = self;
	viewer.presentSourceImageView = ((TimelineCell *)[collectionView cellForItemAtIndexPath:indexPath]).imageView;
	[self presentViewController:viewer animated:YES completion:nil];
}

#pragma mark - IMZoomTransitionSource

- (nullable UIImageView *)zoomTransitionImageViewForAssetId:(NSString *)assetId {
	NSUInteger item = [self.assets indexOfObjectPassingTest:^BOOL(IMAsset *asset, NSUInteger idx, BOOL *stop) {
		return [asset.assetId isEqualToString:assetId];
	}];
	if (item == NSNotFound) {
		return nil;
	}
	NSIndexPath *indexPath = [NSIndexPath indexPathForItem:(NSInteger)item inSection:0];
	TimelineCell *cell = (TimelineCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
	if (!cell) {
		[self.collectionView scrollToItemAtIndexPath:indexPath
		                            atScrollPosition:UICollectionViewScrollPositionCenteredVertically
		                                    animated:NO];
		[self.collectionView layoutIfNeeded];
		cell = (TimelineCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
	}
	return cell.imageView;
}

@end
