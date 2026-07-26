#import "SearchViewController.h"
#import "IMSearchApi.h"
#import "TimelineCell.h"
#import "IMPersonCell.h"
#import "IMPlaceCell.h"
#import "AssetGridViewController.h"
#import "AssetViewController.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMSearchMode) {
	IMSearchModeBrowse,
	IMSearchModeResults,
};

typedef NS_ENUM(NSInteger, IMSearchBrowseSection) {
	IMSearchBrowseSectionPeople = 0,
	IMSearchBrowseSectionPlaces = 1,
};

static NSString *const kHeaderReuseIdentifier = @"SearchSectionHeader";

@interface IMSearchSectionHeader : UICollectionReusableView
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation IMSearchSectionHeader

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
			[self.titleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
		]];
	}
	return self;
}

@end

typedef NS_ENUM(NSInteger, IMSearchScope) {
	IMSearchScopeContext = 0,     
	IMSearchScopeOcr = 1,         
	IMSearchScopeDescription = 2, 
	IMSearchScopeFilename = 3,    
};

@interface SearchViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating, IMZoomTransitionSource>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIView *scopeContainer;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) NSLayoutConstraint *scopeHeightConstraint;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic) IMSearchMode mode;

@property (nonatomic, copy) NSArray<IMPerson *> *people;
@property (nonatomic, copy) NSArray<IMAsset *> *placeAssets;
@property (nonatomic, copy) NSArray<NSString *> *placeCityNames;

@property (nonatomic, copy) NSArray<IMAsset *> *resultAssets;
@property (nonatomic, copy, nullable) NSString *lastQuery;
@property (nonatomic, strong, nullable) NSTimer *debounceTimer;
@property (nonatomic, strong, nullable) NSURLSessionTask *searchTask;
@property (nonatomic) NSInteger searchGeneration;
@property (nonatomic) NSInteger resultNextPage;
@property (nonatomic) NSInteger peopleNextPage;
@property (nonatomic) BOOL peopleLoading;
@property (nonatomic, strong, nullable) NSURLSessionTask *browseTask;
@property (nonatomic, copy, nullable) void (^browseRetryAction)(void);
@end

@implementation SearchViewController

static const NSInteger kResultColumns = 4;
static const NSInteger kPlaceColumns = 3;
static const CGFloat kCellSpacing = 2;
static const CGFloat kPersonCellWidth = 78;
static const CGFloat kPersonCellHeight = 100;
static const CGFloat kScopeBarHeight = 44;

- (instancetype)init {
	self = [super init];
	if (self) {
		_people = @[];
		_placeAssets = @[];
		_placeCityNames = @[];
		_resultAssets = @[];
		_mode = IMSearchModeBrowse;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Search");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}

	self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.searchController.searchResultsUpdater = self;
	self.searchController.obscuresBackgroundDuringPresentation = NO;
	self.searchController.searchBar.placeholder = _(@"Search your photos");
	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;

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
	[self.collectionView registerClass:[IMPersonCell class] forCellWithReuseIdentifier:IMPersonCellReuseIdentifier];
	[self.collectionView registerClass:[IMPlaceCell class] forCellWithReuseIdentifier:IMPlaceCellReuseIdentifier];
	[self.collectionView registerClass:[IMSearchSectionHeader class]
	         forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
	                withReuseIdentifier:kHeaderReuseIdentifier];
	[self.view addSubview:self.collectionView];

	self.scopeContainer = [[UIView alloc] init];
	self.scopeContainer.translatesAutoresizingMaskIntoConstraints = NO;
	self.scopeContainer.clipsToBounds = YES;
	[self.view addSubview:self.scopeContainer];

	self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[ _(@"Context"), _(@"OCR"), _(@"Description"), _(@"Filename") ]];
	self.scopeControl.selectedSegmentIndex = IMSearchScopeContext;
	self.scopeControl.translatesAutoresizingMaskIntoConstraints = NO;
	[self.scopeControl addTarget:self action:@selector(scopeChanged) forControlEvents:UIControlEventValueChanged];
	[self.scopeContainer addSubview:self.scopeControl];

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.text = _(@"No results.");
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	if (@available(iOS 13.0, *)) {
		self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.emptyLabel.textColor = UIColor.grayColor;
	}
	self.emptyLabel.hidden = YES;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.userInteractionEnabled = YES;
	[self.emptyLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(retryLastSearch)]];
	[self.view addSubview:self.emptyLabel];

	if (@available(iOS 13.0, *)) {
		self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	} else {
		self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	}
	self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
	self.activityIndicator.hidesWhenStopped = YES;
	[self.view addSubview:self.activityIndicator];

	self.scopeHeightConstraint = [self.scopeContainer.heightAnchor constraintEqualToConstant:0];
	[NSLayoutConstraint activateConstraints:@[
		[self.scopeContainer.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.scopeContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.scopeContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		self.scopeHeightConstraint,

		[self.scopeControl.leadingAnchor constraintEqualToAnchor:self.scopeContainer.leadingAnchor constant:12],
		[self.scopeControl.trailingAnchor constraintEqualToAnchor:self.scopeContainer.trailingAnchor constant:-12],
		[self.scopeControl.bottomAnchor constraintEqualToAnchor:self.scopeContainer.bottomAnchor constant:-6],
		[self.scopeControl.heightAnchor constraintEqualToConstant:32],

		[self.collectionView.topAnchor constraintEqualToAnchor:self.scopeContainer.bottomAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

		[self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.activityIndicator.topAnchor constraintEqualToAnchor:self.scopeContainer.bottomAnchor constant:24],
	]];

	self.people = [IMSearchApi cachedPeople];
	self.placeAssets = [IMSearchApi cachedPlaceAssets];
	self.placeCityNames = [IMSearchApi cachedPlaceCityNames];
	[self.collectionView reloadData];

	[self loadBrowseData];
}

#pragma mark - Browse data

- (void)loadBrowseData {
	__weak typeof(self) weakSelf = self;
	[IMSearchApi peopleAtPage:1 completion:^(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || error || !people) {
			return;
		}
		strongSelf.people = people;
		strongSelf.peopleNextPage = hasNextPage ? 2 : 0;
		if (strongSelf.mode == IMSearchModeBrowse) {
			[strongSelf.collectionView reloadData];
		}
	}];
	[IMSearchApi assetsByCityWithCompletion:^(NSArray<IMAsset *> *_Nullable assets, NSArray<NSString *> *_Nullable cityNames,
	                                          NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || error || !assets) {
			return;
		}
		strongSelf.placeAssets = assets;
		strongSelf.placeCityNames = cityNames;
		if (strongSelf.mode == IMSearchModeBrowse) {
			[strongSelf.collectionView reloadData];
		}
	}];
}

- (void)loadMorePeople {
	if (self.peopleLoading || self.peopleNextPage < 1) {
		return;
	}
	self.peopleLoading = YES;
	NSInteger page = self.peopleNextPage;
	__weak typeof(self) weakSelf = self;
	[IMSearchApi peopleAtPage:page completion:^(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.peopleLoading = NO;
		if (error || !people) {
			return;
		}
		strongSelf.people = [strongSelf.people arrayByAddingObjectsFromArray:people];
		strongSelf.peopleNextPage = hasNextPage ? page + 1 : 0;
		if (strongSelf.mode == IMSearchModeBrowse) {
			[strongSelf.collectionView reloadData];
		}
	}];
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	NSString *text = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[self.debounceTimer invalidate];

	if (text.length == 0) {
		self.lastQuery = nil;
		[self cancelInFlightSearch];
		[self setScopeBarVisible:NO];
		self.mode = IMSearchModeBrowse;
		self.emptyLabel.hidden = YES;
		[self.collectionView reloadData];
		return;
	}

	[self setScopeBarVisible:YES];
	__weak typeof(self) weakSelf = self;
	NSTimer *timer = [NSTimer timerWithTimeInterval:0.4
	                                         repeats:NO
	                                           block:^(NSTimer *_Nonnull unused) {
		    [weakSelf performSearch:text];
	    }];
	[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
	self.debounceTimer = timer;
}

- (void)retryLastSearch {
	if (self.mode == IMSearchModeBrowse) {
		if (self.browseRetryAction && !self.browseTask) {
			self.emptyLabel.hidden = YES;
			self.browseRetryAction();
		}
		return;
	}
	if (self.lastQuery.length > 0) {
		[self performSearch:self.lastQuery];
	}
}

- (void)scopeChanged {
	if (self.lastQuery.length > 0) {
		[self performSearch:self.lastQuery];
	}
}

- (void)setScopeBarVisible:(BOOL)visible {
	self.scopeHeightConstraint.constant = visible ? kScopeBarHeight : 0;
	[UIView animateWithDuration:0.2 animations:^{
		[self.view layoutIfNeeded];
	}];
}

- (void)cancelInFlightSearch {
	self.searchGeneration += 1;
	[self.searchTask cancel];
	self.searchTask = nil;
	[self.activityIndicator stopAnimating];
}

- (void)performSearch:(NSString *)query {
	[self cancelInFlightSearch];
	[self.browseTask cancel];
	self.browseTask = nil;
	self.lastQuery = query;
	self.mode = IMSearchModeResults;
	self.resultAssets = @[];
	self.resultNextPage = 0;
	self.emptyLabel.hidden = YES;
	[self.collectionView reloadData];
	[self.activityIndicator startAnimating];
	[self fetchSearchPage:1];
}

- (void)fetchSearchPage:(NSInteger)page {
	NSInteger generation = self.searchGeneration;
	NSString *query = self.lastQuery;

	__weak typeof(self) weakSelf = self;
	void (^completion)(NSArray<IMAsset *> *_Nullable, NSString *_Nullable, NSError *_Nullable) =
	    ^(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.searchGeneration) {
			return;
		}
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
			return;
		}
		strongSelf.searchTask = nil;
		[strongSelf.activityIndicator stopAnimating];
		if (error) {
			if (page == 1) {
				strongSelf.emptyLabel.text = _(@"Search failed. Tap to retry.");
				strongSelf.emptyLabel.hidden = NO;
			}
			return;
		}
		strongSelf.resultNextPage = nextPage.integerValue >= 1 ? nextPage.integerValue : 0;
		if (page == 1) {
			strongSelf.emptyLabel.text = _(@"No results.");
			strongSelf.resultAssets = assets ?: @[];
			strongSelf.emptyLabel.hidden = strongSelf.resultAssets.count > 0;
		} else {
			strongSelf.resultAssets = [strongSelf.resultAssets arrayByAddingObjectsFromArray:assets ?: @[]];
		}
		[strongSelf.collectionView reloadData];
	};

	switch (self.scopeControl.selectedSegmentIndex) {
		case IMSearchScopeOcr:
			self.searchTask = [IMSearchApi metadataSearchWithOcr:query page:page completion:completion];
			break;
		case IMSearchScopeDescription:
			self.searchTask = [IMSearchApi metadataSearchWithDescription:query page:page completion:completion];
			break;
		case IMSearchScopeFilename:
			self.searchTask = [IMSearchApi metadataSearchWithFilename:query page:page completion:completion];
			break;
		case IMSearchScopeContext:
		default:
			self.searchTask = [IMSearchApi smartSearchWithQuery:query page:page completion:completion];
			break;
	}
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
	return self.mode == IMSearchModeBrowse ? 2 : 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	if (self.mode == IMSearchModeResults) {
		return self.resultAssets.count;
	}
	return section == IMSearchBrowseSectionPeople ? self.people.count : self.placeAssets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                   cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	if (self.mode == IMSearchModeResults) {
		TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier
		                                                                forIndexPath:indexPath];
		[cell configureWithAsset:self.resultAssets[indexPath.item]];
		return cell;
	}
	if (indexPath.section == IMSearchBrowseSectionPeople) {
		IMPersonCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:IMPersonCellReuseIdentifier
		                                                                forIndexPath:indexPath];
		[cell configureWithPerson:self.people[indexPath.item]];
		return cell;
	}
	IMPlaceCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:IMPlaceCellReuseIdentifier
	                                                                forIndexPath:indexPath];
	[cell configureWithAsset:self.placeAssets[indexPath.item] cityName:self.placeCityNames[indexPath.item]];
	return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
            viewForSupplementaryElementOfKind:(NSString *)kind
                                  atIndexPath:(NSIndexPath *)indexPath {
	IMSearchSectionHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
	                                                                 withReuseIdentifier:kHeaderReuseIdentifier
	                                                                        forIndexPath:indexPath];
	header.titleLabel.text = indexPath.section == IMSearchBrowseSectionPeople ? _(@"People") : _(@"Places");
	return header;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width;
	if (self.mode == IMSearchModeResults) {
		CGFloat side = (width - (kResultColumns - 1) * kCellSpacing) / kResultColumns;
		return CGSizeMake(side, side);
	}
	if (indexPath.section == IMSearchBrowseSectionPeople) {
		return CGSizeMake(kPersonCellWidth, kPersonCellHeight);
	}
	CGFloat side = (width - (kPlaceColumns - 1) * kCellSpacing) / kPlaceColumns;
	return CGSizeMake(side, side);
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                             layout:(UICollectionViewLayout *)collectionViewLayout
    referenceSizeForHeaderInSection:(NSInteger)section {
	if (self.mode == IMSearchModeResults) {
		return CGSizeZero;
	}
	NSInteger count = section == IMSearchBrowseSectionPeople ? self.people.count : self.placeAssets.count;
	return count > 0 ? CGSizeMake(0, 30) : CGSizeZero;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView
        willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath {
	if (self.mode == IMSearchModeResults) {
		if (self.resultNextPage >= 1 && self.searchTask == nil &&
		    indexPath.item + kResultColumns * 6 >= (NSInteger)self.resultAssets.count) {
			[self fetchSearchPage:self.resultNextPage];
		}
		return;
	}
	if (indexPath.section == IMSearchBrowseSectionPeople &&
	    indexPath.item + 40 >= (NSInteger)self.people.count) {
		[self loadMorePeople];
	}
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];

	if (self.mode == IMSearchModeResults) {
		AssetViewController *viewer = [AssetViewController viewerWithAssets:self.resultAssets startIndex:indexPath.item];
		viewer.zoomSource = self;
		viewer.presentSourceImageView = ((TimelineCell *)[collectionView cellForItemAtIndexPath:indexPath]).imageView;
		[self presentViewController:viewer animated:YES completion:nil];
		return;
	}

	if (self.browseTask) {
		return;
	}
	if (indexPath.section == IMSearchBrowseSectionPeople) {
		[self pushGridForPerson:self.people[indexPath.item]];
	} else {
		[self pushGridForCity:self.placeCityNames[indexPath.item]];
	}
}

#pragma mark - Person/city tap-through

- (void)pushGridForPerson:(IMPerson *)person {
	NSString *title = person.name.length > 0 ? person.name : _(@"Unnamed");
	NSString *personId = person.personId;
	__weak typeof(self) weakSelf = self;
	self.browseRetryAction = ^{ [weakSelf pushGridForPerson:person]; };
	[self startBrowseTask:[IMSearchApi metadataSearchWithPersonId:personId
	                                                          page:1
	                                                    completion:[self browseCompletionWithTitle:title
	                                                                                    pageLoader:^NSURLSessionTask *_Nullable(NSInteger page, void (^pageCompletion)(NSArray<IMAsset *> *_Nullable, NSString *_Nullable, NSError *_Nullable)) {
		    return [IMSearchApi metadataSearchWithPersonId:personId page:page completion:pageCompletion];
	    }]]];
}

- (void)pushGridForCity:(NSString *)city {
	__weak typeof(self) weakSelf = self;
	self.browseRetryAction = ^{ [weakSelf pushGridForCity:city]; };
	[self startBrowseTask:[IMSearchApi metadataSearchWithCity:city
	                                                      page:1
	                                                completion:[self browseCompletionWithTitle:city
	                                                                                pageLoader:^NSURLSessionTask *_Nullable(NSInteger page, void (^pageCompletion)(NSArray<IMAsset *> *_Nullable, NSString *_Nullable, NSError *_Nullable)) {
		    return [IMSearchApi metadataSearchWithCity:city page:page completion:pageCompletion];
	    }]]];
}

- (void)startBrowseTask:(nullable NSURLSessionTask *)task {
	self.emptyLabel.hidden = YES;
	[self.activityIndicator startAnimating];
	self.browseTask = task;
}

- (void (^)(NSArray<IMAsset *> *_Nullable, NSString *_Nullable, NSError *_Nullable))browseCompletionWithTitle:(NSString *)title
                                                                                                    pageLoader:(IMAssetGridPageLoader)pageLoader {
	__weak typeof(self) weakSelf = self;
	return ^(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.browseTask = nil;
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
			return;
		}
		[strongSelf.activityIndicator stopAnimating];
		if (error || !assets) {
			if (strongSelf.mode == IMSearchModeBrowse) {
				strongSelf.emptyLabel.text = _(@"Failed to load. Tap to retry.");
				strongSelf.emptyLabel.hidden = NO;
			}
			return;
		}
		strongSelf.browseRetryAction = nil;
		AssetGridViewController *grid = [AssetGridViewController gridWithTitle:title assets:assets];
		grid.nextPageToken = nextPage;
		grid.pageLoader = pageLoader;
		[strongSelf.navigationController pushViewController:grid animated:YES];
	};
}

#pragma mark - IMZoomTransitionSource

- (nullable UIImageView *)zoomTransitionImageViewForAssetId:(NSString *)assetId {
	if (self.mode != IMSearchModeResults) {
		return nil; 
	}
	NSUInteger item = [self.resultAssets indexOfObjectPassingTest:^BOOL(IMAsset *asset, NSUInteger idx, BOOL *stop) {
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
