#import "LocalAssetGridViewController.h"
#import "common.h"
#import <Photos/Photos.h>

static NSString *const kCellId = @"LocalAssetCell";

@interface IMLocalAssetCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic) PHImageRequestID requestId;
- (void)configureWithAsset:(nullable PHAsset *)asset;
@end

@implementation IMLocalAssetCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		if (@available(iOS 13.0, *)) {
			self.contentView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
		} else {
			self.contentView.backgroundColor = UIColor.groupTableViewBackgroundColor;
		}
		self.imageView = [[UIImageView alloc] init];
		self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
		[self.contentView addSubview:self.imageView];
		[NSLayoutConstraint activateConstraints:@[
			[self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
		]];
		self.requestId = PHInvalidImageRequestID;
	}
	return self;
}

- (void)configureWithAsset:(nullable PHAsset *)asset {
	if (self.requestId != PHInvalidImageRequestID) {
		[[PHImageManager defaultManager] cancelImageRequest:self.requestId];
		self.requestId = PHInvalidImageRequestID;
	}
	self.imageView.image = nil;
	if (!asset) {
		return;
	}

	PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
	options.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
	options.resizeMode = PHImageRequestOptionsResizeModeFast;
	options.networkAccessAllowed = YES;

	CGFloat scale = UIScreen.mainScreen.scale;
	CGSize targetSize = CGSizeMake(120 * scale, 120 * scale);
	__weak typeof(self) weakSelf = self;
	self.requestId = [[PHImageManager defaultManager]
	    requestImageForAsset:asset
	              targetSize:targetSize
	             contentMode:PHImageContentModeAspectFill
	                 options:options
	           resultHandler:^(UIImage *_Nullable result, NSDictionary *_Nullable info) {
		    weakSelf.imageView.image = result;
	    }];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	if (self.requestId != PHInvalidImageRequestID) {
		[[PHImageManager defaultManager] cancelImageRequest:self.requestId];
		self.requestId = PHInvalidImageRequestID;
	}
	self.imageView.image = nil;
}

@end

@interface LocalAssetGridViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<PHAsset *> *assets;
@end

@implementation LocalAssetGridViewController

static const NSInteger kColumns = 4;
static const CGFloat kCellSpacing = 2;

+ (instancetype)gridWithTitle:(NSString *)title deviceAssetIds:(NSArray<NSString *> *)deviceAssetIds {
	LocalAssetGridViewController *vc = [[LocalAssetGridViewController alloc] init];
	vc.title = title;

	PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithLocalIdentifiers:deviceAssetIds options:nil];
	NSMutableArray<PHAsset *> *assets = [NSMutableArray arrayWithCapacity:result.count];
	[result enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
		[assets addObject:asset];
	}];
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
	[self.collectionView registerClass:[IMLocalAssetCell class] forCellWithReuseIdentifier:kCellId];
	[self.view addSubview:self.collectionView];

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.text = _(@"Nothing pending.");
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
	IMLocalAssetCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCellId forIndexPath:indexPath];
	[cell configureWithAsset:self.assets[indexPath.item]];
	return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width;
	CGFloat side = (width - (kColumns - 1) * kCellSpacing) / kColumns;
	return CGSizeMake(side, side);
}

@end
