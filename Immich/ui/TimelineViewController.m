#import "TimelineViewController.h"
#import "TimelineCell.h"
#import "IMAssetApi.h"
#import "AssetViewController.h"
#import "IMBulkAssetActions.h"
#import "IMDatabase.h"
#import "IMPhotoLibrary.h"
#import "common.h"
#import <Photos/Photos.h>

static NSString *const kHeaderReuseIdentifier = @"TimelineHeader";
static const int64_t kLocalRefreshDebounceMs = 750;

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

@interface TimelineViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, PHPhotoLibraryChangeObserver>
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

@property (nonatomic) BOOL selecting;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IMAsset *> *selectedAssets;
@property (nonatomic, strong) UIBarButtonItem *favoriteButton;
@property (nonatomic, strong) UIBarButtonItem *addAlbumButton;
@property (nonatomic, strong) UIBarButtonItem *downloadButton;
@property (nonatomic, strong) UIBarButtonItem *deleteButton;
@end

@implementation TimelineViewController

static const NSInteger kColumns = 4;
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

		_headerDateFormatter = [[NSDateFormatter alloc] init];
		_headerDateFormatter.dateFormat = @"yyyy-MM-dd";
		_headerDateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	}
	return self;
}

- (void)dealloc {
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
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Select")
	                                                                           style:UIBarButtonItemStylePlain
	                                                                          target:self
	                                                                          action:@selector(toggleSelecting)];

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
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self scheduleLocalRefresh];
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
		for (NSString *bucket in grouped) {
			[grouped[bucket] setArray:[[grouped[bucket] reverseObjectEnumerator] allObjects]];
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
	self.navigationItem.rightBarButtonItem.title = self.selecting ? _(@"Cancel") : _(@"Select");
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
	if (self.selecting) {
		self.title = hasSelection ? [NSString stringWithFormat:_(@"%ld Selected"), (long)self.selectedAssets.count] : _(@"Select Items");
	} else {
		self.title = _(@"Timeline");
	}
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
	self.bucketDates = [[allBuckets.allObjects sortedArrayUsingSelector:@selector(compare:)] reverseObjectEnumerator].allObjects;
	[self.collectionView reloadData];
	[self updateEmptyState];
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
	NSString *bucket = self.bucketDates[section];
	NSArray<IMAsset *> *loadedServerAssets = self.bucketAssets[bucket];
	NSInteger serverCount = loadedServerAssets ? (NSInteger)loadedServerAssets.count : self.serverBucketCounts[bucket].integerValue;
	NSInteger localCount = self.localItemsByBucket[bucket].count;
	return serverCount + localCount;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                   cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier
	                                                                forIndexPath:indexPath];
	NSString *bucket = self.bucketDates[indexPath.section];
	NSArray<IMTimelineLocalItem *> *localItems = self.localItemsByBucket[bucket];
	NSInteger localCount = localItems.count;

	if (indexPath.item < localCount) {
		IMTimelineLocalItem *item = localItems[indexPath.item];
		[cell configureWithLocalAsset:item.asset syncState:item.state];
		cell.selectionModeEnabled = NO; 
		return cell;
	}

	NSInteger serverIndex = indexPath.item - localCount;
	NSArray<IMAsset *> *assets = self.bucketAssets[bucket];
	if (assets && serverIndex < (NSInteger)assets.count) {
		[cell configureWithAsset:assets[serverIndex]];
		cell.selectionModeEnabled = self.selecting;
	} else {
		[cell configureWithAsset:nil];
		cell.selectionModeEnabled = NO;
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

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	NSString *bucket = self.bucketDates[indexPath.section];
	NSInteger localCount = self.localItemsByBucket[bucket].count;

	if (!self.selecting) {
		[collectionView deselectItemAtIndexPath:indexPath animated:YES];
		if (indexPath.item < localCount) {
			return;
		}
		NSInteger serverIndex = indexPath.item - localCount;
		NSArray<IMAsset *> *assets = self.bucketAssets[bucket];
		if (!assets || serverIndex >= (NSInteger)assets.count) {
			return;
		}
		AssetViewController *viewer = [AssetViewController viewerWithAssets:assets startIndex:serverIndex];
		[self presentViewController:viewer animated:YES completion:nil];
		return;
	}

	if (indexPath.item < localCount) {
		[collectionView deselectItemAtIndexPath:indexPath animated:NO];
		return;
	}
	NSInteger serverIndex = indexPath.item - localCount;
	NSArray<IMAsset *> *assets = self.bucketAssets[bucket];
	if (!assets || serverIndex >= (NSInteger)assets.count) {
		return;
	}
	self.selectedAssets[assets[serverIndex].assetId] = assets[serverIndex];
	[self updateSelectionToolbarState];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.selecting) {
		return;
	}
	NSString *bucket = self.bucketDates[indexPath.section];
	NSInteger localCount = self.localItemsByBucket[bucket].count;
	if (indexPath.item < localCount) {
		return;
	}
	NSInteger serverIndex = indexPath.item - localCount;
	NSArray<IMAsset *> *assets = self.bucketAssets[bucket];
	if (!assets || serverIndex >= (NSInteger)assets.count) {
		return;
	}
	[self.selectedAssets removeObjectForKey:assets[serverIndex].assetId];
	[self updateSelectionToolbarState];
}

@end
