#import "AlbumsViewController.h"
#import "AlbumDetailViewController.h"
#import "IMAlbumApi.h"
#import "IMAlbumCell.h"
#import "common.h"

@interface AlbumsViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<IMAlbum *> *albums;
@end

@implementation AlbumsViewController

static const NSInteger kColumns = 2;
static const CGFloat kCellSpacing = 16;
static const CGFloat kLabelsHeight = 44;

- (instancetype)init {
	self = [super init];
	if (self) {
		_albums = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Albums");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
	                                                                                        target:self
	                                                                                        action:@selector(createTapped)];

	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = kCellSpacing;
	layout.minimumLineSpacing = kCellSpacing;
	layout.sectionInset = UIEdgeInsetsMake(kCellSpacing, kCellSpacing, kCellSpacing, kCellSpacing);

	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	if (@available(iOS 13.0, *)) {
		self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.collectionView.backgroundColor = UIColor.whiteColor;
	}
	[self.collectionView registerClass:[IMAlbumCell class] forCellWithReuseIdentifier:IMAlbumCellReuseIdentifier];
	[self.view addSubview:self.collectionView];

	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.collectionView.refreshControl = self.refreshControl;

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.text = _(@"No albums yet.");
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	if (@available(iOS 13.0, *)) {
		self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.emptyLabel.textColor = UIColor.grayColor;
	}
	self.emptyLabel.hidden = YES;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.userInteractionEnabled = YES;
	[self.emptyLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	[self.view addSubview:self.emptyLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	self.albums = [IMAlbumApi cachedAlbums];
	[self.collectionView reloadData];
	self.emptyLabel.hidden = self.albums.count > 0;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[IMAlbumApi allAlbumsWithCompletion:^(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[strongSelf.refreshControl endRefreshing];
		if (error || !albums) {
			if (strongSelf.albums.count == 0) {
				strongSelf.emptyLabel.text = _(@"Couldn't load albums. Tap to retry.");
				strongSelf.emptyLabel.hidden = NO;
			}
			return;
		}
		strongSelf.emptyLabel.text = _(@"No albums yet.");
		strongSelf.albums = albums;
		[strongSelf.collectionView reloadData];
		strongSelf.emptyLabel.hidden = albums.count > 0;
	}];
}

- (void)createTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"New Album")
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.placeholder = _(@"Album name");
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Create")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		    if (name.length == 0) {
			    return;
		    }
		    [weakSelf createAlbumWithName:name];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)createAlbumWithName:(NSString *)name {
	__weak typeof(self) weakSelf = self;
	[IMAlbumApi createAlbumWithName:name
	                      completion:^(IMAlbum *_Nullable album, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || error || !album) {
			    return;
		    }
		    [strongSelf.navigationController pushViewController:[AlbumDetailViewController detailViewControllerForAlbum:album]
		                                                 animated:YES];
	    }];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.albums.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                   cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	IMAlbumCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:IMAlbumCellReuseIdentifier
	                                                                forIndexPath:indexPath];
	[cell configureWithAlbum:self.albums[indexPath.item]];
	return cell;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                    layout:(UICollectionViewLayout *)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width - kCellSpacing * (kColumns + 1);
	CGFloat side = width / kColumns;
	return CGSizeMake(side, side + kLabelsHeight);
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];
	IMAlbum *album = self.albums[indexPath.item];
	[self.navigationController pushViewController:[AlbumDetailViewController detailViewControllerForAlbum:album] animated:YES];
}

@end
