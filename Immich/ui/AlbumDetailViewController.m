#import "AlbumDetailViewController.h"
#import "IMAlbumApi.h"
#import "TimelineCell.h"
#import "AssetViewController.h"
#import "common.h"

@interface AlbumDetailViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) IMAlbum *album;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@end

@implementation AlbumDetailViewController

static const NSInteger kColumns = 4;
static const CGFloat kCellSpacing = 2;

+ (instancetype)detailViewControllerForAlbum:(IMAlbum *)album {
	AlbumDetailViewController *vc = [[AlbumDetailViewController alloc] init];
	vc.album = album;
	return vc;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_assets = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.album.name;
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
	                                                                                        target:self
	                                                                                        action:@selector(moreTapped)];

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
	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
	                                                                                        action:@selector(handleLongPress:)];
	[self.collectionView addGestureRecognizer:longPress];
	[self.view addSubview:self.collectionView];

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.text = _(@"No photos in this album yet.");
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

	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

		[self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	[self reload];
}

- (void)reload {
	[self.activityIndicator startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMAlbumApi assetsInAlbumId:self.album.albumId
	                  completion:^(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    [strongSelf.activityIndicator stopAnimating];
		    if (error || !assets) {
			    return;
		    }
		    strongSelf.assets = assets;
		    [strongSelf.collectionView reloadData];
		    strongSelf.emptyLabel.hidden = assets.count > 0;
	    }];
}

#pragma mark - Album actions

- (void)moreTapped {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Rename Album")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [weakSelf renameTapped];
	    }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Delete Album")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [weakSelf deleteTapped];
	    }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)renameTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Rename Album")
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.text = self.album.name;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Save")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		    if (name.length == 0) {
			    return;
		    }
		    [IMAlbumApi renameAlbumId:weakSelf.album.albumId
		                          name:name
		                    completion:^(IMAlbum *_Nullable album, NSError *_Nullable error) {
			        typeof(self) strongSelf = weakSelf;
			        if (!strongSelf || error || !album) {
				        return;
			        }
			        strongSelf.album = album;
			        strongSelf.title = album.name;
		        }];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete Album?")
	                                                                 message:_(@"The photos themselves are not deleted.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [IMAlbumApi deleteAlbumId:weakSelf.album.albumId
		                    completion:^(BOOL success, NSError *_Nullable error) {
			        typeof(self) strongSelf = weakSelf;
			        if (strongSelf && success) {
				        [strongSelf.navigationController popViewControllerAnimated:YES];
			        }
		        }];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Remove asset (long press)

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan) {
		return;
	}
	CGPoint point = [gesture locationInView:self.collectionView];
	NSIndexPath *indexPath = [self.collectionView indexPathForItemAtPoint:point];
	if (!indexPath || (NSUInteger)indexPath.item >= self.assets.count) {
		return;
	}
	IMAsset *asset = self.assets[indexPath.item];

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Remove from Album")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [weakSelf removeAsset:asset];
	    }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
	sheet.popoverPresentationController.sourceView = cell ?: self.collectionView;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(point.x, point.y, 1, 1);
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)removeAsset:(IMAsset *)asset {
	__weak typeof(self) weakSelf = self;
	[IMAlbumApi removeAssetIds:@[ asset.assetId ]
	              fromAlbumId:self.album.albumId
	               completion:^(BOOL success, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || !success) {
			    return;
		    }
		    NSMutableArray<IMAsset *> *remaining = [strongSelf.assets mutableCopy];
		    [remaining removeObject:asset];
		    strongSelf.assets = remaining;
		    [strongSelf.collectionView reloadData];
		    strongSelf.emptyLabel.hidden = remaining.count > 0;
	    }];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.assets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                   cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	TimelineCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TimelineCellReuseIdentifier
	                                                                forIndexPath:indexPath];
	[cell configureWithAsset:self.assets[indexPath.item]];
	return cell;
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
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];
	AssetViewController *viewer = [AssetViewController viewerWithAssets:self.assets startIndex:indexPath.item];
	[self presentViewController:viewer animated:YES completion:nil];
}

@end
