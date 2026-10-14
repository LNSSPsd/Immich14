#import "VisibilityViewController.h"
#import "IMAssetApi.h"
#import "AssetGridViewController.h"
#import "common.h"

@interface VisibilityViewController ()
@property (nonatomic, copy) NSString *visibility;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@property (nonatomic, strong, nullable) AssetGridViewController *grid;
@property (nonatomic) NSUInteger loadGeneration;
@end

@implementation VisibilityViewController

- (instancetype)initWithVisibility:(NSString *)visibility title:(NSString *)title {
	if ((self = [super init])) {
		_visibility = [visibility copy];
		_assets = @[];
		self.title = title;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.status = [[UILabel alloc] init];
	self.status.translatesAutoresizingMaskIntoConstraints = NO;
	self.status.textAlignment = NSTextAlignmentCenter;
	self.status.textColor = UIColor.secondaryLabelColor;
	self.status.numberOfLines = 0;
	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.status];
	[self.view addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[
		[self.status.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.status.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
		[self.status.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
		[self.status.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
	                                                                                        target:self
	                                                                                        action:@selector(reload)];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)reload {
	NSUInteger generation = ++self.loadGeneration;
	if (!self.grid) {
		self.status.text = nil;
		[self.spinner startAnimating];
	}
	NSString *visibility = self.visibility;
	__weak typeof(self) weakSelf = self;
	[IMAssetApi timeBucketsWithVisibility:visibility completion:^(NSArray<NSString *> *dates, NSArray<NSNumber *> *counts, NSError *error) {
		if (error || dates.count == 0) {
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf || strongSelf.loadGeneration != generation) return;
				[strongSelf showAssets:@[]];
				if (error) {
					strongSelf.status.text = _(@"Unable to load photos.");
					[strongSelf showError:error];
				}
			});
			return;
		}
		NSMutableDictionary<NSString *, NSArray<IMAsset *> *> *byBucket = [NSMutableDictionary dictionary];
		dispatch_group_t group = dispatch_group_create();
		__block NSError *firstError = nil;
		for (NSString *date in dates) {
			dispatch_group_enter(group);
			[IMAssetApi assetsInTimeBucket:date visibility:visibility completion:^(NSArray<IMAsset *> *assets, NSError *bucketError) {
				@synchronized (byBucket) {
					if (bucketError) {
						firstError = firstError ?: bucketError;
					} else {
						byBucket[date] = assets ?: @[];
					}
				}
				dispatch_group_leave(group);
			}];
		}
		dispatch_group_notify(group, dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || strongSelf.loadGeneration != generation) return;
			NSMutableArray<IMAsset *> *all = [NSMutableArray array];
			for (NSString *date in dates) {
				[all addObjectsFromArray:byBucket[date] ?: @[]];
			}
			[strongSelf showAssets:all];
			if (firstError) [strongSelf showError:firstError];
		});
	}];
}

- (void)showAssets:(NSArray<IMAsset *> *)assets {
	[self.spinner stopAnimating];
	NSArray *oldIds = [self.assets valueForKey:@"assetId"];
	NSArray *newIds = [assets valueForKey:@"assetId"];
	BOOL changed = ![oldIds isEqualToArray:newIds] || (!self.grid && assets.count);
	self.assets = assets;
	self.status.text = assets.count ? nil : _(@"No photos");
	if (!changed) {
		return;
	}
	if (self.grid) {
		[self.grid willMoveToParentViewController:nil];
		[self.grid.view removeFromSuperview];
		[self.grid removeFromParentViewController];
		self.grid = nil;
	}
	if (assets.count == 0) {
		return;
	}
	AssetGridViewController *grid = [AssetGridViewController gridWithTitle:self.title assets:assets];
	[self addChildViewController:grid];
	grid.view.frame = self.view.bounds;
	grid.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:grid.view];
	[grid didMoveToParentViewController:self];
	self.grid = grid;
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title
	                                                               message:error.localizedDescription ?: _(@"Request failed")
	                                                        preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
