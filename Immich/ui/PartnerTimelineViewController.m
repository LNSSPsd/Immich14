#import "PartnerTimelineViewController.h"
#import "IMAssetApi.h"
#import "TimelineCell.h"
#import "AssetViewController.h"
#import "IMSession.h"
#import "common.h"

static const CGFloat kPartnerCellSpacing = 2.0;
static const NSInteger kPartnerColumns = 4;

static BOOL IMPartnerTimelineUUIDv4(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	return canonical.length == 36 && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

@interface PartnerTimelineViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) IMPartner *partner;
@property (nonatomic) BOOL aggregate;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<NSString *> *bucketDates;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *bucketCounts;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<IMAsset *> *> *bucketAssets;
@property (nonatomic, strong) NSMutableSet<NSString *> *loadingBuckets;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL loadingBucketsList;
@end

@implementation PartnerTimelineViewController

+ (instancetype)viewControllerWithPartner:(IMPartner *)partner {
	return [[self alloc] initWithPartner:partner];
}

+ (instancetype)aggregateViewController {
	PartnerTimelineViewController *vc = [[self alloc] initWithPartner:[[IMPartner alloc] init]];
	vc.aggregate = YES;
	return vc;
}

- (instancetype)initWithPartner:(IMPartner *)partner {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_partner = partner;
		_bucketDates = @[];
		_bucketCounts = @{};
		_bucketAssets = [NSMutableDictionary dictionary];
		_loadingBuckets = [NSMutableSet set];
	}
	return self;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
	return [self initWithPartner:[[IMPartner alloc] init]];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	return [self initWithPartner:[[IMPartner alloc] init]];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	NSString *name = self.partner.name.length ? self.partner.name : self.partner.email;
	self.title = self.aggregate ? _(@"Shared Partner Photos") : (name.length ? name : _(@"Partner Photos"));
	if (self.partner.email.length && ![self.partner.email isEqualToString:name]) self.navigationItem.prompt = self.partner.email;
	if (@available(iOS 13.0, *)) self.view.backgroundColor = UIColor.systemBackgroundColor;
	else self.view.backgroundColor = UIColor.whiteColor;

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = kPartnerCellSpacing;
	layout.minimumLineSpacing = kPartnerCellSpacing;
	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	self.collectionView.alwaysBounceVertical = YES;
	self.collectionView.backgroundColor = self.view.backgroundColor;
	[self.collectionView registerClass:[TimelineCell class] forCellWithReuseIdentifier:TimelineCellReuseIdentifier];
	[self.view addSubview:self.collectionView];

	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
	self.collectionView.refreshControl = self.refreshControl;

	self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.userInteractionEnabled = YES;
	if (@available(iOS 13.0, *)) self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	else self.emptyLabel.textColor = UIColor.grayColor;
	[self.emptyLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(refresh)]];
	[self.view addSubview:self.emptyLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
		[self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
	]];
	[self refresh];
}

- (void)dealloc {
	_generation += 1;
}

- (void)refresh {
	if (self.loadingBucketsList) {
		[self.refreshControl endRefreshing];
		return;
	}
	NSString *userId = self.aggregate ? IMSession.shared.userId : self.partner.partnerId;
	if (!IMPartnerTimelineUUIDv4(userId)) {
		self.emptyLabel.text = _(@"This partner has an invalid user identifier.");
		if (self.aggregate) self.emptyLabel.text = _(@"Sign in again to browse shared photos.");
		self.emptyLabel.hidden = NO;
		[self.refreshControl endRefreshing];
		return;
	}
	self.loadingBucketsList = YES;
	NSUInteger generation = ++self.generation;
	[self.bucketAssets removeAllObjects];
	[self.loadingBuckets removeAllObjects];
	self.bucketDates = @[];
	self.bucketCounts = @{};
	self.emptyLabel.text = _(@"Loading partner photos…");
	self.emptyLabel.hidden = NO;
	[self.collectionView reloadData];
	[self.refreshControl beginRefreshing];
	__weak typeof(self) weakSelf = self;
	[IMAssetApi timeBucketsForUserId:userId withPartners:self.aggregate completion:^(NSArray<NSString *> *dates, NSArray<NSNumber *> *counts, NSError *error) {
		PartnerTimelineViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		strongSelf.loadingBucketsList = NO;
		[strongSelf.refreshControl endRefreshing];
		if (error || !dates || dates.count != counts.count) {
			strongSelf.emptyLabel.text = error.localizedDescription.length ? error.localizedDescription : _(@"Couldn’t load this partner’s photos. Tap to retry.");
			strongSelf.emptyLabel.hidden = NO;
			[strongSelf.collectionView reloadData];
			return;
		}
		NSMutableDictionary<NSString *, NSNumber *> *mappedCounts = [NSMutableDictionary dictionaryWithCapacity:dates.count];
		for (NSUInteger index = 0; index < dates.count; index++) {
			NSString *date = dates[index];
			NSNumber *count = counts[index];
			if ([date isKindOfClass:[NSString class]] && date.length && [count isKindOfClass:[NSNumber class]]) mappedCounts[date] = count;
		}
		strongSelf.bucketDates = [mappedCounts.allKeys sortedArrayUsingSelector:@selector(compare:)];
		strongSelf.bucketCounts = mappedCounts;
		strongSelf.emptyLabel.text = strongSelf.bucketDates.count ? @"" : _(@"No shared photos yet.");
		strongSelf.emptyLabel.hidden = strongSelf.bucketDates.count > 0;
		[strongSelf.collectionView reloadData];
		if (strongSelf.bucketDates.count) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[strongSelf.collectionView layoutIfNeeded];
				NSInteger section = (NSInteger)strongSelf.bucketDates.count - 1;
				if (section >= 0 && [strongSelf.collectionView numberOfItemsInSection:section] > 0) {
					[strongSelf.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]
					                              atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
				}
			});
		}
	}];
}

- (void)loadBucketIfNeeded:(NSString *)bucket {
	NSString *userId = self.aggregate ? IMSession.shared.userId : self.partner.partnerId;
	if (bucket.length == 0 || self.bucketAssets[bucket] || [self.loadingBuckets containsObject:bucket] || !IMPartnerTimelineUUIDv4(userId)) return;
	[self.loadingBuckets addObject:bucket];
	NSUInteger generation = self.generation;
	__weak typeof(self) weakSelf = self;
	[IMAssetApi assetsInTimeBucket:bucket forUserId:userId withPartners:self.aggregate completion:^(NSArray<IMAsset *> *assets, NSError *error) {
		PartnerTimelineViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		[strongSelf.loadingBuckets removeObject:bucket];
		if (error || !assets) {
			if (strongSelf.bucketAssets.count == 0) {
				strongSelf.emptyLabel.text = error.localizedDescription.length ? error.localizedDescription : _(@"Couldn’t load this month’s photos.");
				strongSelf.emptyLabel.hidden = NO;
			}
			return;
		}
		strongSelf.bucketAssets[bucket] = assets.reverseObjectEnumerator.allObjects;
		strongSelf.emptyLabel.hidden = strongSelf.bucketDates.count > 0;
		[strongSelf.collectionView reloadData];
	}];
}

- (NSInteger)numberOfItemsForSection:(NSInteger)section {
	if (section < 0 || section >= (NSInteger)self.bucketDates.count) return 0;
	NSString *bucket = self.bucketDates[section];
	NSArray<IMAsset *> *assets = self.bucketAssets[bucket];
	return assets ? (NSInteger)assets.count : MAX(0, self.bucketCounts[bucket].integerValue);
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	return self.bucketDates.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return [self numberOfItemsForSection:section];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier forIndexPath:indexPath];
	NSString *bucket = indexPath.section < (NSInteger)self.bucketDates.count ? self.bucketDates[indexPath.section] : nil;
	NSArray<IMAsset *> *assets = bucket ? self.bucketAssets[bucket] : nil;
	IMAsset *asset = assets && indexPath.item < (NSInteger)assets.count ? assets[indexPath.item] : nil;
	[cell configureWithAsset:asset];
	cell.selectionModeEnabled = NO;
	if (!asset && bucket) [self loadBucketIfNeeded:bucket];
	return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
   sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width;
	CGFloat side = (width - (kPartnerColumns - 1) * kPartnerCellSpacing) / kPartnerColumns;
	return CGSizeMake(MAX(1, side), MAX(1, side));
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section < (NSInteger)self.bucketDates.count) [self loadBucketIfNeeded:self.bucketDates[indexPath.section]];
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section >= (NSInteger)self.bucketDates.count) return;
	NSString *bucket = self.bucketDates[indexPath.section];
	NSArray<IMAsset *> *assets = self.bucketAssets[bucket];
	if (!assets || indexPath.item >= (NSInteger)assets.count) {
		[collectionView deselectItemAtIndexPath:indexPath animated:YES];
		return;
	}
	AssetViewController *viewer = [AssetViewController viewerWithAssets:assets startIndex:indexPath.item readOnly:YES];
	[self presentViewController:viewer animated:YES completion:nil];
}

@end
