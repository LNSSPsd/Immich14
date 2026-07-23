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

@interface SearchViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating>
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
	[IMSearchApi allPeopleWithCompletion:^(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || error || !people) {
			return;
		}
		strongSelf.people = people;
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
	self.debounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.4
	                                                       repeats:NO
	                                                         block:^(NSTimer *_Nonnull timer) {
		    [weakSelf performSearch:text];
	    }];
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
	[self.searchTask cancel];
	self.searchTask = nil;
	[self.activityIndicator stopAnimating];
}

- (void)performSearch:(NSString *)query {
	[self cancelInFlightSearch];
	self.lastQuery = query;
	self.mode = IMSearchModeResults;
	self.resultAssets = @[];
	self.emptyLabel.hidden = YES;
	[self.collectionView reloadData];
	[self.activityIndicator startAnimating];

	self.searchGeneration += 1;
	NSInteger generation = self.searchGeneration;

	__weak typeof(self) weakSelf = self;
	void (^completion)(NSArray<IMAsset *> *_Nullable, NSError *_Nullable) = ^(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.searchGeneration) {
			return;
		}
		strongSelf.searchTask = nil;
		[strongSelf.activityIndicator stopAnimating];
		if (error) {
			return;
		}
		strongSelf.resultAssets = assets ?: @[];
		[strongSelf.collectionView reloadData];
		strongSelf.emptyLabel.hidden = strongSelf.resultAssets.count > 0;
	};

	switch (self.scopeControl.selectedSegmentIndex) {
		case IMSearchScopeOcr:
			self.searchTask = [IMSearchApi metadataSearchWithOcr:query completion:completion];
			break;
		case IMSearchScopeDescription:
			self.searchTask = [IMSearchApi metadataSearchWithDescription:query completion:completion];
			break;
		case IMSearchScopeFilename:
			self.searchTask = [IMSearchApi metadataSearchWithFilename:query completion:completion];
			break;
		case IMSearchScopeContext:
		default:
			self.searchTask = [IMSearchApi smartSearchWithQuery:query completion:completion];
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

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];

	if (self.mode == IMSearchModeResults) {
		AssetViewController *viewer = [AssetViewController viewerWithAssets:self.resultAssets startIndex:indexPath.item];
		[self presentViewController:viewer animated:YES completion:nil];
		return;
	}

	if (indexPath.section == IMSearchBrowseSectionPeople) {
		IMPerson *person = self.people[indexPath.item];
		[IMSearchApi metadataSearchWithPersonId:person.personId
		                              completion:^(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error) {
			    if (error || !assets) {
				    return;
			    }
			    AssetGridViewController *grid = [AssetGridViewController gridWithTitle:person.name assets:assets];
			    [self.navigationController pushViewController:grid animated:YES];
		    }];
		return;
	}

	NSString *city = self.placeCityNames[indexPath.item];
	[IMSearchApi metadataSearchWithCity:city
	                          completion:^(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error) {
		    if (error || !assets) {
			    return;
		    }
		    AssetGridViewController *grid = [AssetGridViewController gridWithTitle:city assets:assets];
		    [self.navigationController pushViewController:grid animated:YES];
	    }];
}

@end
