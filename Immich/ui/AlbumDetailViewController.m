#import "AlbumDetailViewController.h"
#import "IMAlbumApi.h"
#import "IMBulkAssetActions.h"
#import "TimelineCell.h"
#import "AssetViewController.h"
#import "AlbumSharingViewController.h"
#import "IMSession.h"
#import "IMSharedLinkApi.h"
#import "SharedLinkEditorViewController.h"
#import "ActivityViewController.h"
#import "MapViewController.h"
#import "common.h"

@interface AlbumDetailViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, IMZoomTransitionSource>
@property (nonatomic, strong) IMAlbum *album;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@property (nonatomic, strong) UIBarButtonItem *moreButton;
@property (nonatomic, strong, nullable) IMAlbumAssetsTask *fetchTask;

@property (nonatomic) BOOL selecting;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IMAsset *> *selectedAssets;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedAssetOrder;
@property (nonatomic, strong) UIBarButtonItem *favoriteButton;
@property (nonatomic, strong) UIBarButtonItem *addAlbumButton;
@property (nonatomic, strong) UIBarButtonItem *downloadButton;
@property (nonatomic, strong) UIBarButtonItem *removeButton;
@property (nonatomic, strong) UIBarButtonItem *deleteButton;
@property (nonatomic, strong) UIBarButtonItem *jobButton;
@property (nonatomic, strong) UIBarButtonItem *tagButton;
@property (nonatomic, strong) UIBarButtonItem *metadataButton;
@property (nonatomic) BOOL loadingAlbumMap;
- (void)editAlbumInfoTapped;
- (void)updateAlbumFields:(NSDictionary<NSString *, id> *)fields;
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
		_selectedAssets = [NSMutableDictionary dictionary];
		_selectedAssetOrder = [NSMutableArray array];
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
	self.moreButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
	                                                                  target:self
	                                                                  action:@selector(moreTapped)];
	self.navigationItem.rightBarButtonItem = self.moreButton;

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

	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.collectionView.refreshControl = self.refreshControl;

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
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.userInteractionEnabled = YES;
	[self.emptyLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
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

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if ([self isMovingFromParentViewController]) {
		if (self.selecting) {
			[self toggleSelecting];
		}
		[self.fetchTask cancel];
		self.fetchTask = nil;
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	__weak typeof(self) weakSelf = self;
	[IMAlbumApi albumForId:self.album.albumId completion:^(IMAlbum *album, NSError *error) {
		if (!album) return;
		weakSelf.album = album;
		[weakSelf updateSelectionToolbarState];
	}];
}

- (void)dealloc {
	[_fetchTask cancel];
}

- (void)reload {
	[self.activityIndicator startAnimating];
	[self.fetchTask cancel];
	__weak typeof(self) weakSelf = self;
	self.fetchTask = [IMAlbumApi assetsInAlbumId:self.album.albumId
	                                        order:self.album.order
	                                   completion:^(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    strongSelf.fetchTask = nil;
		    [strongSelf.activityIndicator stopAnimating];
		    [strongSelf.refreshControl endRefreshing];
		    if (error || !assets) {
			    if (strongSelf.assets.count == 0) {
				    strongSelf.emptyLabel.text = _(@"Couldn't load this album. Tap to retry.");
				    strongSelf.emptyLabel.hidden = NO;
			    }
			    return;
		    }
		    strongSelf.emptyLabel.text = _(@"No photos in this album yet.");
		    strongSelf.assets = assets;
		    if (strongSelf.selecting) {
			    [strongSelf toggleSelecting];
		    } else {
			    [strongSelf.collectionView reloadData];
		    }
		    strongSelf.emptyLabel.hidden = assets.count > 0;
	    }];
}

#pragma mark - Album actions

- (BOOL)canEditAlbum {
	NSString *role = [self.album roleForUserId:IMSession.shared.userId];
	return [role isEqualToString:@"owner"] || [role isEqualToString:@"editor"];
}

- (BOOL)ownsAlbum {
	return [[self.album roleForUserId:IMSession.shared.userId] isEqualToString:@"owner"];
}

- (void)showAlbumMap {
	if (self.loadingAlbumMap || self.album.albumId.length == 0) return;
	self.loadingAlbumMap = YES;
	self.moreButton.enabled = NO;
	[self.activityIndicator startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMAlbumApi mapMarkersForAlbumId:self.album.albumId key:nil slug:nil completion:^(NSArray<IMMapMarker *> *_Nullable markers, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loadingAlbumMap = NO;
		strongSelf.moreButton.enabled = YES;
		[strongSelf.activityIndicator stopAnimating];
		if (error || !markers) {
			UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn't load album map")
			                                                                 message:error.localizedDescription ?: _(@"The server did not return map locations.")
			                                                          preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
			[strongSelf presentViewController:alert animated:YES completion:nil];
			return;
		}
		MapViewController *map = [MapViewController mapViewControllerWithMarkers:markers
		                                                                     title:strongSelf.album.name];
		[strongSelf.navigationController pushViewController:map animated:YES];
	}];
}

- (void)moreTapped {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Sharing") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AlbumSharingViewController *sharing = [[AlbumSharingViewController alloc] initWithAlbumId:weakSelf.album.albumId];
		[weakSelf.navigationController pushViewController:sharing animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Map") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf showAlbumMap];
	}]];
	if (self.assets.count > 0) {
		[sheet addAction:[UIAlertAction actionWithTitle:_(@"Select Photos")
		                                           style:UIAlertActionStyleDefault
		                                         handler:^(UIAlertAction *_Nonnull action) {
			    [weakSelf toggleSelecting];
		    }]];
	}
	if (self.canEditAlbum) [sheet addAction:[UIAlertAction actionWithTitle:_(@"Rename Album")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [weakSelf renameTapped];
	    }]];
	if (self.canEditAlbum) [sheet addAction:[UIAlertAction actionWithTitle:_(@"Album Settings")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *_Nonnull action) {
	    [weakSelf editAlbumInfoTapped];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Activity")
	                                   style:UIAlertActionStyleDefault
	                                 handler:^(UIAlertAction *action) {
	    ActivityViewController *activity = [ActivityViewController activityViewControllerForAlbumId:weakSelf.album.albumId
	                                                                                           assetId:nil
	                                                                                             title:weakSelf.album.name
                                                                                        albumOwner:[weakSelf ownsAlbum]];
	    [weakSelf.navigationController pushViewController:activity animated:YES];
}]];
	if (self.ownsAlbum) [sheet addAction:[UIAlertAction actionWithTitle:_(@"Delete Album")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [weakSelf deleteTapped];
	    }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Create Public Link") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf createPublicLink];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)editAlbumInfoTapped {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Album Settings")
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Edit Description")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
	    UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Album Description")
	                                                                     message:nil
	                                                              preferredStyle:UIAlertControllerStyleAlert];
	    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
	        field.text = weakSelf.album.albumDescription;
	        field.placeholder = _(@"Description");
	    }];
	    [alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	    [alert addAction:[UIAlertAction actionWithTitle:_(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *saveAction) {
	        NSString *description = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
	        [weakSelf updateAlbumFields:@{ @"description": description }];
	    }]];
	    [weakSelf presentViewController:alert animated:YES completion:nil];
}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Sort Oldest First") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
	    [weakSelf updateAlbumFields:@{ @"order": @"asc" }];
}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Sort Newest First") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
	    [weakSelf updateAlbumFields:@{ @"order": @"desc" }];
}]];
	NSString *activityTitle = self.album.activityEnabled ? _(@"Disable Activity Feed") : _(@"Enable Activity Feed");
	[sheet addAction:[UIAlertAction actionWithTitle:activityTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
	    [weakSelf updateAlbumFields:@{ @"isActivityEnabled": @(!weakSelf.album.activityEnabled) }];
}]];
	if (self.assets.count > 0) {
	    [sheet addAction:[UIAlertAction actionWithTitle:_(@"Use First Photo as Cover") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
	        IMAsset *asset = weakSelf.assets.firstObject;
	        if (asset.assetId.length) [weakSelf updateAlbumFields:@{ @"albumThumbnailAssetId": asset.assetId }];
	    }]];
}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)updateAlbumFields:(NSDictionary<NSString *,id> *)fields {
	if (!self.canEditAlbum || fields.count == 0) return;
	self.moreButton.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMAlbumApi updateAlbumId:self.album.albumId fields:fields completion:^(IMAlbum *album, NSError *error) {
	    AlbumDetailViewController *strongSelf = weakSelf;
	    if (!strongSelf) return;
	    strongSelf.moreButton.enabled = YES;
	    if (!album || error) {
	        [IMBulkAssetActions showErrorAlertWithTitle:_(@"Couldn't Update Album")
                                              message:error.localizedDescription ?: _(@"The server rejected this album update.")
                                presentingController:strongSelf];
	        return;
	    }
	    strongSelf.album = album;
	    strongSelf.title = album.name;
	    [strongSelf reload];
}];
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
			        if (!strongSelf) {
				        return;
			        }
			        if (error || !album) {
				        [IMBulkAssetActions showErrorAlertWithTitle:_(@"Couldn't Rename Album")
				                                              message:error.localizedDescription
				                                presentingController:strongSelf];
				        return;
			        }
			        strongSelf.album = album;
			        strongSelf.title = album.name;
		        }];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)createPublicLink {
	__weak typeof(self) weakSelf = self;
	__weak SharedLinkEditorViewController *weakEditor = nil;
	SharedLinkEditorViewController *editor = [SharedLinkEditorViewController editorForNewLinkWithTitle:self.album.name
	                                                                                          saveHandler:^(NSDictionary<NSString *,id> *fields) {
		AlbumDetailViewController *self = weakSelf;
		if (!self) return;
		self.moreButton.enabled = NO;
		[IMSharedLinkApi createAlbumLinkForAlbumId:self.album.albumId options:fields completion:^(IMSharedLink *link, NSError *error) {
			AlbumDetailViewController *inner = weakSelf;
			if (!inner) return;
			inner.moreButton.enabled = YES;
			if (!link || error) {
				[weakEditor setSaving:NO];
				[IMBulkAssetActions showErrorAlertWithTitle:_(@"Couldn't Create Link")
				                                      message:error.localizedDescription ?: _(@"The server rejected this link.")
				                        presentingController:editor];
				return;
			}
			NSURL *url = [IMSharedLinkApi publicURLForLink:link];
			if (!url) {
				[weakEditor setSaving:NO];
				[IMBulkAssetActions showErrorAlertWithTitle:_(@"Couldn't Create Link")
				                                      message:_(@"The server returned an invalid shared link.")
				                        presentingController:editor];
				return;
			}
			[inner dismissViewControllerAnimated:YES completion:^{
				UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
				activity.popoverPresentationController.barButtonItem = inner.moreButton;
				[inner presentViewController:activity animated:YES completion:nil];
			}];
		}];
	}];
	weakEditor = editor;
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:nav animated:YES completion:nil];
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
			        if (!strongSelf) {
				        return;
			        }
			        if (!success) {
				        [IMBulkAssetActions showErrorAlertWithTitle:_(@"Couldn't Delete Album")
				                                              message:error.localizedDescription
				                                presentingController:strongSelf];
				        return;
			        }
			        [strongSelf.navigationController popViewControllerAnimated:YES];
		        }];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Multi-select

- (void)toggleSelecting {
	self.selecting = !self.selecting;
	[self.selectedAssets removeAllObjects];
	[self.selectedAssetOrder removeAllObjects];
	for (NSIndexPath *indexPath in [self.collectionView.indexPathsForSelectedItems copy]) {
		[self.collectionView deselectItemAtIndexPath:indexPath animated:NO];
	}
	self.collectionView.allowsMultipleSelection = self.selecting;
	if (self.selecting) {
		UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
		                                                                          target:self
		                                                                          action:@selector(toggleSelecting)];
		self.navigationItem.rightBarButtonItem = cancel;
		self.toolbarItems = [self makeSelectionToolbarItems];
	} else {
		self.navigationItem.rightBarButtonItem = self.moreButton;
	}
	[self.navigationController setToolbarHidden:!self.selecting animated:YES];
	[self.collectionView reloadData];
	[self updateSelectionToolbarState];
}

- (NSArray<UIBarButtonItem *> *)makeSelectionToolbarItems {
	UIImage *starImage = nil, *albumImage = nil, *downloadImage = nil, *removeImage = nil, *trashImage = nil, *jobImage = nil, *tagImage = nil, *metadataImage = nil;
	if (@available(iOS 13.0, *)) {
		starImage = [UIImage systemImageNamed:@"star"];
		albumImage = [UIImage systemImageNamed:@"plus.rectangle.on.folder"];
		downloadImage = [UIImage systemImageNamed:@"square.and.arrow.down"];
		removeImage = [UIImage systemImageNamed:@"minus.circle"];
		trashImage = [UIImage systemImageNamed:@"trash"];
		jobImage = [UIImage systemImageNamed:@"gearshape"];
		tagImage = [UIImage systemImageNamed:@"tag"];
		metadataImage = [UIImage systemImageNamed:@"pencil"];
	}
	self.favoriteButton = [[UIBarButtonItem alloc] initWithImage:starImage style:UIBarButtonItemStylePlain target:self action:@selector(favoriteSelected)];
	self.addAlbumButton = [[UIBarButtonItem alloc] initWithImage:albumImage style:UIBarButtonItemStylePlain target:self action:@selector(addSelectedToAlbum)];
	self.downloadButton = [[UIBarButtonItem alloc] initWithImage:downloadImage style:UIBarButtonItemStylePlain target:self action:@selector(downloadSelected)];
	self.removeButton = [[UIBarButtonItem alloc] initWithImage:removeImage style:UIBarButtonItemStylePlain target:self action:@selector(removeSelectedFromAlbum)];
	self.jobButton = [[UIBarButtonItem alloc] initWithImage:jobImage style:UIBarButtonItemStylePlain target:self action:@selector(jobSelected)];
	self.jobButton.accessibilityLabel = _(@"Run asset job");
	self.tagButton = [[UIBarButtonItem alloc] initWithImage:tagImage style:UIBarButtonItemStylePlain target:self action:@selector(tagSelected)];
	self.tagButton.accessibilityLabel = _(@"Add Tags");
	self.metadataButton = [[UIBarButtonItem alloc] initWithImage:metadataImage style:UIBarButtonItemStylePlain target:self action:@selector(metadataSelected)];
	self.metadataButton.accessibilityLabel = _(@"Edit custom metadata");
	self.deleteButton = [[UIBarButtonItem alloc] initWithImage:trashImage style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)];
	if (@available(iOS 13.0, *)) {
		self.removeButton.tintColor = UIColor.systemRedColor;
		self.deleteButton.tintColor = UIColor.systemRedColor;
	}
	UIBarButtonItem *flex1 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex2 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex3 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex4 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex5 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex6 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *flex7 = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	return @[ self.favoriteButton, flex1, self.addAlbumButton, flex2, self.downloadButton, flex3, self.removeButton, flex4, self.jobButton, flex5, self.tagButton, flex6, self.metadataButton, flex7, self.deleteButton ];
}

- (BOOL)allSelectedAreFavorite {
	if (self.selectedAssets.count == 0) {
		return NO;
	}
	for (IMAsset *asset in [self orderedSelectedAssets]) {
		if (!asset.isFavorite) {
			return NO;
		}
	}
	return YES;
}

- (NSArray<IMAsset *> *)orderedSelectedAssets {
	NSMutableArray<IMAsset *> *assets = [NSMutableArray arrayWithCapacity:self.selectedAssetOrder.count];
	for (NSString *assetId in self.selectedAssetOrder) {
		IMAsset *asset = self.selectedAssets[assetId];
		if (asset) [assets addObject:asset];
	}
	return assets;
}

- (void)updateSelectionToolbarState {
	BOOL hasSelection = self.selectedAssets.count > 0;
	self.favoriteButton.enabled = hasSelection;
	self.addAlbumButton.enabled = hasSelection;
	self.downloadButton.enabled = hasSelection;
	self.removeButton.enabled = hasSelection && self.canEditAlbum;
	self.jobButton.enabled = hasSelection;
	self.tagButton.enabled = hasSelection;
	self.metadataButton.enabled = hasSelection;
	self.deleteButton.enabled = hasSelection;
	if (@available(iOS 13.0, *)) {
		self.favoriteButton.image = [UIImage systemImageNamed:[self allSelectedAreFavorite] ? @"star.slash" : @"star"];
	}
	if (self.selecting) {
		self.title = hasSelection ? [NSString stringWithFormat:_(@"%ld Selected"), (long)self.selectedAssets.count] : _(@"Select Items");
	} else {
		self.title = self.album.name;
	}
}

- (void)favoriteSelected {
	NSArray<IMAsset *> *assets = [self orderedSelectedAssets];
	BOOL favorite = ![self allSelectedAreFavorite];
	__weak typeof(self) weakSelf = self;
	[IMBulkAssetActions setFavorite:favorite
	                         assets:assets
	           presentingController:self
	                     completion:^(BOOL success) {
		    typeof(self) strongSelf = weakSelf;
		    if (strongSelf.selecting) {
			    [strongSelf toggleSelecting];
		    }
		    if (success) {
			    [strongSelf reload];
		    }
	    }];
}

- (void)downloadSelected {
	NSArray<IMAsset *> *assets = [self orderedSelectedAssets];
	__weak typeof(self) weakSelf = self;
	[IMBulkAssetActions downloadAssets:assets
	              presentingController:self
	                         completion:^{
		    typeof(self) strongSelf = weakSelf;
		    if (strongSelf.selecting) {
			    [strongSelf toggleSelecting];
		    }
	    }];
}

- (void)jobSelected {
	NSArray<IMAsset *> *assets = [self orderedSelectedAssets];
	__weak typeof(self) weakSelf = self;
	[IMBulkAssetActions presentAssetJobPickerForAssets:assets presentingController:self completion:^(BOOL success) {
		if (success && weakSelf.selecting) {
			[weakSelf toggleSelecting];
		}
	}];
}

- (void)tagSelected {
	NSArray<IMAsset *> *assets = [self orderedSelectedAssets];
	__weak typeof(self) weakSelf = self;
	[IMBulkAssetActions presentTagPickerForAssets:assets
	                         presentingController:self
	                                    completion:^(BOOL success) {
		if (success && weakSelf.selecting) {
			[weakSelf toggleSelecting];
		}
	}];
}

- (void)metadataSelected {
	NSArray<IMAsset *> *assets = [self orderedSelectedAssets];
	__weak typeof(self) weakSelf = self;
	[IMBulkAssetActions presentMetadataPickerForAssets:assets
	                              presentingController:self
	                                         completion:^(BOOL success) {
		if (success && weakSelf.selecting) {
			[weakSelf toggleSelecting];
		}
	}];
}

- (void)deleteSelected {
	NSArray<IMAsset *> *assets = [self orderedSelectedAssets];
	__weak typeof(self) weakSelf = self;
	[IMBulkAssetActions confirmDeleteAssets:assets
	                   presentingController:self
	                              completion:^(BOOL deleted) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || !deleted) {
			    return;
		    }
		    [strongSelf removeAssetsLocally:assets];
		    if (strongSelf.selecting) {
			    [strongSelf toggleSelecting];
		    }
	    }];
}

- (void)removeAssetsLocally:(NSArray<IMAsset *> *)assets {
	NSMutableSet<NSString *> *removedIds = [NSMutableSet setWithCapacity:assets.count];
	for (IMAsset *asset in assets) {
		[removedIds addObject:asset.assetId];
	}
	NSMutableArray<IMAsset *> *remaining = [NSMutableArray arrayWithCapacity:self.assets.count];
	NSInteger removed = 0;
	for (IMAsset *asset in self.assets) {
		if ([removedIds containsObject:asset.assetId]) {
			removed++;
		} else {
			[remaining addObject:asset];
		}
	}
	self.assets = remaining;
	[self.collectionView reloadData];
	self.emptyLabel.hidden = remaining.count > 0;
	[IMAlbumApi adjustCachedAssetCountForAlbumId:self.album.albumId delta:-removed];
}

- (void)addSelectedToAlbum {
	NSArray<IMAsset *> *assets = [self orderedSelectedAssets];
	[self toggleSelecting];
	[IMBulkAssetActions presentAddToAlbumForAssets:assets presentingController:self];
}

- (void)removeSelectedFromAlbum {
	if (!self.canEditAlbum) return;
	NSArray<IMAsset *> *assets = [self orderedSelectedAssets];
	NSString *title = assets.count == 1 ? _(@"Remove 1 item from this album?")
	                                     : [NSString stringWithFormat:_(@"Remove %ld items from this album?"), (long)assets.count];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Remove")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:assets.count];
		    for (IMAsset *asset in assets) {
			    [ids addObject:asset.assetId];
		    }
		    [IMAlbumApi removeAssetIds:ids
		                  fromAlbumId:weakSelf.album.albumId
		                   completion:^(BOOL success, NSError *_Nullable error) {
			        typeof(self) strongSelf = weakSelf;
			        if (!strongSelf) {
				        return;
			        }
			        if (!success) {
				        [IMBulkAssetActions showErrorAlertWithTitle:_(@"Couldn't Remove")
				                                              message:error.localizedDescription
				                                presentingController:strongSelf];
				        return;
			        }
			        [strongSelf removeAssetsLocally:assets];
			        if (strongSelf.selecting) {
				        [strongSelf toggleSelecting];
			        }
		        }];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Remove asset (long press)

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan || self.selecting) {
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
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Activity")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
	    ActivityViewController *activity = [ActivityViewController activityViewControllerForAlbumId:weakSelf.album.albumId
	                                                                                           assetId:asset.assetId
	                                                                                             title:_(@"Photo Activity")
                                                                                        albumOwner:[weakSelf ownsAlbum]];
	    [weakSelf.navigationController pushViewController:activity animated:YES];
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
		    if (!strongSelf) {
			    return;
		    }
		    if (!success) {
			    [IMBulkAssetActions showErrorAlertWithTitle:_(@"Couldn't Remove")
			                                          message:error.localizedDescription
			                            presentingController:strongSelf];
			    return;
		    }
		    [strongSelf removeAssetsLocally:@[ asset ]];
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
	cell.selectionModeEnabled = self.selecting;
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
	if (!self.selecting) {
		[collectionView deselectItemAtIndexPath:indexPath animated:YES];
		AssetViewController *viewer = [AssetViewController viewerWithAssets:self.assets startIndex:indexPath.item];
		viewer.zoomSource = self;
		viewer.presentSourceImageView = ((TimelineCell *)[collectionView cellForItemAtIndexPath:indexPath]).imageView;
		[self presentViewController:viewer animated:YES completion:nil];
		return;
	}
	if ((NSUInteger)indexPath.item >= self.assets.count) {
		return;
	}
	IMAsset *asset = self.assets[indexPath.item];
	NSString *assetId = asset.assetId;
	if (![assetId isKindOfClass:[NSString class]] || assetId.length == 0) {
		[collectionView deselectItemAtIndexPath:indexPath animated:NO];
		return;
	}
	if (!self.selectedAssets[assetId]) {
		[self.selectedAssetOrder addObject:assetId];
	}
	self.selectedAssets[assetId] = asset;
	[self updateSelectionToolbarState];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
	if (!self.selecting || (NSUInteger)indexPath.item >= self.assets.count) {
		return;
	}
	NSString *assetId = self.assets[indexPath.item].assetId;
	if (![assetId isKindOfClass:[NSString class]] || assetId.length == 0) {
		return;
	}
	[self.selectedAssets removeObjectForKey:assetId];
	[self.selectedAssetOrder removeObject:assetId];
	[self updateSelectionToolbarState];
}

#pragma mark - IMZoomTransitionSource

- (nullable UIImageView *)zoomTransitionImageViewForAssetId:(NSString *)assetId {
	NSUInteger item = [self.assets indexOfObjectPassingTest:^BOOL(IMAsset *asset, NSUInteger idx, BOOL *stop) {
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
