#import "MemoriesViewController.h"
#import "IMMemoryApi.h"
#import "IMMemoryCell.h"
#import "IMMemoryPlayerViewController.h"
#import "MemoryEditorViewController.h"
#import "common.h"

static NSString *const kMemorySectionHeader = @"MemorySectionHeader";
static const CGFloat kMemoryInset = 16;
static const CGFloat kMemorySpacing = 20;

@interface IMMemorySectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation IMMemorySectionHeader
- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.titleLabel = [[UILabel alloc] init];
		self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
		self.titleLabel.textColor = UIColor.labelColor;
		self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
		[self addSubview:self.titleLabel];
		[NSLayoutConstraint activateConstraints:@[
			[self.titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kMemoryInset],
			[self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-kMemoryInset],
			[self.titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
		]];
	}
	return self;
}
@end

@interface MemoriesViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<NSString *> *sectionTitles;
@property (nonatomic, copy) NSArray<NSArray<IMMemory *> *> *sections;
@property (nonatomic) BOOL loadedOnce;
@end

@implementation MemoriesViewController

- (instancetype)init {
	self = [super init];
	if (self) {
		_sectionTitles = @[];
		_sections = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Memories");
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
	                                                                                           target:self
	                                                                                           action:@selector(createMemoryTapped)];
	UIBarButtonItem *statisticsButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]
	                                                                     style:UIBarButtonItemStylePlain
	                                                                    target:self
	                                                                    action:@selector(statisticsTapped)];
	statisticsButton.accessibilityLabel = _(@"Memory statistics");
	self.navigationItem.leftItemsSupplementBackButton = YES;
	self.navigationItem.leftBarButtonItem = statisticsButton;
	self.view.backgroundColor = UIColor.systemBackgroundColor;

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumLineSpacing = kMemorySpacing;
	layout.sectionInset = UIEdgeInsetsMake(0, kMemoryInset, kMemorySpacing, kMemoryInset);
	self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
	self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
	self.collectionView.alwaysBounceVertical = YES;
	[self.collectionView registerClass:[IMMemoryCell class] forCellWithReuseIdentifier:IMMemoryCellReuseIdentifier];
	[self.collectionView registerClass:[IMMemorySectionHeader class]
	        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
	               withReuseIdentifier:kMemorySectionHeader];
	[self.view addSubview:self.collectionView];
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reloadMemories) forControlEvents:UIControlEventValueChanged];
	self.collectionView.refreshControl = self.refreshControl;

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	self.emptyLabel.hidden = YES;
	[self.view addSubview:self.emptyLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
		[self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
	]];

	[self applyMemories:[IMMemoryApi cachedMemories]];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.navigationController.viewControllers.firstObject == self) {
		self.navigationController.navigationBar.prefersLargeTitles = YES;
	}
	[self reloadMemories];
}

- (void)reloadMemories {
	__weak typeof(self) weakSelf = self;
	[IMMemoryApi allMemoriesWithCompletion:^(NSArray<IMMemory *> *_Nullable memories, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf.refreshControl endRefreshing];
		if (error || !memories) {
			if (strongSelf.sections.count == 0) {
				strongSelf.emptyLabel.text = _(@"Couldn't load memories. Pull to retry.");
				strongSelf.emptyLabel.hidden = NO;
			}
			return;
		}
		strongSelf.loadedOnce = YES;
		[strongSelf applyMemories:memories];
	}];
}

- (void)applyMemories:(NSArray<IMMemory *> *)memories {
	NSMutableArray<IMMemory *> *today = [NSMutableArray array];
	NSMutableArray<IMMemory *> *saved = [NSMutableArray array];
	NSMutableArray<IMMemory *> *rest = [NSMutableArray array];
	for (IMMemory *memory in memories) {
		if (memory.assets.count == 0) continue;
		if (memory.isActiveToday) {
			[today addObject:memory];
		} else if (memory.isSaved) {
			[saved addObject:memory];
		} else {
			[rest addObject:memory];
		}
	}
	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *sections = [NSMutableArray array];
	if (today.count) { [titles addObject:_(@"On This Day")]; [sections addObject:today]; }
	if (saved.count) { [titles addObject:_(@"Saved")]; [sections addObject:saved]; }
	if (rest.count) { [titles addObject:today.count || saved.count ? _(@"More Memories") : _(@"Memories")]; [sections addObject:rest]; }
	self.sectionTitles = titles;
	self.sections = sections;
	self.emptyLabel.text = _(@"No memories yet.\nImmich makes them from photos taken on this day in earlier years.");
	self.emptyLabel.hidden = sections.count > 0 || !self.loadedOnce;
	[self.collectionView reloadData];
}

#pragma mark Actions

- (void)createMemoryTapped {
	MemoryEditorViewController *editor = [[MemoryEditorViewController alloc] initForCreate];
	__weak typeof(self) weakSelf = self;
	editor.onSaved = ^(IMMemory *memory) {
		[weakSelf reloadMemories];
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)statisticsTapped {
	UIBarButtonItem *button = self.navigationItem.leftBarButtonItem;
	button.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMMemoryApi statisticsWithCompletion:^(IMMemoryStatistics *_Nullable statistics, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
		NSString *message = nil;
		if (error || !statistics) {
			message = error.localizedDescription ?: _(@"The server could not load memory statistics.");
		} else {
			NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
			formatter.numberStyle = NSNumberFormatterDecimalStyle;
			message = [NSString stringWithFormat:_(@"Total memories: %@"), [formatter stringFromNumber:@(statistics.total)] ?: @"0"];
		}
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Memory statistics")
		                                                               message:message
		                                                        preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[strongSelf presentViewController:alert animated:YES completion:nil];
	}];
}

#pragma mark Collection view

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	return (NSInteger)self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return (NSInteger)self.sections[section].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	IMMemoryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:IMMemoryCellReuseIdentifier forIndexPath:indexPath];
	cell.compact = NO;
	[cell configureWithMemory:self.sections[indexPath.section][indexPath.item]];
	return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
	IMMemorySectionHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
	                                                                  withReuseIdentifier:kMemorySectionHeader
	                                                                         forIndexPath:indexPath];
	header.titleLabel.text = self.sectionTitles[indexPath.section];
	return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width - kMemoryInset * 2;
	BOOL hero = indexPath.section == 0 && self.sections.count && self.sections[0].firstObject.isActiveToday;
	return CGSizeMake(width, round(width * (hero ? 1.05 : 0.66)));
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                             layout:(UICollectionViewLayout *)collectionViewLayout
    referenceSizeForHeaderInSection:(NSInteger)section {
	return CGSizeMake(collectionView.bounds.size.width, 44);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	IMMemoryCell *cell = (IMMemoryCell *)[collectionView cellForItemAtIndexPath:indexPath];
	IMMemoryPlayerViewController *player = [IMMemoryPlayerViewController playerWithMemories:self.sections[indexPath.section]
	                                                                             startIndex:indexPath.item];
	player.sourceImageView = cell.imageView;
	__weak typeof(self) weakSelf = self;
	player.onChange = ^{
		[weakSelf reloadMemories];
	};
	[self presentViewController:player animated:YES completion:nil];
}

@end
