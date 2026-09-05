#import "StacksViewController.h"
#import "IMStackApi.h"
#import "TimelineCell.h"
#import "AssetGridViewController.h"
#import "common.h"

@interface StacksViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<IMStack *> *stacks;
@property (nonatomic, copy) NSArray<IMAsset *> *primaryAssets;
@end

@implementation StacksViewController

- (instancetype)init {
	self = [super init];
	if (self) {
		_stacks = @[];
		_primaryAssets = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Stacks");
	if (@available(iOS 13.0, *)) self.view.backgroundColor = UIColor.systemBackgroundColor;
	else self.view.backgroundColor = UIColor.whiteColor;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = 2;
	layout.minimumLineSpacing = 2;
	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	if (@available(iOS 13.0, *)) self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
	else self.collectionView.backgroundColor = UIColor.whiteColor;
	[self.collectionView registerClass:[TimelineCell class] forCellWithReuseIdentifier:TimelineCellReuseIdentifier];
	[self.view addSubview:self.collectionView];
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
	[self.collectionView addSubview:self.refreshControl];

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.text = _(@"No stacks.");
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	if (@available(iOS 13.0, *)) self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	else self.emptyLabel.textColor = UIColor.grayColor;
	[self.view addSubview:self.emptyLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];
	[self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.stacks.count > 0) [self refresh];
}

- (void)refresh {
	[IMStackApi stacksWithCompletion:^(NSArray<IMStack *> *stacks, NSError *error) {
		[self.refreshControl endRefreshing];
		if (error) {
			if (self.stacks.count == 0) self.emptyLabel.text = _(@"Couldn't load stacks. Pull to retry.");
			return;
		}
		self.stacks = stacks ?: @[];
		NSMutableArray *primaries = [NSMutableArray arrayWithCapacity:self.stacks.count];
		for (IMStack *stack in self.stacks) {
			IMAsset *primary = nil;
			for (IMAsset *asset in stack.assets) if ([asset.assetId isEqualToString:stack.primaryAssetId]) { primary = asset; break; }
			if (!primary) primary = stack.assets.firstObject;
			if (primary) [primaries addObject:primary];
		}
		self.primaryAssets = primaries;
		self.emptyLabel.text = _(@"No stacks.");
		self.emptyLabel.hidden = self.primaryAssets.count > 0;
		[self.collectionView reloadData];
	}];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return self.primaryAssets.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier forIndexPath:indexPath];
	[cell configureWithAsset:self.primaryAssets[indexPath.item]];
	return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat side = (collectionView.bounds.size.width - 4.0) / 3.0;
	return CGSizeMake(side, side);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.item >= self.stacks.count) return;
	IMStack *stack = self.stacks[indexPath.item];
	if (stack.assets.count == 0) return;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:_(@"Stack (%ld items)"), (long)stack.assets.count] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"View Photos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AssetGridViewController *grid = [AssetGridViewController gridWithTitle:[NSString stringWithFormat:_(@"Stack (%ld)"), (long)stack.assets.count] assets:stack.assets];
		[self.navigationController pushViewController:grid animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Set Primary Photo") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[self presentPrimaryPickerForStack:stack];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Delete Stack") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[self deleteStack:stack];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = [collectionView cellForItemAtIndexPath:indexPath]; sheet.popoverPresentationController.sourceRect = ((UIView *)[collectionView cellForItemAtIndexPath:indexPath]).bounds; }
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentPrimaryPickerForStack:(IMStack *)stack {
	UIAlertController *picker = [UIAlertController alertControllerWithTitle:_(@"Choose Primary Photo") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	for (IMAsset *asset in stack.assets) {
		NSString *title = asset.fileCreatedAt.length ? asset.fileCreatedAt : asset.assetId;
		[picker addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[IMStackApi updateStack:stack.stackId primaryAssetId:asset.assetId completion:^(IMStack *updated, NSError *error) {
				if (!updated) [self showError:error title:_(@"Couldn't Set Primary")]; else [self refresh];
			}];
		}]];
	}
	[picker addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (picker.popoverPresentationController) { picker.popoverPresentationController.sourceView = self.view; picker.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1); }
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)deleteStack:(IMStack *)stack {
	[IMStackApi deleteStack:stack.stackId completion:^(BOOL success, NSError *error) {
		if (!success) [self showError:error title:_(@"Couldn't Delete Stack")]; else [self refresh];
	}];
}

- (void)showError:(NSError *)error title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
