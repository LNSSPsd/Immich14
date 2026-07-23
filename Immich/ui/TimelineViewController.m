#import "TimelineViewController.h"
#import "TimelineCell.h"
#import "IMAssetApi.h"
#import "IMDatabase.h"
#import "common.h"

static NSString *const kHeaderReuseIdentifier = @"TimelineHeader";

@interface TimelineSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation TimelineSectionHeader

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		if (@available(iOS 13.0, *)) {
			self.backgroundColor = UIColor.systemBackgroundColor;
		} else {
			self.backgroundColor = UIColor.whiteColor;
		}
		self.titleLabel = [[UILabel alloc] init];
		self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
		[self addSubview:self.titleLabel];
		[NSLayoutConstraint activateConstraints:@[
			[self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
			[self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12],
			[self.titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
		]];
	}
	return self;
}

@end

@interface TimelineViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<NSString *> *bucketDates;   
@property (nonatomic, strong) NSArray<NSNumber *> *bucketCounts;  
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<IMAsset *> *> *bucketAssets;
@property (nonatomic, strong) NSMutableSet<NSString *> *loadingBuckets;
@property (nonatomic, strong) NSDateFormatter *headerDateFormatter;
@end

@implementation TimelineViewController

static const NSInteger kColumns = 4;
static const CGFloat kCellSpacing = 2;

- (instancetype)init {
	self = [super init];
	if (self) {
		_bucketDates = @[];
		_bucketCounts = @[];
		_bucketAssets = [NSMutableDictionary dictionary];
		_loadingBuckets = [NSMutableSet set];

		_headerDateFormatter = [[NSDateFormatter alloc] init];
		_headerDateFormatter.dateFormat = @"yyyy-MM-dd";
		_headerDateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Timeline");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = kCellSpacing;
	layout.minimumLineSpacing = kCellSpacing;
	layout.sectionInset = UIEdgeInsetsZero;
	layout.headerReferenceSize = CGSizeMake(0, 32);

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
	[self.collectionView registerClass:[TimelineSectionHeader class]
	         forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
	                withReuseIdentifier:kHeaderReuseIdentifier];
	[self.view addSubview:self.collectionView];

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.text = _(@"No photos yet.");
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	if (@available(iOS 13.0, *)) {
		self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.emptyLabel.textColor = UIColor.grayColor;
	}
	self.emptyLabel.hidden = YES;
	[self.view addSubview:self.emptyLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	[self loadCachedBuckets];
	[self refreshBuckets];
}

#pragma mark - Bucket loading

- (void)loadCachedBuckets {
	NSArray<NSString *> *dates;
	NSArray<NSNumber *> *counts;
	[[IMDatabase shared] cachedBucketDates:&dates counts:&counts];
	if (dates.count > 0) {
		self.bucketDates = dates;
		self.bucketCounts = counts;
		[self.collectionView reloadData];
		[self updateEmptyState];
	}
}

- (void)refreshBuckets {
	__weak typeof(self) weakSelf = self;
	[IMAssetApi timeBucketsWithCompletion:^(NSArray<NSString *> *_Nullable bucketDates,
	                                         NSArray<NSNumber *> *_Nullable counts, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || error || !bucketDates) {
			return;
		}
		strongSelf.bucketDates = bucketDates;
		strongSelf.bucketCounts = counts;
		[[IMDatabase shared] replaceBucketDates:bucketDates counts:counts];
		[strongSelf.collectionView reloadData];
		[strongSelf updateEmptyState];
	}];
}

- (void)updateEmptyState {
	self.emptyLabel.hidden = self.bucketDates.count > 0;
}

- (void)loadBucketIfNeeded:(NSString *)bucket {
	if (self.bucketAssets[bucket] || [self.loadingBuckets containsObject:bucket]) {
		return;
	}

	NSArray<IMAsset *> *cached = [[IMDatabase shared] cachedAssetsForTimeBucket:bucket];
	if (cached.count > 0) {
		self.bucketAssets[bucket] = cached;
		[self reloadSectionForBucket:bucket];
	}

	[self.loadingBuckets addObject:bucket];
	__weak typeof(self) weakSelf = self;
	[IMAssetApi assetsInTimeBucket:bucket
	                     completion:^(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    [strongSelf.loadingBuckets removeObject:bucket];
		    if (error || !assets) {
			    return;
		    }
		    strongSelf.bucketAssets[bucket] = assets;
		    [[IMDatabase shared] replaceAssets:assets forTimeBucket:bucket];
		    [strongSelf reloadSectionForBucket:bucket];
	    }];
}

- (void)reloadSectionForBucket:(NSString *)bucket {
	NSUInteger section = [self.bucketDates indexOfObject:bucket];
	if (section == NSNotFound || section >= (NSUInteger)self.collectionView.numberOfSections) {
		return;
	}
	[self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:section]];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	return self.bucketDates.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.bucketCounts[section].integerValue;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                   cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier
	                                                                forIndexPath:indexPath];
	NSString *bucket = self.bucketDates[indexPath.section];
	NSArray<IMAsset *> *assets = self.bucketAssets[bucket];
	if (assets && (NSUInteger)indexPath.item < assets.count) {
		[cell configureWithAsset:assets[indexPath.item]];
	} else {
		[cell configureWithAsset:nil];
		[self loadBucketIfNeeded:bucket];
	}
	return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
            viewForSupplementaryElementOfKind:(NSString *)kind
                                  atIndexPath:(NSIndexPath *)indexPath {
	TimelineSectionHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
	                                                                withReuseIdentifier:kHeaderReuseIdentifier
	                                                                       forIndexPath:indexPath];
	NSString *bucket = self.bucketDates[indexPath.section];
	NSDate *date = [self.headerDateFormatter dateFromString:bucket];
	if (date) {
		static NSDateFormatter *titleFormatter;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			titleFormatter = [[NSDateFormatter alloc] init];
			titleFormatter.dateFormat = @"MMMM yyyy";
			titleFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		});
		header.titleLabel.text = [titleFormatter stringFromDate:date];
	} else {
		header.titleLabel.text = bucket;
	}
	return header;
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
