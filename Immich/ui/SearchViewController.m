#import "SearchViewController.h"
#import "IMSearchApi.h"
#import "IMApiClient.h"
#import "TimelineCell.h"
#import "IMPersonCell.h"
#import "IMPlaceCell.h"
#import "AssetGridViewController.h"
#import "AssetViewController.h"
#import "ExploreViewController.h"
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
@property (nonatomic) NSInteger peopleGeneration;
@property (nonatomic, strong, nullable) NSURLSessionTask *browseTask;
@property (nonatomic, copy, nullable) void (^browseRetryAction)(void);
@property (nonatomic, strong, nullable) NSURLSessionTask *discoveryTask;
@property (nonatomic) NSInteger discoveryGeneration;
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
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Explore")
	                                                                            style:UIBarButtonItemStylePlain
	                                                                           target:self
	                                                                           action:@selector(showSearchTools)];
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
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(peopleDidChange:) name:IMPeopleDidChangeNotification object:nil];
}

#pragma mark - Browse data

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self.debounceTimer invalidate];
	[self.searchTask cancel];
	[self.browseTask cancel];
	[self.discoveryTask cancel];
}

- (void)peopleDidChange:(NSNotification *)notification {
	self.people = [IMSearchApi cachedPeople];
	self.peopleNextPage = 0;
	if (self.mode == IMSearchModeBrowse) [self.collectionView reloadData];
	[self loadBrowseData];
}

- (void)loadBrowseData {
	NSInteger generation = ++self.peopleGeneration;
	self.peopleLoading = YES;
	__weak typeof(self) weakSelf = self;
	[IMSearchApi peopleAtPage:1 completion:^(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.peopleGeneration) {
			return;
		}
		strongSelf.peopleLoading = NO;
		if (error || !people) return;
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
	NSInteger generation = self.peopleGeneration;
	__weak typeof(self) weakSelf = self;
	[IMSearchApi peopleAtPage:page completion:^(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.peopleGeneration) {
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

#pragma mark - Discovery tools

- (void)showSearchTools {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Explore")
	                                                                  message:_(@"Find assets using the server's discovery indexes.")
	                                                           preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Favorite photos")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf loadFavoriteAssets];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Random photos")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf loadDiscoveryAssetsWithTitle:_(@"Random photos") criteria:@{ @"size": @100 } large:NO];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Explore categories")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[self.navigationController pushViewController:[[ExploreViewController alloc] init] animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Largest files")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf loadDiscoveryAssetsWithTitle:_(@"Largest files") criteria:@{ @"size": @100 } large:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Matching asset count")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf loadSearchStatistics];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Location suggestions")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf loadCitySuggestions];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Camera makes")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf loadCameraMakeSuggestions];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Camera models")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf loadCameraModelSuggestions];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Camera lenses")
	                                          style:UIAlertActionStyleDefault
	                                        handler:^(UIAlertAction *action) {
		[weakSelf loadCameraLensSuggestions];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)loadFavoriteAssets {
	[self.browseTask cancel];
	self.browseTask = nil;
	__weak typeof(self) weakSelf = self;
	NSString *title = _(@"Favorite photos");
	self.browseRetryAction = ^{
		[weakSelf loadFavoriteAssets];
	};
	IMAssetGridPageLoader pageLoader = ^NSURLSessionTask *_Nullable(NSInteger page,
	                                                                  void (^pageCompletion)(NSArray<IMAsset *> *_Nullable,
	                                                                                         NSString *_Nullable,
	                                                                                         NSError *_Nullable)) {
		return [IMSearchApi metadataSearchWithFavorite:YES page:page completion:pageCompletion];
	};
	[self startBrowseTask:[IMSearchApi metadataSearchWithFavorite:YES
	                                                           page:1
	                                                     completion:[self browseCompletionWithTitle:title
	                                                                                     pageLoader:pageLoader]]];
}

- (void)showDiscoveryError:(NSError *)error title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
	                                                                 message:error.localizedDescription ?: _(@"The server could not complete this search.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) {
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (void)loadDiscoveryAssetsWithTitle:(NSString *)title
	                         criteria:(NSDictionary<NSString *, id> *)criteria
	                            large:(BOOL)large {
	[self.discoveryTask cancel];
	NSInteger generation = ++self.discoveryGeneration;
	[self.activityIndicator startAnimating];
	__weak typeof(self) weakSelf = self;
	void (^completion)(NSArray<IMAsset *> *, NSError *) = ^(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error) {
		SearchViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.discoveryGeneration) {
			return;
		}
		strongSelf.discoveryTask = nil;
		[strongSelf.activityIndicator stopAnimating];
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
			return;
		}
		if (error || !assets) {
			[strongSelf showDiscoveryError:error title:title];
			return;
		}
		AssetGridViewController *grid = [AssetGridViewController gridWithTitle:title assets:assets];
		[strongSelf.navigationController pushViewController:grid animated:YES];
	};
	if (large) {
		self.discoveryTask = [IMSearchApi largeAssetsWithCriteria:criteria completion:completion];
	} else {
		self.discoveryTask = [IMSearchApi randomAssetsWithCriteria:criteria completion:completion];
	}
}

- (void)loadSearchStatistics {
	[self.discoveryTask cancel];
	NSInteger generation = ++self.discoveryGeneration;
	[self.activityIndicator startAnimating];
	NSString *query = self.lastQuery;
	NSDictionary *criteria = @{};
	BOOL exactFilter = NO;
	if (query.length > 0) {
		switch (self.scopeControl.selectedSegmentIndex) {
			case IMSearchScopeOcr: criteria = @{ @"ocr": query }; exactFilter = YES; break;
			case IMSearchScopeDescription: criteria = @{ @"description": query }; exactFilter = YES; break;
			default: break;
		}
	}
	__weak typeof(self) weakSelf = self;
	self.discoveryTask = [IMSearchApi searchStatisticsWithCriteria:criteria completion:^(IMSearchStatistics *_Nullable statistics, NSError *_Nullable error) {
		SearchViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.discoveryGeneration) {
			return;
		}
		strongSelf.discoveryTask = nil;
		[strongSelf.activityIndicator stopAnimating];
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
			return;
		}
		if (error || !statistics) {
			[strongSelf showDiscoveryError:error title:_(@"Asset count")];
			return;
		}
		NSString *message;
		if (exactFilter) {
			message = [NSString stringWithFormat:_(@"%@ matching assets"), @(statistics.total)];
		} else if (query.length > 0) {
			message = [NSString stringWithFormat:_(@"%@ assets in your library (this search scope has no count filter)"), @(statistics.total)];
		} else {
			message = [NSString stringWithFormat:_(@"%@ assets in your library"), @(statistics.total)];
		}
		if (!strongSelf.viewIfLoaded.window) {
			return;
		}
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Asset count") message:message preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[strongSelf presentViewController:alert animated:YES completion:nil];
	}];
}

- (void)loadCitySuggestions {
	[self.discoveryTask cancel];
	NSInteger generation = ++self.discoveryGeneration;
	[self.activityIndicator startAnimating];
	NSString *query = self.lastQuery.lowercaseString;
	__weak typeof(self) weakSelf = self;
	self.discoveryTask = [IMSearchApi searchSuggestionsForType:IMSearchSuggestionTypeCity
	                                                    country:nil
	                                                       state:nil
	                                                       make:nil
	                                                      model:nil
	                                                  lensModel:nil
	                                                includeNull:NO
	                                                 completion:^(NSArray<NSString *> *_Nullable suggestions, NSError *_Nullable error) {
		SearchViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.discoveryGeneration) {
			return;
		}
		strongSelf.discoveryTask = nil;
		[strongSelf.activityIndicator stopAnimating];
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
			return;
		}
		if (error || !suggestions) {
			[strongSelf showDiscoveryError:error title:_(@"Location suggestions")];
			return;
		}
		NSMutableArray<NSString *> *filtered = [NSMutableArray arrayWithCapacity:MIN((NSUInteger)30, suggestions.count)];
		for (NSString *suggestion in suggestions) {
			if (query.length > 0 && [suggestion.lowercaseString rangeOfString:query].location == NSNotFound) {
				continue;
			}
			[filtered addObject:suggestion];
			if (filtered.count == 30) break;
		}
		if (filtered.count == 0) {
			[strongSelf showDiscoveryError:[NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{ NSLocalizedDescriptionKey: _(@"No location suggestions found.") }]
			                         title:_(@"Location suggestions")];
			return;
		}
		if (!strongSelf.viewIfLoaded.window) {
			return;
		}
		UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Choose a location") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		for (NSString *suggestion in filtered) {
			[sheet addAction:[UIAlertAction actionWithTitle:suggestion style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				strongSelf.searchController.searchBar.text = suggestion;
				[strongSelf updateSearchResultsForSearchController:strongSelf.searchController];
			}]];
		}
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		if (sheet.popoverPresentationController) {
			sheet.popoverPresentationController.barButtonItem = strongSelf.navigationItem.rightBarButtonItem;
		}
		[strongSelf presentViewController:sheet animated:YES completion:nil];
	}];
}


- (void)loadCameraMakeSuggestions {
	[self loadCameraSuggestionsForType:IMSearchSuggestionTypeCameraMake title:_(@"Camera makes") criteriaKey:@"make"];
}

- (void)loadCameraModelSuggestions {
	[self loadCameraSuggestionsForType:IMSearchSuggestionTypeCameraModel title:_(@"Camera models") criteriaKey:@"model"];
}

- (void)loadCameraLensSuggestions {
	[self loadCameraSuggestionsForType:IMSearchSuggestionTypeCameraLensModel title:_(@"Camera lenses") criteriaKey:@"lensModel"];
}

- (void)loadCameraSuggestionsForType:(NSString *)type
	                             title:(NSString *)title
	                       criteriaKey:(NSString *)criteriaKey {
	[self.discoveryTask cancel];
	NSInteger generation = ++self.discoveryGeneration;
	[self.activityIndicator startAnimating];
	NSString *query = self.lastQuery.lowercaseString;
	__weak typeof(self) weakSelf = self;
	self.discoveryTask = [IMSearchApi searchSuggestionsForType:type
	                                                    country:nil
	                                                       state:nil
	                                                       make:nil
	                                                      model:nil
	                                                  lensModel:nil
	                                                includeNull:NO
	                                                 completion:^(NSArray<NSString *> *_Nullable suggestions, NSError *_Nullable error) {
		SearchViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.discoveryGeneration) return;
		strongSelf.discoveryTask = nil;
		[strongSelf.activityIndicator stopAnimating];
		if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
		if (error || !suggestions) {
			[strongSelf showDiscoveryError:error title:title];
			return;
		}
		NSMutableArray<NSString *> *filtered = [NSMutableArray arrayWithCapacity:MIN((NSUInteger)30, suggestions.count)];
		for (NSString *suggestion in suggestions) {
			if (query.length > 0 && [suggestion.lowercaseString rangeOfString:query].location == NSNotFound) continue;
			[filtered addObject:suggestion];
			if (filtered.count == 30) break;
		}
		if (filtered.count == 0) {
			[strongSelf showDiscoveryError:[NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:_(@"No %@ found."), title.lowercaseString] }]
			                         title:title];
			return;
		}
		if (!strongSelf.viewIfLoaded.window) return;
		NSString *chooseTitle = [NSString stringWithFormat:_(@"Choose a %@"), title.lowercaseString];
		UIAlertController *sheet = [UIAlertController alertControllerWithTitle:chooseTitle message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		for (NSString *suggestion in filtered) {
			[sheet addAction:[UIAlertAction actionWithTitle:suggestion style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				[strongSelf loadCameraAssetsWithField:criteriaKey value:suggestion title:title];
			}]];
		}
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		if (sheet.popoverPresentationController) sheet.popoverPresentationController.barButtonItem = strongSelf.navigationItem.rightBarButtonItem;
		[strongSelf presentViewController:sheet animated:YES completion:nil];
	}];
}

- (void)loadCameraAssetsWithField:(NSString *)field value:(NSString *)value title:(NSString *)title {
	[self.browseTask cancel];
	self.browseTask = nil;
	__weak typeof(self) weakSelf = self;
	self.browseRetryAction = ^{ [weakSelf loadCameraAssetsWithField:field value:value title:title]; };
	IMAssetGridPageLoader pageLoader = ^NSURLSessionTask *_Nullable(NSInteger page, void (^pageCompletion)(NSArray<IMAsset *> *_Nullable, NSString *_Nullable, NSError *_Nullable)) {
		if ([field isEqualToString:@"make"]) return [IMSearchApi metadataSearchWithMake:value page:page completion:pageCompletion];
		if ([field isEqualToString:@"model"]) return [IMSearchApi metadataSearchWithModel:value page:page completion:pageCompletion];
		return [IMSearchApi metadataSearchWithLensModel:value page:page completion:pageCompletion];
	};
	[self startBrowseTask:pageLoader(1, [self browseCompletionWithTitle:[NSString stringWithFormat:@"%@: %@", title, value]
	                                                               pageLoader:pageLoader])];
	/* The loader is intentionally used for the first page too, so all three filters share
	 * the same response validation and pagination behavior. */
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	NSString *text = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[self.debounceTimer invalidate];
	if (self.discoveryTask) {
		self.discoveryGeneration += 1;
		[self.discoveryTask cancel];
		self.discoveryTask = nil;
	}

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
	self.discoveryGeneration += 1;
	[self.discoveryTask cancel];
	self.discoveryTask = nil;
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
