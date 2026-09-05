#import "PeopleViewController.h"
#import "IMPersonCell.h"
#import "IMSearchApi.h"
#import "AssetGridViewController.h"
#import "PersonProfileViewController.h"
#import "common.h"

@interface IMManagedPersonCell : IMPersonCell
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation IMManagedPersonCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.statusLabel = [[UILabel alloc] init];
		self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.statusLabel.font = [UIFont systemFontOfSize:11];
		self.statusLabel.textColor = UIColor.secondaryLabelColor;
		self.statusLabel.textAlignment = NSTextAlignmentCenter;
		[self.contentView addSubview:self.statusLabel];
		[NSLayoutConstraint activateConstraints:@[
			[self.statusLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.statusLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
		]];
		self.isAccessibilityElement = YES;
		self.accessibilityTraits = UIAccessibilityTraitButton;
	}
	return self;
}

- (void)configureWithPerson:(IMPerson *)person {
	[super configureWithPerson:person];
	self.statusLabel.text = person.isHidden ? _(@"Hidden") : (person.name.length ? nil : _(@"Unnamed"));
	self.accessibilityLabel = person.name.length ? person.name : _(@"Unnamed person");
	self.accessibilityValue = person.isHidden ? _(@"Hidden") : nil;
	self.accessibilityHint = _(@"View photos or edit this person.");
}

@end

@interface PeopleViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchResultsUpdating>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<IMPerson *> *people;
@property (nonatomic, copy) NSString *query;
@property (nonatomic) BOOL includeHidden;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL saving;
@property (nonatomic) NSInteger nextPage;
@property (nonatomic) NSInteger generation;
@property (nonatomic) NSInteger browseGeneration;
@property (nonatomic, strong, nullable) NSTimer *debounceTimer;
@property (nonatomic, strong, nullable) NSURLSessionTask *listTask;
@property (nonatomic, strong, nullable) NSURLSessionTask *assetTask;
@end

@implementation PeopleViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"People");
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.people = [IMSearchApi cachedPeople];
	self.query = @"";
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Show Hidden") style:UIBarButtonItemStylePlain target:self action:@selector(toggleHidden)];

	self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.searchController.searchResultsUpdater = self;
	self.searchController.obscuresBackgroundDuringPresentation = NO;
	self.searchController.searchBar.placeholder = _(@"Search people by name");
	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = 8;
	layout.minimumLineSpacing = 8;
	layout.sectionInset = UIEdgeInsetsMake(12, 12, 12, 12);
	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
	self.collectionView.alwaysBounceVertical = YES;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	[self.collectionView registerClass:[IMManagedPersonCell class] forCellWithReuseIdentifier:@"managed-person"];
	[self.view addSubview:self.collectionView];
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reloadPeople) forControlEvents:UIControlEventValueChanged];
	self.collectionView.refreshControl = self.refreshControl;

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.userInteractionEnabled = YES;
	[self.emptyLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reloadPeople)]];
	[self.view addSubview:self.emptyLabel];
	self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
	self.activityIndicator.hidesWhenStopped = YES;
	[self.view addSubview:self.activityIndicator];
	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
		[self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.activityIndicator.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
	]];
	[self reloadPeople];
}

- (void)dealloc {
	[self.debounceTimer invalidate];
	[self.listTask cancel];
	[self.assetTask cancel];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	self.browseGeneration += 1;
	[self.assetTask cancel];
	self.assetTask = nil;
	if (!self.loading && !self.saving) [self.activityIndicator stopAnimating];
}

- (void)toggleHidden {
	if (self.saving) return;
	self.includeHidden = !self.includeHidden;
	self.navigationItem.rightBarButtonItem.title = self.includeHidden ? _(@"Hide Hidden") : _(@"Show Hidden");
	self.people = @[];
	[self.collectionView reloadData];
	[self reloadPeople];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
	if ([query isEqualToString:self.query]) return;
	self.query = query;
	[self cancelPendingRequests];
	self.people = @[];
	self.nextPage = 0;
	[self.collectionView reloadData];
	self.emptyLabel.hidden = YES;
	[self.activityIndicator startAnimating];
	__weak typeof(self) weakSelf = self;
	self.debounceTimer = [NSTimer timerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *timer) {
		[weakSelf reloadPeople];
	}];
	[[NSRunLoop mainRunLoop] addTimer:self.debounceTimer forMode:NSRunLoopCommonModes];
}

- (void)cancelPendingRequests {
	[self.debounceTimer invalidate];
	self.debounceTimer = nil;
	self.generation += 1;
	self.browseGeneration += 1;
	[self.listTask cancel];
	[self.assetTask cancel];
	self.listTask = nil;
	self.assetTask = nil;
	self.loading = NO;
}

- (void)reloadPeople {
	[self cancelPendingRequests];
	self.nextPage = 0;
	[self fetchPage:1];
}

- (void)fetchPage:(NSInteger)page {
	if (self.loading) return;
	self.loading = YES;
	self.emptyLabel.hidden = YES;
	[self.activityIndicator startAnimating];
	NSInteger generation = self.generation;
	__weak typeof(self) weakSelf = self;
	void (^completion)(NSArray<IMPerson *> *, BOOL, NSError *) = ^(NSArray<IMPerson *> *people, BOOL hasNextPage, NSError *error) {
		PeopleViewController *self = weakSelf;
		if (!self || generation != self.generation) return;
		self.listTask = nil;
		self.loading = NO;
		[self.refreshControl endRefreshing];
		if (!self.assetTask && !self.saving) [self.activityIndicator stopAnimating];
		if (error) {
			self.emptyLabel.text = _(@"Unable to load people. Tap to retry.");
			self.emptyLabel.hidden = self.people.count > 0;
			if (self.people.count) [self showError:error];
			return;
		}
		if (page == 1) {
			self.people = people ?: @[];
		} else {
			NSMutableArray<IMPerson *> *combined = [self.people mutableCopy];
			NSMutableSet<NSString *> *ids = [NSMutableSet setWithArray:[self.people valueForKey:@"personId"]];
			for (IMPerson *person in people) {
				if (![ids containsObject:person.personId]) {
					[combined addObject:person];
					[ids addObject:person.personId];
				}
			}
			self.people = combined;
		}
		self.nextPage = hasNextPage && people.count ? page + 1 : 0;
		self.emptyLabel.text = self.query.length ? _(@"No matching people.") : _(@"No people found. Faces appear after the server processes your photos.");
		self.emptyLabel.hidden = self.people.count > 0;
		[self.collectionView reloadData];
	};
	if (self.query.length) {
		self.listTask = [IMSearchApi searchPeopleNamed:self.query includeHidden:self.includeHidden completion:^(NSArray<IMPerson *> *people, NSError *error) {
			completion(people, NO, error);
		}];
	} else {
		self.listTask = [IMSearchApi peopleAtPage:page includeHidden:self.includeHidden completion:completion];
	}
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"People") message:error.localizedDescription ?: _(@"The request failed. Please try again.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.people.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	IMManagedPersonCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"managed-person" forIndexPath:indexPath];
	[cell configureWithPerson:self.people[indexPath.item]];
	return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat availableWidth = MAX(1, collectionView.bounds.size.width - 24);
	NSInteger columns = MAX(1, (NSInteger)(availableWidth / 96));
	CGFloat width = (availableWidth - (columns - 1) * 8) / columns;
	return CGSizeMake(width, width + 30);
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
	if (self.nextPage > 0 && !self.loading && indexPath.item + 20 >= self.people.count) {
		[self fetchPage:self.nextPage];
	}
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];
	if (self.saving || self.assetTask) return;
	IMPerson *person = self.people[indexPath.item];
	NSString *title = person.name.length ? person.name : _(@"Unnamed person");
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:person.isHidden ? _(@"Hidden from the People browse view") : nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"View Photos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf browsePerson:person];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Person Details") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		PeopleViewController *self = weakSelf;
		if (!self) return;
		__weak PeopleViewController *weakPeople = self;
		PersonProfileViewController *profile = [[PersonProfileViewController alloc] initWithPersonId:person.personId
		                                                                             displayName:person.name
		                                                                                onSaved:^(IMPersonProfile *updated) {
			[weakPeople reloadPeople];
		}];
		[self.navigationController pushViewController:profile animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Rename") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf renamePerson:person];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:person.isHidden ? _(@"Show Person") : _(@"Hide Person") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf updatePerson:person name:nil hidden:@(!person.isHidden)];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)renamePerson:(IMPerson *)person {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Rename Person") message:_(@"Leave the name empty to make this person unnamed.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = person.name;
		field.placeholder = _(@"Name");
		field.autocapitalizationType = UITextAutocapitalizationTypeWords;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
		[weakSelf updatePerson:person name:name hidden:nil];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)updatePerson:(IMPerson *)person name:(NSString *)name hidden:(NSNumber *)hidden {
	if (self.saving) return;
	self.saving = YES;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	[self.activityIndicator startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMSearchApi updatePersonId:person.personId name:name hidden:hidden completion:^(IMPerson *updatedPerson, NSError *error) {
		PeopleViewController *self = weakSelf;
		if (!self) return;
		self.saving = NO;
		self.navigationItem.rightBarButtonItem.enabled = YES;
		if (error) {
			if (!self.loading && !self.assetTask) [self.activityIndicator stopAnimating];
			if (self.view.window) [self showError:error];
			return;
		}
		[self reloadPeople];
	}];
}

- (void)browsePerson:(IMPerson *)person {
	if (self.assetTask || self.saving) return;
	[self.activityIndicator startAnimating];
	NSInteger generation = ++self.browseGeneration;
	__weak typeof(self) weakSelf = self;
	self.assetTask = [IMSearchApi metadataSearchWithPersonId:person.personId page:1 completion:^(NSArray<IMAsset *> *assets, NSString *nextPage, NSError *error) {
		PeopleViewController *self = weakSelf;
		if (!self || self.browseGeneration != generation) return;
		self.assetTask = nil;
		if (!self.loading && !self.saving) [self.activityIndicator stopAnimating];
		if (self.navigationController.topViewController != self) return;
		if (error) { [self showError:error]; return; }
		AssetGridViewController *grid = [AssetGridViewController gridWithTitle:person.name.length ? person.name : _(@"Unnamed person") assets:assets ?: @[]];
		grid.nextPageToken = nextPage;
		grid.pageLoader = ^NSURLSessionTask *(NSInteger page, void (^completion)(NSArray<IMAsset *> *, NSString *, NSError *)) {
			return [IMSearchApi metadataSearchWithPersonId:person.personId page:page completion:completion];
		};
		[self.navigationController pushViewController:grid animated:YES];
	}];
}

@end
