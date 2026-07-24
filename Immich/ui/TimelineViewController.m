#import "TimelineViewController.h"
#import "TimelineCell.h"
#import "IMClusterCell.h"
#import "IMTimelineGridLayout.h"
#import "IMAssetApi.h"
#import "AssetViewController.h"
#import "IMBulkAssetActions.h"
#import "IMDatabase.h"
#import "IMPhotoLibrary.h"
#import "common.h"
#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>

static const int64_t kLocalRefreshDebounceMs = 750;

static const NSInteger kColumnSteps[] = {1, 3, 5, 11, 23};
static const NSInteger kColumnStepCount = 5;
static const NSInteger kDenseGridMinColumns = 11; 
static const CGFloat kClusterEnterOvershoot = 1.35; 
static const CGFloat kClusterExitPinchScale = 1.3;  
static const CGFloat kClusterRowHeight = 84;
static const CGFloat kFooterHeight = 56; 

@interface IMTimelineLocalItem : NSObject
@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic) IMSyncState state;
+ (instancetype)itemWithAsset:(PHAsset *)asset state:(IMSyncState)state;
@end

@implementation IMTimelineLocalItem
+ (instancetype)itemWithAsset:(PHAsset *)asset state:(IMSyncState)state {
	IMTimelineLocalItem *item = [[IMTimelineLocalItem alloc] init];
	item.asset = asset;
	item.state = state;
	return item;
}
@end

@interface TimelineViewController () <UICollectionViewDataSource, UICollectionViewDelegate, PHPhotoLibraryChangeObserver>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<NSString *> *bucketDates;               
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *serverBucketCounts; 
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<IMAsset *> *> *bucketAssets;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<IMTimelineLocalItem *> *> *localItemsByBucket;
@property (nonatomic, strong) NSMutableSet<NSString *> *loadingBuckets;
@property (nonatomic, strong) NSDateFormatter *headerDateFormatter;
@property (nonatomic, strong) dispatch_queue_t localScanQueue;
@property (nonatomic) BOOL localRefreshPending;
@property (nonatomic) BOOL hasScrolledToNewest; 
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic) NSInteger statsImageCount;
@property (nonatomic) NSInteger statsVideoCount;

@property (nonatomic) BOOL selecting;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IMAsset *> *selectedAssets;
@property (nonatomic, strong) UIBarButtonItem *favoriteButton;
@property (nonatomic, strong) UIBarButtonItem *addAlbumButton;
@property (nonatomic, strong) UIBarButtonItem *downloadButton;
@property (nonatomic, strong) UIBarButtonItem *deleteButton;

@property (nonatomic) NSInteger columnStepIndex; 
@property (nonatomic) CGFloat liveColumns;        
@property (nonatomic, readonly) IMTimelineGridLayout *gridLayout;
@property (nonatomic) CGFloat pinchStartColumns;  
@property (nonatomic) CGFloat pinchColumns;      
@property (nonatomic) NSInteger zoomLowIndex;
@property (nonatomic) NSInteger zoomHighIndex;
@property (nonatomic, strong) CADisplayLink *zoomSettleLink;
@property (nonatomic) CGFloat zoomSettleFrom;
@property (nonatomic) CGFloat zoomSettleTo;
@property (nonatomic) CFTimeInterval zoomSettleStartTime;
@property (nonatomic) CFTimeInterval zoomSettleDuration;
@property (nonatomic, strong) NSIndexPath *zoomAnchorIndexPath;
@property (nonatomic) CGFloat zoomAnchorFraction; 
@property (nonatomic) CGFloat zoomAnchorViewY;    
@property (nonatomic) BOOL clusterMode;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UILabel *> *denseBadgeViewsByBucket;
@property (nonatomic, strong) UIView *titleScrimView;
@property (nonatomic, strong) CAGradientLayer *titleScrimLayer;
@property (nonatomic, strong) UILabel *dateRangeLabel;
@property (nonatomic, strong) UILabel *locationLabel;
@property (nonatomic, strong) UIVisualEffectView *selectPillView;
@property (nonatomic, strong) UIButton *selectButton;
@end

@implementation TimelineViewController

static const CGFloat kCellSpacing = 2;

- (instancetype)init {
	self = [super init];
	if (self) {
		_bucketDates = @[];
		_serverBucketCounts = @{};
		_bucketAssets = [NSMutableDictionary dictionary];
		_localItemsByBucket = @{};
		_loadingBuckets = [NSMutableSet set];
		_localScanQueue = dispatch_queue_create("com.lns.immich-ios-14.timeline.localscan", DISPATCH_QUEUE_SERIAL);
		_selectedAssets = [NSMutableDictionary dictionary];
		_columnStepIndex = 2; 
		_liveColumns = kColumnSteps[_columnStepIndex];
		_denseBadgeViewsByBucket = [NSMutableDictionary dictionary];

		_headerDateFormatter = [[NSDateFormatter alloc] init];
		_headerDateFormatter.dateFormat = @"yyyy-MM-dd";
		_headerDateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	}
	return self;
}

- (void)dealloc {
	[_zoomSettleLink invalidate];
	[[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Timeline");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}
	self.navigationController.navigationBarHidden = YES;

	IMTimelineGridLayout *layout = [[IMTimelineGridLayout alloc] init];
	layout.spacing = kCellSpacing;
	layout.rowHeight = kClusterRowHeight;
	layout.footerHeight = kFooterHeight;
	[layout setFromColumns:kColumnSteps[self.columnStepIndex] toColumns:kColumnSteps[self.columnStepIndex] progress:0];

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
	[self.collectionView registerClass:[IMClusterCell class] forCellWithReuseIdentifier:IMClusterCellReuseIdentifier];
	[self.view addSubview:self.collectionView];

	self.footerLabel = [[UILabel alloc] init];
	self.footerLabel.textAlignment = NSTextAlignmentCenter;
	self.footerLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
	if (@available(iOS 13.0, *)) {
		self.footerLabel.textColor = UIColor.labelColor;
	} else {
		self.footerLabel.textColor = UIColor.blackColor;
	}
	[self.collectionView addSubview:self.footerLabel];

	UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
	[self.collectionView addGestureRecognizer:pinch];

	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(pullToRefresh) forControlEvents:UIControlEventValueChanged];
	self.collectionView.refreshControl = self.refreshControl;

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
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.userInteractionEnabled = YES;
	[self.emptyLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pullToRefresh)]];
	[self.view addSubview:self.emptyLabel];

	[self setUpTitleBar];

	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	[[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(scheduleLocalRefresh)
	                                              name:IMSyncStateDidChangeNotification
	                                            object:nil];

	[self loadCachedBuckets];
	[self refreshBuckets];
	[self refreshLocalPendingAssets];
	[self refreshAssetStatistics];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self scheduleLocalRefresh];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	UIEdgeInsets insets = UIEdgeInsetsMake(self.view.safeAreaInsets.top, 0, 0, 0);
	if (!UIEdgeInsetsEqualToEdgeInsets(self.collectionView.contentInset, insets)) {
		self.collectionView.contentInset = insets;
		self.collectionView.scrollIndicatorInsets = insets;
	}
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	self.titleScrimLayer.frame = self.titleScrimView.bounds;
	[CATransaction commit];
	[self updateFooterLabel];
}

#pragma mark - Local (PhotoKit) pending assets

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self scheduleLocalRefresh];
	});
}

- (void)scheduleLocalRefresh {
	if (self.localRefreshPending) {
		return;
	}
	self.localRefreshPending = YES;
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kLocalRefreshDebounceMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.localRefreshPending = NO;
		[strongSelf refreshLocalPendingAssets];
	});
}

- (NSString *)bucketKeyForDate:(NSDate *)date {
	static NSCalendar *calendar;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
		calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	});
	NSDateComponents *comps = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:date];
	comps.day = 1;
	return [self.headerDateFormatter stringFromDate:[calendar dateFromComponents:comps]];
}

- (void)refreshLocalPendingAssets {
	NSDictionary<NSString *, NSNumber *> *states = [[IMDatabase shared] allDeviceAssetSyncStates];
	__weak typeof(self) weakSelf = self;
	dispatch_async(self.localScanQueue, ^{
		NSArray<PHAsset *> *assets = [[IMPhotoLibrary shared] allAssets]; 
		NSMutableDictionary<NSString *, NSMutableArray<IMTimelineLocalItem *> *> *grouped = [NSMutableDictionary dictionary];
		for (PHAsset *asset in assets) {
			NSNumber *stateNum = states[asset.localIdentifier];
			IMSyncState state = stateNum ? (IMSyncState)stateNum.integerValue : IMSyncStateUnknown;
			if (state == IMSyncStateSynced) {
				continue; 
			}
			NSDate *date = asset.creationDate;
			if (!date) {
				continue;
			}
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) {
				return;
			}
			NSString *bucket = [strongSelf bucketKeyForDate:date];
			NSMutableArray<IMTimelineLocalItem *> *items = grouped[bucket];
			if (!items) {
				items = [NSMutableArray array];
				grouped[bucket] = items;
			}
			[items addObject:[IMTimelineLocalItem itemWithAsset:asset state:state]];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) {
				return;
			}
			strongSelf.localItemsByBucket = grouped;
			[strongSelf recomputeBucketDates];
		});
	});
}

#pragma mark - Multi-select

- (void)toggleSelecting {
	self.selecting = !self.selecting;
	[self.selectedAssets removeAllObjects];
	for (NSIndexPath *indexPath in [self.collectionView.indexPathsForSelectedItems copy]) {
		[self.collectionView deselectItemAtIndexPath:indexPath animated:NO];
	}
	self.collectionView.allowsMultipleSelection = self.selecting;
	if (self.selecting) {
		self.toolbarItems = [self makeSelectionToolbarItems];
	}
	[self.navigationController setToolbarHidden:!self.selecting animated:YES];
	[self.collectionView reloadData]; 
	[self updateSelectionToolbarState];
}

- (NSArray<UIBarButtonItem *> *)makeSelectionToolbarItems {
	UIImage *starImage = nil, *albumImage = nil, *downloadImage = nil, *trashImage = nil;
	if (@available(iOS 13.0, *)) {
		starImage = [UIImage systemImageNamed:@"star"];
		albumImage = [UIImage systemImageNamed:@"plus.rectangle.on.folder"];
		downloadImage = [UIImage systemImageNamed:@"square.and.arrow.down"];
		trashImage = [UIImage systemImageNamed:@"trash"];
	}
	self.favoriteButton = [[UIBarButtonItem alloc] initWithImage:starImage style:UIBarButtonItemStylePlain target:self action:@selector(favoriteSelected)];
	self.addAlbumButton = [[UIBarButtonItem alloc] initWithImage:albumImage style:UIBarButtonItemStylePlain target:self action:@selector(addSelectedToAlbum)];
	self.downloadButton = [[UIBarButtonItem alloc] initWithImage:downloadImage style:UIBarButtonItemStylePlain target:self action:@selector(downloadSelected)];
	self.deleteButton = [[UIBarButtonItem alloc] initWithImage:trashImage style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)];
	if (@available(iOS 13.0, *)) {
		self.deleteButton.tintColor = UIColor.systemRedColor;
	}
	UIBarButtonItem *flex1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex3 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	return @[ self.favoriteButton, flex1, self.addAlbumButton, flex2, self.downloadButton, flex3, self.deleteButton ];
}

- (void)updateSelectionToolbarState {
	BOOL hasSelection = self.selectedAssets.count > 0;
	self.favoriteButton.enabled = hasSelection;
	self.addAlbumButton.enabled = hasSelection;
	self.downloadButton.enabled = hasSelection;
	self.deleteButton.enabled = hasSelection;
	[self updateTitleBarForSelectionState];
}

- (void)favoriteSelected {
	NSArray<IMAsset *> *assets = self.selectedAssets.allValues;
	[IMBulkAssetActions favoriteAssets:assets
	              presentingController:self
	                         completion:^(BOOL success) {
		    [self toggleSelecting];
	    }];
}

- (void)deleteSelected {
	NSArray<IMAsset *> *assets = self.selectedAssets.allValues;
	__weak typeof(self) weakSelf = self;
	[IMBulkAssetActions confirmDeleteAssets:assets
	                   presentingController:self
	                              completion:^(BOOL deleted) {
		    typeof(self) strongSelf = weakSelf;
		    if (deleted && strongSelf) {
			    [strongSelf toggleSelecting];
			    [strongSelf pullToRefresh];
		    }
	    }];
}

- (void)downloadSelected {
	NSArray<IMAsset *> *assets = self.selectedAssets.allValues;
	[IMBulkAssetActions downloadAssets:assets
	              presentingController:self
	                         completion:^{
		    [self toggleSelecting];
	    }];
}

- (void)addSelectedToAlbum {
	NSArray<IMAsset *> *assets = self.selectedAssets.allValues;
	[self toggleSelecting];
	[IMBulkAssetActions presentAddToAlbumForAssets:assets presentingController:self];
}

#pragma mark - Bucket loading (server)

- (void)loadCachedBuckets {
	NSArray<NSString *> *dates;
	NSArray<NSNumber *> *counts;
	[[IMDatabase shared] cachedBucketDates:&dates counts:&counts];
	if (dates.count > 0) {
		self.serverBucketCounts = [NSDictionary dictionaryWithObjects:counts forKeys:dates];
		[self recomputeBucketDates];
	}
}

- (void)pullToRefresh {
	[self.bucketAssets removeAllObjects];
	[self refreshBuckets];
	[self refreshLocalPendingAssets];
	[self refreshAssetStatistics];
}

- (void)refreshBuckets {
	__weak typeof(self) weakSelf = self;
	[IMAssetApi timeBucketsWithCompletion:^(NSArray<NSString *> *_Nullable bucketDates,
	                                         NSArray<NSNumber *> *_Nullable counts, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[strongSelf.refreshControl endRefreshing];
		if (error || !bucketDates) {
			if (strongSelf.bucketDates.count == 0) {
				strongSelf.emptyLabel.text = _(@"Couldn't load timeline. Tap to retry.");
				strongSelf.emptyLabel.hidden = NO;
			}
			return;
		}
		strongSelf.emptyLabel.text = _(@"No photos yet.");
		strongSelf.serverBucketCounts = [NSDictionary dictionaryWithObjects:counts forKeys:bucketDates];
		[[IMDatabase shared] replaceBucketDates:bucketDates counts:counts];
		[strongSelf recomputeBucketDates];
	}];
}

- (void)recomputeBucketDates {
	NSMutableSet<NSString *> *allBuckets = [NSMutableSet setWithArray:self.serverBucketCounts.allKeys];
	[allBuckets addObjectsFromArray:self.localItemsByBucket.allKeys];
	self.bucketDates = [allBuckets.allObjects sortedArrayUsingSelector:@selector(compare:)];
	[self.collectionView reloadData];
	[self updateEmptyState];
	if (!self.hasScrolledToNewest && self.bucketDates.count > 0) {
		self.hasScrolledToNewest = YES;
		[self scrollToNewestAnimated:NO];
	}
	[self updateFooterLabel];
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[weakSelf updateTitleBarForScrollPosition];
	});
}

- (void)scrollToNewestAnimated:(BOOL)animated {
	[self.collectionView layoutIfNeeded];
	UIEdgeInsets insets = self.collectionView.contentInset;
	if (@available(iOS 11.0, *)) {
		insets = self.collectionView.adjustedContentInset;
	}
	CGFloat minOffset = -insets.top;
	CGFloat maxOffset = self.collectionView.contentSize.height + insets.bottom -
	                    self.collectionView.bounds.size.height - kFooterHeight;
	[self.collectionView setContentOffset:CGPointMake(0, MAX(minOffset, maxOffset)) animated:animated];
}

- (void)refreshAssetStatistics {
	__weak typeof(self) weakSelf = self;
	[IMAssetApi assetStatisticsWithCompletion:^(NSInteger images, NSInteger videos, NSError *_Nullable error) {
		if (error) {
			return;
		}
		typeof(self) strongSelf = weakSelf;
		strongSelf.statsImageCount = images;
		strongSelf.statsVideoCount = videos;
		[strongSelf updateFooterLabel];
	}];
}

- (void)updateFooterLabel {
	if (self.statsImageCount + self.statsVideoCount > 0) {
		static NSNumberFormatter *formatter;
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			formatter = [[NSNumberFormatter alloc] init];
			formatter.numberStyle = NSNumberFormatterDecimalStyle;
		});
		self.footerLabel.text = [NSString stringWithFormat:_(@"%@ Photos, %@ Videos"),
		                                                    [formatter stringFromNumber:@(self.statsImageCount)],
		                                                    [formatter stringFromNumber:@(self.statsVideoCount)]];
	} else {
		self.footerLabel.text = @"";
	}
	self.footerLabel.hidden = self.clusterMode || self.bucketDates.count == 0;
	CGSize contentSize = self.collectionView.collectionViewLayout.collectionViewContentSize;
	self.footerLabel.frame = CGRectMake(0, contentSize.height - kFooterHeight, contentSize.width, kFooterHeight);
}

- (void)updateEmptyState {
	self.emptyLabel.hidden = self.bucketDates.count > 0;
}

- (void)loadBucketIfNeeded:(NSString *)bucket {
	if (self.bucketAssets[bucket] || [self.loadingBuckets containsObject:bucket] ||
	    self.serverBucketCounts[bucket] == nil) {
		return;
	}

	NSArray<IMAsset *> *cached = [[IMDatabase shared] cachedAssetsForTimeBucket:bucket];
	if (cached.count > 0) {
		self.bucketAssets[bucket] = cached.reverseObjectEnumerator.allObjects;
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
		    strongSelf.bucketAssets[bucket] = assets.reverseObjectEnumerator.allObjects;
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
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		[weakSelf updateTitleBarForScrollPosition];
	});
}

#pragma mark - Bucket title formatting (cluster cell)

- (NSString *)monthTitleForBucket:(NSString *)bucket {
	NSDate *date = [self.headerDateFormatter dateFromString:bucket];
	if (!date) {
		return bucket;
	}
	static NSDateFormatter *titleFormatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		titleFormatter = [[NSDateFormatter alloc] init];
		titleFormatter.dateFormat = @"MMMM yyyy";
		titleFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	});
	return [titleFormatter stringFromDate:date];
}

- (NSInteger)yearOfBucket:(NSString *)bucket {
	NSDate *date = [self.headerDateFormatter dateFromString:bucket];
	if (!date) {
		return 0;
	}
	static NSCalendar *calendar;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
		calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	});
	return [calendar component:NSCalendarUnitYear fromDate:date];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	return self.clusterMode ? 1 : (NSInteger)self.bucketDates.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	if (self.clusterMode) {
		return self.bucketDates.count;
	}
	NSString *bucket = self.bucketDates[section];
	return [self serverCountForBucket:bucket] + (NSInteger)self.localItemsByBucket[bucket].count;
}

- (NSInteger)serverCountForBucket:(NSString *)bucket {
	NSArray<IMAsset *> *loaded = self.bucketAssets[bucket];
	return loaded ? (NSInteger)loaded.count : self.serverBucketCounts[bucket].integerValue;
}

- (nullable IMAsset *)loadedServerAssetAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section < 0 || indexPath.section >= (NSInteger)self.bucketDates.count) {
		return nil;
	}
	NSString *bucket = self.bucketDates[indexPath.section];
	NSArray<IMAsset *> *assets = self.bucketAssets[bucket];
	if (!assets || indexPath.item >= (NSInteger)assets.count) {
		return nil;
	}
	return assets[indexPath.item];
}

- (nullable IMTimelineLocalItem *)localItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section < 0 || indexPath.section >= (NSInteger)self.bucketDates.count) {
		return nil;
	}
	NSString *bucket = self.bucketDates[indexPath.section];
	NSInteger localIndex = indexPath.item - [self serverCountForBucket:bucket];
	NSArray<IMTimelineLocalItem *> *localItems = self.localItemsByBucket[bucket];
	if (localIndex < 0 || localIndex >= (NSInteger)localItems.count) {
		return nil;
	}
	return localItems[localIndex];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                   cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	if (self.clusterMode) {
		return [self clusterCellAt:indexPath inCollectionView:collectionView];
	}

	TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier
	                                                                forIndexPath:indexPath];
	NSString *bucket = self.bucketDates[indexPath.section];
	IMTimelineLocalItem *localItem = [self localItemAtIndexPath:indexPath];
	if (localItem) {
		[cell configureWithLocalAsset:localItem.asset syncState:localItem.state];
		cell.selectionModeEnabled = NO; 
		return cell;
	}

	IMAsset *asset = [self loadedServerAssetAtIndexPath:indexPath];
	if (asset) {
		[cell configureWithAsset:asset];
		cell.selectionModeEnabled = self.selecting;
	} else {
		[cell configureWithAsset:nil];
		cell.selectionModeEnabled = NO;
		[self loadBucketIfNeeded:bucket];
	}
	return cell;
}

- (IMClusterCell *)clusterCellAt:(NSIndexPath *)indexPath inCollectionView:(UICollectionView *)collectionView {
	IMClusterCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:IMClusterCellReuseIdentifier
	                                                                 forIndexPath:indexPath];
	NSString *bucket = self.bucketDates[indexPath.item];
	NSString *title = [self monthTitleForBucket:bucket];
	NSArray<IMTimelineLocalItem *> *localItems = self.localItemsByBucket[bucket];
	NSArray<IMAsset *> *serverAssets = self.bucketAssets[bucket];
	NSInteger count = (serverAssets ? (NSInteger)serverAssets.count : self.serverBucketCounts[bucket].integerValue) + localItems.count;

	if (localItems.count > 0) {
		[cell configureWithTitle:title count:count coverLocalAsset:localItems.lastObject.asset];
		return cell;
	}
	if (serverAssets.count > 0) {
		[cell configureWithTitle:title count:count coverAssetId:serverAssets.lastObject.assetId];
		return cell;
	}
	[cell configureWithTitle:title count:count coverAssetId:nil];
	[self loadBucketIfNeeded:bucket];
	return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (self.clusterMode) {
		[collectionView deselectItemAtIndexPath:indexPath animated:YES];
		[self exitClusterModeAndJumpToBucketIndex:indexPath.item];
		return;
	}

	NSString *bucket = self.bucketDates[indexPath.section];
	IMAsset *asset = [self loadedServerAssetAtIndexPath:indexPath];

	if (!self.selecting) {
		[collectionView deselectItemAtIndexPath:indexPath animated:YES];
		if (!asset) {
			return;
		}
		AssetViewController *viewer = [AssetViewController viewerWithAssets:self.bucketAssets[bucket]
		                                                        startIndex:indexPath.item];
		[self presentViewController:viewer animated:YES completion:nil];
		return;
	}

	if (!asset) {
		[collectionView deselectItemAtIndexPath:indexPath animated:NO];
		return;
	}
	self.selectedAssets[asset.assetId] = asset;
	[self updateSelectionToolbarState];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.selecting) {
		return;
	}
	IMAsset *asset = [self loadedServerAssetAtIndexPath:indexPath];
	if (!asset) {
		return;
	}
	[self.selectedAssets removeObjectForKey:asset.assetId];
	[self updateSelectionToolbarState];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	[self updateTitleBarForScrollPosition];
}

#pragma mark - Pinch-to-zoom (Phase 9)

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
	switch (gesture.state) {
		case UIGestureRecognizerStateBegan:
			[self endZoomSettle];
			self.pinchStartColumns = self.clusterMode ? kColumnSteps[kColumnStepCount - 1] : kColumnSteps[self.columnStepIndex];
			self.pinchColumns = self.pinchStartColumns;
			[self captureZoomAnchorForGesture:gesture];
			break;

		case UIGestureRecognizerStateChanged: {
			if (self.clusterMode) {
				if (gesture.scale >= kClusterExitPinchScale) {
					self.clusterMode = NO;
					self.columnStepIndex = kColumnStepCount - 1;
					[self applyColumnStepIndex:self.columnStepIndex];
					[self animateModeTransitionZoomingOut:NO thenScrollToBucket:nil];
				}
				return;
			}
			CGFloat minColumns = kColumnSteps[0];
			CGFloat maxColumns = kColumnSteps[kColumnStepCount - 1];
			CGFloat rawColumns = self.pinchStartColumns / gesture.scale;
			if (rawColumns > maxColumns * kClusterEnterOvershoot) {
				self.clusterMode = YES;
				[self animateModeTransitionZoomingOut:YES thenScrollToBucket:nil];
				return;
			}
			self.pinchColumns = MAX(minColumns, MIN(rawColumns, maxColumns));
			self.zoomAnchorViewY = [gesture locationInView:self.collectionView].y - self.collectionView.contentOffset.y;
			[self applyZoomForColumns:self.pinchColumns];
			break;
		}

		case UIGestureRecognizerStateEnded:
		case UIGestureRecognizerStateCancelled:
			if (!self.clusterMode) {
				[self settleZoomToNearestColumnStep];
			}
			break;

		default:
			break;
	}
}

- (void)applyZoomForColumns:(CGFloat)columns {
	NSInteger lowIndex = 0;
	while (lowIndex + 1 < kColumnStepCount && kColumnSteps[lowIndex + 1] <= columns) {
		lowIndex++;
	}
	NSInteger highIndex = MIN(lowIndex + 1, kColumnStepCount - 1);
	CGFloat low = kColumnSteps[lowIndex];
	CGFloat high = kColumnSteps[highIndex];
	CGFloat progress = 0;
	if (high > low) {
		progress = (log(columns) - log(low)) / (log(high) - log(low));
		progress = MAX(0, MIN(1, progress));
	}
	self.zoomLowIndex = lowIndex;
	self.zoomHighIndex = highIndex;
	self.liveColumns = columns;
	[self.gridLayout setFromColumns:kColumnSteps[lowIndex] toColumns:kColumnSteps[highIndex] progress:progress];
	[self relayoutGridKeepingZoomAnchor];
	[self updateTitleBarForScrollPosition];
}

- (IMTimelineGridLayout *)gridLayout {
	return (IMTimelineGridLayout *)self.collectionView.collectionViewLayout;
}

- (void)applyColumnStepIndex:(NSInteger)index {
	self.zoomLowIndex = index;
	self.zoomHighIndex = index;
	self.liveColumns = kColumnSteps[index];
	[self.gridLayout setFromColumns:kColumnSteps[index] toColumns:kColumnSteps[index] progress:0];
}

- (void)settleZoomToNearestColumnStep {
	CGFloat progress = self.gridLayout.progress;
	BOOL toHigh = progress >= 0.5;
	self.columnStepIndex = toHigh ? self.zoomHighIndex : self.zoomLowIndex;
	self.zoomSettleFrom = progress;
	self.zoomSettleTo = toHigh ? 1 : 0;
	if (fabs(self.zoomSettleTo - self.zoomSettleFrom) < 0.001) {
		[self endZoomSettle];
		return;
	}
	self.zoomSettleStartTime = CACurrentMediaTime();
	self.zoomSettleDuration = 0.1 + 0.2 * fabs(self.zoomSettleTo - self.zoomSettleFrom);
	self.zoomSettleLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(zoomSettleTick:)];
	[self.zoomSettleLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)zoomSettleTick:(CADisplayLink *)link {
	CGFloat elapsed = (CGFloat)(CACurrentMediaTime() - self.zoomSettleStartTime);
	CGFloat t = self.zoomSettleDuration > 0 ? elapsed / self.zoomSettleDuration : 1;
	if (t >= 1) {
		[self endZoomSettle];
		return;
	}
	CGFloat eased = 1 - pow(1 - t, 3); 
	CGFloat progress = self.zoomSettleFrom + (self.zoomSettleTo - self.zoomSettleFrom) * eased;
	CGFloat low = kColumnSteps[self.zoomLowIndex];
	CGFloat high = kColumnSteps[self.zoomHighIndex];
	self.liveColumns = exp(log(low) + (log(high) - log(low)) * progress);
	[self.gridLayout setFromColumns:kColumnSteps[self.zoomLowIndex]
	                      toColumns:kColumnSteps[self.zoomHighIndex]
	                       progress:progress];
	[self relayoutGridKeepingZoomAnchor];
	[self updateTitleBarForScrollPosition];
}

- (void)endZoomSettle {
	[self.zoomSettleLink invalidate];
	self.zoomSettleLink = nil;
	if (self.clusterMode) {
		return;
	}
	[self applyColumnStepIndex:self.columnStepIndex];
	[self relayoutGridKeepingZoomAnchor];
	self.zoomAnchorIndexPath = nil;
	[self updateTitleBarForScrollPosition];
}

- (NSInteger)nearestColumnStepIndexTo:(CGFloat)columns {
	NSInteger bestIndex = 0;
	CGFloat bestDiff = CGFLOAT_MAX;
	for (NSInteger i = 0; i < kColumnStepCount; i++) {
		CGFloat diff = fabs(columns - kColumnSteps[i]);
		if (diff < bestDiff) {
			bestDiff = diff;
			bestIndex = i;
		}
	}
	return bestIndex;
}

- (BOOL)isDenseGridMode {
	return kColumnSteps[[self nearestColumnStepIndexTo:self.liveColumns]] >= kDenseGridMinColumns;
}

- (void)captureZoomAnchorForGesture:(UIPinchGestureRecognizer *)gesture {
	CGPoint point = [gesture locationInView:self.collectionView]; 
	self.zoomAnchorViewY = point.y - self.collectionView.contentOffset.y;
	NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
	if (!indexPath) {
		CGFloat bestDistance = CGFLOAT_MAX;
		for (UICollectionViewCell *cell in self.collectionView.visibleCells) {
			CGFloat distance = fabs(CGRectGetMidY(cell.frame) - point.y);
			if (distance < bestDistance) {
				bestDistance = distance;
				indexPath = [self.collectionView indexPathForCell:cell];
			}
		}
	}
	self.zoomAnchorIndexPath = indexPath;
	self.zoomAnchorFraction = 0.5;
	if (indexPath) {
		UICollectionViewLayoutAttributes *attributes =
		    [self.collectionView.collectionViewLayout layoutAttributesForItemAtIndexPath:indexPath];
		if (attributes && attributes.frame.size.height > 0) {
			CGFloat fraction = (point.y - CGRectGetMinY(attributes.frame)) / attributes.frame.size.height;
			self.zoomAnchorFraction = MAX(0, MIN(1, fraction));
		}
	}
}

- (void)relayoutGridKeepingZoomAnchor {
	[self.collectionView.collectionViewLayout invalidateLayout];
	[self.collectionView layoutIfNeeded];
	NSIndexPath *anchor = self.zoomAnchorIndexPath;
	if (!anchor || anchor.section >= self.collectionView.numberOfSections ||
	    anchor.item >= [self.collectionView numberOfItemsInSection:anchor.section]) {
		return;
	}
	UICollectionViewLayoutAttributes *attributes =
	    [self.collectionView.collectionViewLayout layoutAttributesForItemAtIndexPath:anchor];
	if (!attributes) {
		return;
	}
	CGFloat anchorContentY = CGRectGetMinY(attributes.frame) + self.zoomAnchorFraction * attributes.frame.size.height;
	UIEdgeInsets insets = self.collectionView.contentInset;
	if (@available(iOS 11.0, *)) {
		insets = self.collectionView.adjustedContentInset;
	}
	CGFloat minOffset = -insets.top;
	CGFloat maxOffset = MAX(minOffset,
	                        self.collectionView.contentSize.height + insets.bottom - self.collectionView.bounds.size.height);
	CGFloat offsetY = MAX(minOffset, MIN(maxOffset, anchorContentY - self.zoomAnchorViewY));
	self.collectionView.contentOffset = CGPointMake(0, offsetY);
	[self.collectionView layoutIfNeeded];
	[self updateFooterLabel]; 
}

- (void)exitClusterModeAndJumpToBucketIndex:(NSInteger)bucketIndex {
	NSString *bucket = (bucketIndex >= 0 && bucketIndex < (NSInteger)self.bucketDates.count) ? self.bucketDates[bucketIndex] : nil;
	self.clusterMode = NO;
	self.columnStepIndex = kColumnStepCount - 1;
	[self applyColumnStepIndex:self.columnStepIndex];
	[self animateModeTransitionZoomingOut:NO thenScrollToBucket:bucket];
}

- (void)animateModeTransitionZoomingOut:(BOOL)zoomingOut thenScrollToBucket:(nullable NSString *)bucket {
	self.selectButton.enabled = !self.clusterMode;

	UIView *snapshot = [self.collectionView snapshotViewAfterScreenUpdates:NO];
	snapshot.frame = self.collectionView.frame;
	[self.view insertSubview:snapshot aboveSubview:self.collectionView];

	CGFloat outgoingScale = zoomingOut ? 1.15 : 0.85;
	CGFloat incomingStartScale = zoomingOut ? 0.85 : 1.15;

	self.collectionView.alpha = 0;
	self.collectionView.transform = CGAffineTransformMakeScale(incomingStartScale, incomingStartScale);
	[self endZoomSettle];
	self.gridLayout.rowMode = self.clusterMode;
	self.gridLayout.footerHeight = self.clusterMode ? 0 : kFooterHeight;
	if (!self.clusterMode) {
		[self applyColumnStepIndex:self.columnStepIndex];
	}
	[self updateFooterLabel];
	[self.collectionView.collectionViewLayout invalidateLayout];
	[self.collectionView reloadData];

	__weak typeof(self) weakSelf = self;
	[UIView animateWithDuration:0.3
	                       delay:0
	                     options:UIViewAnimationOptionCurveEaseInOut
	                  animations:^{
		    snapshot.alpha = 0;
		    snapshot.transform = CGAffineTransformMakeScale(outgoingScale, outgoingScale);
		    weakSelf.collectionView.alpha = 1;
		    weakSelf.collectionView.transform = CGAffineTransformIdentity;
	    }
	                  completion:^(BOOL finished) {
		    [snapshot removeFromSuperview];
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    if (bucket) {
			    NSUInteger section = [strongSelf.bucketDates indexOfObject:bucket];
			    if (section != NSNotFound && (NSInteger)section < strongSelf.collectionView.numberOfSections) {
				    [strongSelf.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]
				                                        atScrollPosition:UICollectionViewScrollPositionTop
				                                                animated:YES];
			    }
		    }
		    [strongSelf updateTitleBarForScrollPosition];
	    }];
}

#pragma mark - Floating title (Phase 9)

- (void)setUpTitleBar {
	self.titleScrimLayer = [CAGradientLayer layer];
	self.titleScrimLayer.colors = @[
		(id)[UIColor colorWithWhite:0 alpha:0.78].CGColor,
		(id)[UIColor colorWithWhite:0 alpha:0.55].CGColor,
		(id)[UIColor colorWithWhite:0 alpha:0].CGColor,
	];
	self.titleScrimLayer.locations = @[ @0, @0.6, @1 ];
	UIView *scrimView = [[UIView alloc] init];
	scrimView.translatesAutoresizingMaskIntoConstraints = NO;
	scrimView.userInteractionEnabled = NO;
	[scrimView.layer addSublayer:self.titleScrimLayer];
	[self.view addSubview:scrimView];
	self.titleScrimView = scrimView;

	self.dateRangeLabel = [[UILabel alloc] init];
	self.dateRangeLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.dateRangeLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
	self.dateRangeLabel.textAlignment = NSTextAlignmentLeft;
	self.dateRangeLabel.textColor = UIColor.whiteColor;
	self.dateRangeLabel.adjustsFontSizeToFitWidth = YES;
	self.dateRangeLabel.minimumScaleFactor = 0.6;
	[self.view addSubview:self.dateRangeLabel];

	self.locationLabel = [[UILabel alloc] init];
	self.locationLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.locationLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
	self.locationLabel.textAlignment = NSTextAlignmentLeft;
	self.locationLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.95];
	[self.view addSubview:self.locationLabel];

	UIVisualEffectView *pill = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
	pill.translatesAutoresizingMaskIntoConstraints = NO;
	pill.layer.cornerRadius = 15;
	pill.clipsToBounds = YES;
	[self.view addSubview:pill];
	self.selectPillView = pill;

	self.selectButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.selectButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.selectButton setTitle:_(@"Select") forState:UIControlStateNormal];
	[self.selectButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	self.selectButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	[self.selectButton addTarget:self action:@selector(toggleSelecting) forControlEvents:UIControlEventTouchUpInside];
	[pill.contentView addSubview:self.selectButton];

	[NSLayoutConstraint activateConstraints:@[
		[self.titleScrimView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.titleScrimView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.titleScrimView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.titleScrimView.bottomAnchor constraintEqualToAnchor:self.locationLabel.bottomAnchor constant:14],

		[pill.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
		[pill.topAnchor constraintEqualToAnchor:self.dateRangeLabel.topAnchor constant:2],
		[pill.heightAnchor constraintEqualToConstant:32],

		[self.selectButton.leadingAnchor constraintEqualToAnchor:pill.contentView.leadingAnchor constant:14],
		[self.selectButton.trailingAnchor constraintEqualToAnchor:pill.contentView.trailingAnchor constant:-14],
		[self.selectButton.topAnchor constraintEqualToAnchor:pill.contentView.topAnchor],
		[self.selectButton.bottomAnchor constraintEqualToAnchor:pill.contentView.bottomAnchor],

		[self.dateRangeLabel.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
		[self.dateRangeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:pill.leadingAnchor constant:-8],
		[self.dateRangeLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
		[self.dateRangeLabel.heightAnchor constraintEqualToConstant:34],

		[self.locationLabel.leadingAnchor constraintEqualToAnchor:self.dateRangeLabel.leadingAnchor],
		[self.locationLabel.trailingAnchor constraintLessThanOrEqualToAnchor:pill.leadingAnchor constant:-8],
		[self.locationLabel.topAnchor constraintEqualToAnchor:self.dateRangeLabel.bottomAnchor constant:0],
		[self.locationLabel.heightAnchor constraintEqualToConstant:20],
	]];
}

- (void)updateTitleBarForSelectionState {
	if (self.selecting) {
		NSInteger n = self.selectedAssets.count;
		self.dateRangeLabel.text = n > 0 ? [NSString stringWithFormat:_(@"%ld Selected"), (long)n] : _(@"Select Items");
		self.locationLabel.hidden = YES;
		[self.selectButton setTitle:_(@"Cancel") forState:UIControlStateNormal];
	} else {
		[self.selectButton setTitle:_(@"Select") forState:UIControlStateNormal];
		self.locationLabel.hidden = NO;
		[self updateTitleBarForScrollPosition];
	}
}

- (void)updateTitleBarForScrollPosition {
	if (self.selecting) {
		return;
	}
	if (self.bucketDates.count == 0) {
		self.dateRangeLabel.text = @"";
		self.locationLabel.hidden = YES;
		[self removeAllDenseBadges];
		return;
	}

	NSArray<NSIndexPath *> *visible = [self sortedVisibleIndexPaths];
	if (visible.count == 0) {
		if (self.dateRangeLabel.text.length == 0) {
			self.dateRangeLabel.text = [self monthTitleForBucket:self.bucketDates.lastObject];
			self.locationLabel.hidden = YES;
			[self removeAllDenseBadges];
		}
		return;
	}

	if (self.clusterMode) {
		NSString *oldest = [self monthTitleForBucket:self.bucketDates[visible.firstObject.item]];
		NSString *newest = [self monthTitleForBucket:self.bucketDates[visible.lastObject.item]];
		self.dateRangeLabel.text = [newest isEqualToString:oldest] ? newest : [NSString stringWithFormat:@"%@ - %@", oldest, newest];
		self.locationLabel.hidden = YES;
		[self removeAllDenseBadges];
		return;
	}

	if ([self isDenseGridMode]) {
		self.dateRangeLabel.text = @"";
		self.locationLabel.hidden = YES;
		[self updateDenseBadges];
		return;
	}
	[self removeAllDenseBadges];

	if (kColumnSteps[[self nearestColumnStepIndexTo:self.liveColumns]] < 3) {
		NSDate *majorityDate = [self majorityDateAmongVisible:visible];
		self.dateRangeLabel.text = [self formattedRangeFrom:majorityDate to:majorityDate];
	} else {
		NSDate *oldestDate = [self nearestDateAmongVisible:visible fromTop:YES];
		NSDate *newestDate = [self nearestDateAmongVisible:visible fromTop:NO];
		self.dateRangeLabel.text = [self formattedRangeFrom:oldestDate to:newestDate];
	}

	NSString *location = [self nearestLocationAmongVisible:visible];
	self.locationLabel.text = location;
	self.locationLabel.hidden = (location.length == 0);
}

- (nullable NSDate *)majorityDateAmongVisible:(NSArray<NSIndexPath *> *)sortedVisible {
	NSCalendar *calendar = [NSCalendar currentCalendar];
	NSMutableDictionary<NSDate *, NSNumber *> *countsByDay = [NSMutableDictionary dictionary];
	NSDate *bestDay = nil;
	NSInteger bestCount = 0;
	for (NSIndexPath *indexPath in sortedVisible) {
		NSDate *date = [self dateAtIndexPath:indexPath];
		if (!date) {
			continue;
		}
		NSDate *dayStart = [calendar startOfDayForDate:date];
		NSInteger count = countsByDay[dayStart].integerValue + 1;
		countsByDay[dayStart] = @(count);
		if (count > bestCount) {
			bestCount = count;
			bestDay = dayStart;
		}
	}
	return bestDay;
}

- (NSArray<NSIndexPath *> *)sortedVisibleIndexPaths {
	return [[self.collectionView indexPathsForVisibleItems] sortedArrayUsingComparator:^NSComparisonResult(NSIndexPath *a, NSIndexPath *b) {
		if (a.section != b.section) {
			return a.section < b.section ? NSOrderedAscending : NSOrderedDescending;
		}
		if (a.item != b.item) {
			return a.item < b.item ? NSOrderedAscending : NSOrderedDescending;
		}
		return NSOrderedSame;
	}];
}

- (nullable NSDate *)nearestDateAmongVisible:(NSArray<NSIndexPath *> *)sortedVisible fromTop:(BOOL)fromTop {
	NSEnumerator<NSIndexPath *> *e = fromTop ? sortedVisible.objectEnumerator : sortedVisible.reverseObjectEnumerator;
	for (NSIndexPath *indexPath in e) {
		NSDate *date = [self dateAtIndexPath:indexPath];
		if (date) {
			return date;
		}
	}
	return nil;
}

- (nullable NSString *)nearestLocationAmongVisible:(NSArray<NSIndexPath *> *)sortedVisible {
	for (NSIndexPath *indexPath in sortedVisible) {
		NSString *location = [self locationStringForAsset:[self loadedServerAssetAtIndexPath:indexPath]];
		if (location.length > 0) {
			return location;
		}
	}
	return nil;
}

- (nullable NSDate *)dateAtIndexPath:(NSIndexPath *)indexPath {
	IMTimelineLocalItem *localItem = [self localItemAtIndexPath:indexPath];
	if (localItem) {
		return localItem.asset.creationDate;
	}
	IMAsset *asset = [self loadedServerAssetAtIndexPath:indexPath];
	return asset ? IMDateFromServerTimestamp(asset.fileCreatedAt) : nil;
}

- (NSString *)formattedRangeFrom:(nullable NSDate *)from to:(nullable NSDate *)to {
	if (!from && !to) {
		return @"";
	}
	from = from ?: to;
	to = to ?: from;

	static NSDateFormatter *monthDayFormatter; 
	static NSDateFormatter *monthFormatter;    
	static NSCalendar *calendar;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		monthDayFormatter = [[NSDateFormatter alloc] init];
		monthDayFormatter.dateFormat = @"MMM d";
		monthFormatter = [[NSDateFormatter alloc] init];
		monthFormatter.dateFormat = @"MMM";
		calendar = [NSCalendar currentCalendar];
	});

	NSInteger fromYear = [calendar component:NSCalendarUnitYear fromDate:from];
	NSInteger toYear = [calendar component:NSCalendarUnitYear fromDate:to];
	NSInteger fromMonth = [calendar component:NSCalendarUnitMonth fromDate:from];
	NSInteger toMonth = [calendar component:NSCalendarUnitMonth fromDate:to];
	NSInteger fromDay = [calendar component:NSCalendarUnitDay fromDate:from];
	NSInteger toDay = [calendar component:NSCalendarUnitDay fromDate:to];

	if (fromYear == toYear && fromMonth == toMonth && fromDay == toDay) {
		return [NSString stringWithFormat:@"%@, %ld", [monthDayFormatter stringFromDate:from], (long)toYear];
	}
	if (fromYear == toYear && fromMonth == toMonth) {
		return [NSString stringWithFormat:@"%@ %ld-%ld, %ld", [monthFormatter stringFromDate:from], (long)fromDay, (long)toDay, (long)toYear];
	}
	if (fromYear == toYear) {
		return [NSString stringWithFormat:@"%@ - %@, %ld", [monthDayFormatter stringFromDate:from], [monthDayFormatter stringFromDate:to], (long)toYear];
	}
	return [NSString stringWithFormat:@"%@, %ld - %@, %ld", [monthDayFormatter stringFromDate:from], (long)fromYear, [monthDayFormatter stringFromDate:to], (long)toYear];
}

- (nullable NSString *)locationStringForAsset:(nullable IMAsset *)asset {
	if (!asset) {
		return nil;
	}
	if (asset.city.length > 0 && asset.country.length > 0) {
		return [NSString stringWithFormat:@"%@, %@", asset.city, asset.country];
	}
	if (asset.city.length > 0) {
		return asset.city;
	}
	return asset.country.length > 0 ? asset.country : nil;
}

#pragma mark - Dense-grid month/year badges (11/23 columns, Phase 9)

- (void)updateDenseBadges {
	BOOL isYearOnly = kColumnSteps[[self nearestColumnStepIndexTo:self.liveColumns]] >= 23;
	CGFloat marginFactor = isYearOnly ? 0.9 : 0.5;
	CGFloat spanFactor = isYearOnly ? 3.25 : 2.5;

	CGRect visibleBounds = self.collectionView.bounds;
	NSMutableSet<NSString *> *neededBuckets = [NSMutableSet set];

	for (NSInteger section = 0; section < (NSInteger)self.bucketDates.count; section++) {
		if (isYearOnly && section > 0 &&
		    [self yearOfBucket:self.bucketDates[section]] == [self yearOfBucket:self.bucketDates[section - 1]]) {
			continue;
		}
		NSIndexPath *firstItem = [NSIndexPath indexPathForItem:0 inSection:section];
		UICollectionViewLayoutAttributes *attrs = [self.collectionView layoutAttributesForItemAtIndexPath:firstItem];
		if (!attrs || !CGRectIntersectsRect(attrs.frame, visibleBounds)) {
			continue;
		}
		NSString *bucket = self.bucketDates[section];
		[neededBuckets addObject:bucket];

		CGFloat cellWidth = attrs.frame.size.width;
		CGRect badgeFrame = CGRectMake(attrs.frame.origin.x + marginFactor * cellWidth,
		                                attrs.frame.origin.y + 6,
		                                spanFactor * cellWidth,
		                                26);

		UILabel *badge = self.denseBadgeViewsByBucket[bucket];
		if (!badge) {
			badge = [self makeDenseBadgeLabel];
			self.denseBadgeViewsByBucket[bucket] = badge;
			[self.collectionView addSubview:badge];
		}
		badge.attributedText = isYearOnly ? [self yearOnlyBadgeTextForBucket:bucket] : [self monthYearBadgeTextForBucket:bucket];
		badge.frame = badgeFrame;
		[self.collectionView bringSubviewToFront:badge];
	}

	for (NSString *bucket in [self.denseBadgeViewsByBucket.allKeys copy]) {
		if (![neededBuckets containsObject:bucket]) {
			[self.denseBadgeViewsByBucket[bucket] removeFromSuperview];
			[self.denseBadgeViewsByBucket removeObjectForKey:bucket];
		}
	}
}

- (void)removeAllDenseBadges {
	if (self.denseBadgeViewsByBucket.count == 0) {
		return;
	}
	for (UILabel *badge in self.denseBadgeViewsByBucket.allValues) {
		[badge removeFromSuperview];
	}
	[self.denseBadgeViewsByBucket removeAllObjects];
}

- (UILabel *)makeDenseBadgeLabel {
	UILabel *badge = [[UILabel alloc] init];
	badge.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.9];
	badge.layer.cornerRadius = 5;
	badge.clipsToBounds = YES;
	badge.textAlignment = NSTextAlignmentCenter;
	badge.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	badge.adjustsFontSizeToFitWidth = YES;
	badge.minimumScaleFactor = 0.7;
	return badge;
}

- (NSAttributedString *)monthYearBadgeTextForBucket:(NSString *)bucket {
	NSDate *date = [self.headerDateFormatter dateFromString:bucket];
	static NSDateFormatter *monthFormatter;
	static NSDateFormatter *yearFormatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		monthFormatter = [[NSDateFormatter alloc] init];
		monthFormatter.dateFormat = @"MMM";
		monthFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		yearFormatter = [[NSDateFormatter alloc] init];
		yearFormatter.dateFormat = @"yyyy";
		yearFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	});
	NSString *month = date ? [monthFormatter stringFromDate:date] : @"";
	NSString *year = date ? [yearFormatter stringFromDate:date] : @"";
	NSString *combined = [NSString stringWithFormat:@"%@ %@", month, year];

	UIFont *font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:combined];
	[text addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, combined.length)];
	[text addAttribute:NSForegroundColorAttributeName value:UIColor.labelColor range:NSMakeRange(0, month.length)];
	[text addAttribute:NSForegroundColorAttributeName
	             value:[UIColor.labelColor colorWithAlphaComponent:0.5]
	             range:NSMakeRange(month.length, combined.length - month.length)];
	return text;
}

- (NSAttributedString *)yearOnlyBadgeTextForBucket:(NSString *)bucket {
	NSDate *date = [self.headerDateFormatter dateFromString:bucket];
	static NSDateFormatter *yearFormatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		yearFormatter = [[NSDateFormatter alloc] init];
		yearFormatter.dateFormat = @"yyyy";
		yearFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	});
	NSString *year = date ? [yearFormatter stringFromDate:date] : @"";
	return [[NSAttributedString alloc] initWithString:year
	                                        attributes:@{
		                                        NSForegroundColorAttributeName : UIColor.labelColor,
		                                        NSFontAttributeName : [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
	                                        }];
}

#pragma mark - Status bar

- (UIStatusBarStyle)preferredStatusBarStyle {
	return UIStatusBarStyleLightContent;
}

@end
