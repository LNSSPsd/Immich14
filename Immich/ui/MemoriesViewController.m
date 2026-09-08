#import "MemoriesViewController.h"
#import "IMMemoryApi.h"
#import "IMMemoryCell.h"
#import "MemoryDetailViewController.h"
#import "MemoryEditorViewController.h"
#import "common.h"

@interface MemoriesViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<IMMemory *> *memories;
@property (nonatomic, copy) NSArray<IMMemory *> *allMemories;
@end

@implementation MemoriesViewController

static const NSInteger kMemoryColumns = 2;
static const CGFloat kMemorySpacing = 12.0;

- (instancetype)init {
	self = [super init];
	if (self) {
		_memories = @[];
		_allMemories = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Memories");
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
	                                                                                           target:self
	                                                                                           action:@selector(createMemoryTapped)];
	UIBarButtonItem *statisticsButton = nil;
	if (@available(iOS 13.0, *)) {
		statisticsButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"]
		                                                    style:UIBarButtonItemStylePlain
		                                                   target:self
		                                                   action:@selector(statisticsTapped)];
	} else {
		statisticsButton = [[UIBarButtonItem alloc] initWithTitle:@"i"
		                                                   style:UIBarButtonItemStylePlain
		                                                  target:self
		                                                  action:@selector(statisticsTapped)];
	}
	self.navigationItem.leftItemsSupplementBackButton = YES;
	self.navigationItem.leftBarButtonItem = statisticsButton;
	self.navigationItem.leftBarButtonItem.accessibilityLabel = _(@"Memory statistics");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	}
	self.filterControl = [[UISegmentedControl alloc] initWithItems:@[ _(@"All"), _(@"Saved") ]];
	self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
	self.filterControl.selectedSegmentIndex = 0;
	[self.filterControl addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
	[self.view addSubview:self.filterControl];

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = kMemorySpacing;
	layout.minimumLineSpacing = kMemorySpacing;
	layout.sectionInset = UIEdgeInsetsMake(kMemorySpacing, kMemorySpacing, kMemorySpacing, kMemorySpacing);
	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	if (@available(iOS 13.0, *)) {
		self.collectionView.backgroundColor = UIColor.systemGroupedBackgroundColor;
	} else {
		self.collectionView.backgroundColor = UIColor.groupTableViewBackgroundColor;
	}
	[self.collectionView registerClass:[IMMemoryCell class] forCellWithReuseIdentifier:IMMemoryCellReuseIdentifier];
	[self.view addSubview:self.collectionView];
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reloadMemories) forControlEvents:UIControlEventValueChanged];
	self.collectionView.refreshControl = self.refreshControl;

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.text = _(@"No memories yet.");
	if (@available(iOS 13.0, *)) {
		self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.emptyLabel.textColor = UIColor.grayColor;
	}
	self.emptyLabel.hidden = YES;
	[self.view addSubview:self.emptyLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.filterControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
		[self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
		[self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
		[self.filterControl.heightAnchor constraintEqualToConstant:32],
		[self.collectionView.topAnchor constraintEqualToAnchor:self.filterControl.bottomAnchor constant:8],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
		[self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
	]];
	[self reloadMemories];
}

- (void)createMemoryTapped {
	MemoryEditorViewController *editor = [[MemoryEditorViewController alloc] initForCreate];
	__weak typeof(self) weakSelf = self;
	editor.onSaved = ^(IMMemory *memory) {
		(void)memory;
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
		 if (!strongSelf) {
			 return;
		 }
		 strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
		 NSString *message = nil;
		 if (error || !statistics) {
			 message = error.localizedDescription ?: _(@"The server could not load memory statistics.");
		} else {
			 NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
			 formatter.numberStyle = NSNumberFormatterDecimalStyle;
			 message = [NSString stringWithFormat:_(@"Total memories: %@"),
			            [formatter stringFromNumber:@(statistics.total)] ?: @"0"];
		 }
		 UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Memory statistics")
		                                                                  message:message
		                                                           preferredStyle:UIAlertControllerStyleAlert];
		 [alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		 [strongSelf presentViewController:alert animated:YES completion:nil];
	}];
}

- (void)filterChanged {
	[self applyFilter];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.collectionView) {
		[self reloadMemories];
	}
}

- (void)reloadMemories {
	__weak typeof(self) weakSelf = self;
	[IMMemoryApi allMemoriesWithCompletion:^(NSArray<IMMemory *> *_Nullable memories, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[strongSelf.refreshControl endRefreshing];
		if (error || !memories) {
			if (strongSelf.memories.count == 0) {
				strongSelf.emptyLabel.text = _(@"Couldn't load memories. Pull to retry.");
				strongSelf.emptyLabel.hidden = NO;
			}
			return;
		}
		strongSelf.allMemories = memories;
		[strongSelf applyFilter];
	}];
}

- (void)applyFilter {
	if (self.filterControl.selectedSegmentIndex == 1) {
		self.memories = [self.allMemories filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(IMMemory *memory, NSDictionary *bindings) {
			return memory.isSaved;
		}]];
	} else {
		self.memories = self.allMemories;
	}
	if (self.emptyLabel) {
		self.emptyLabel.text = self.filterControl.selectedSegmentIndex == 1 ? _(@"No saved memories.") : _(@"No memories yet.");
		self.emptyLabel.hidden = self.memories.count > 0;
	}
	[self.collectionView reloadData];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.memories.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
	               cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	IMMemoryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:IMMemoryCellReuseIdentifier
	                                                                  forIndexPath:indexPath];
	[cell configureWithMemory:self.memories[indexPath.item]];
	return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
	                  layout:(UICollectionViewLayout *)collectionViewLayout
	  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width - (kMemorySpacing * (kMemoryColumns + 1));
	return CGSizeMake(width / kMemoryColumns, width / kMemoryColumns * 0.86);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];
	[self.navigationController pushViewController:[MemoryDetailViewController viewControllerForMemory:self.memories[indexPath.item]]
	                                     animated:YES];
}

@end
