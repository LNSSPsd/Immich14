#import "SharedLinkGuestViewController.h"
#import "IMSharedLinkApi.h"
#import "IMApiClient.h"
#import "IMAsset.h"
#import "common.h"

static const NSInteger kGuestColumns = 3;
static const CGFloat kGuestSpacing = 2.0;

@interface IMGuestAssetCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic) NSUInteger generation;
- (void)configureWithAsset:(IMAsset *)asset
                 publicURL:(NSURL *)publicURL
                 imageCache:(NSCache<NSString *, UIImage *> *)imageCache;
@end

@interface IMGuestPreviewViewController : UIViewController
- (instancetype)initWithAsset:(IMAsset *)asset
                    publicURL:(NSURL *)publicURL
                         image:(nullable UIImage *)image
                allowDownload:(BOOL)allowDownload;
@end

@interface SharedLinkGuestViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, copy) NSURL *publicURL;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *imageCache;
@property (nonatomic, strong, nullable) IMSharedLink *link;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL passwordPromptVisible;
@end

@implementation IMGuestAssetCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;
		self.imageView = [[UIImageView alloc] init];
		self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
		[self.contentView addSubview:self.imageView];
		self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
		self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
		self.spinner.hidesWhenStopped = YES;
		[self.contentView addSubview:self.spinner];
		[NSLayoutConstraint activateConstraints:@[
			[self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
			[self.spinner.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
			[self.spinner.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		]];
	}
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self.task cancel];
	self.task = nil;
	self.generation += 1;
	self.imageView.image = nil;
	[self.spinner stopAnimating];
}

- (void)configureWithAsset:(IMAsset *)asset
	             publicURL:(NSURL *)publicURL
	             imageCache:(NSCache<NSString *, UIImage *> *)imageCache {
	[self.task cancel];
	self.task = nil;
	NSUInteger generation = ++self.generation;
	self.imageView.image = [imageCache objectForKey:asset.assetId];
	if (self.imageView.image) {
		[self.spinner stopAnimating];
		return;
	}
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	self.task = [IMSharedLinkApi guestThumbnailDataForAssetId:asset.assetId
	                                                  publicURL:publicURL
	                                                       size:@"preview"
	                                                 completion:^(NSData *data, NSError *error) {
		IMGuestAssetCell *cell = weakSelf;
		if (!cell || cell.generation != generation) return;
		[cell.spinner stopAnimating];
		if (error || data.length == 0) return;
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			UIImage *image = [UIImage imageWithData:data];
			dispatch_async(dispatch_get_main_queue(), ^{
				IMGuestAssetCell *inner = weakSelf;
				if (!inner || inner.generation != generation) return;
				if (image) {
					[imageCache setObject:image forKey:asset.assetId];
					inner.imageView.image = image;
				}
			});
		});
	}];
}

@end

@implementation IMGuestPreviewViewController {
	IMAsset *_asset;
	NSURL *_publicURL;
	UIImage *_previewImage;
	BOOL _allowDownload;
	UIActivityIndicatorView *_spinner;
	UIImageView *_imageView;
	NSURLSessionTask *_thumbnailTask;
}

- (instancetype)initWithAsset:(IMAsset *)asset
	                publicURL:(NSURL *)publicURL
	                     image:(UIImage *)image
	            allowDownload:(BOOL)allowDownload {
	self = [super init];
	if (self) {
		_asset = asset;
		_publicURL = [publicURL copy];
		_previewImage = image;
		_allowDownload = allowDownload;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _asset.isImage ? _(@"Photo") : _(@"Video");
	self.view.backgroundColor = UIColor.blackColor;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                                                                                         target:self
	                                                                                         action:@selector(doneTapped)];
	if (_allowDownload) {
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
	                                                                                              target:self
	                                                                                              action:@selector(downloadTapped)];
	}
	_imageView = [[UIImageView alloc] init];
	_imageView.translatesAutoresizingMaskIntoConstraints = NO;
	_imageView.contentMode = UIViewContentModeScaleAspectFit;
	_imageView.image = _previewImage;
	[self.view addSubview:_imageView];
	[NSLayoutConstraint activateConstraints:@[
		[_imageView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[_imageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[_imageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[_imageView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
	_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
	_spinner.translatesAutoresizingMaskIntoConstraints = NO;
	_spinner.color = UIColor.whiteColor;
	_spinner.hidesWhenStopped = YES;
	[self.view addSubview:_spinner];
	[NSLayoutConstraint activateConstraints:@[
		[_spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[_spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];
	if (!_previewImage && _asset.assetId.length) {
		[_spinner startAnimating];
		__weak typeof(self) weakSelf = self;
		_thumbnailTask = [IMSharedLinkApi guestThumbnailDataForAssetId:_asset.assetId
	                                                       publicURL:_publicURL
	                                                            size:@"preview"
		                                                      completion:^(NSData *data, NSError *error) {
			IMGuestPreviewViewController *self = weakSelf;
			if (!self) return;
			if (error || data.length == 0) {
				[self->_spinner stopAnimating];
				return;
			}
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
				UIImage *image = [UIImage imageWithData:data];
				dispatch_async(dispatch_get_main_queue(), ^{
					IMGuestPreviewViewController *inner = weakSelf;
					if (!inner) return;
					[inner->_spinner stopAnimating];
					if (image) inner->_imageView.image = image;
				});
			});
		}];
	}
}

- (void)dealloc {
	[_thumbnailTask cancel];
}

- (void)doneTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)downloadTapped {
	if (!_allowDownload || !_asset.assetId.length) return;
	_spinner.hidden = NO;
	[_spinner startAnimating];
	NSString *extension = _asset.isImage ? @"jpg" : @"mp4";
	NSString *name = [NSString stringWithFormat:@"immich-share-%@.%@", _asset.assetId, extension];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	NSURL *destination = [NSURL fileURLWithPath:path];
	__weak typeof(self) weakSelf = self;
	[IMSharedLinkApi guestOriginalFileForAssetId:_asset.assetId
	                                  publicURL:_publicURL
	                             destinationURL:destination
	                                 completion:^(NSURL *fileURL, NSError *error) {
		IMGuestPreviewViewController *self = weakSelf;
		if (!self) return;
		[self->_spinner stopAnimating];
		if (!fileURL || error) {
			[self showError:error ?: [NSError errorWithDomain:IMApiErrorDomain
			                                             code:0
			                                         userInfo:@{NSLocalizedDescriptionKey : _(@"The shared file could not be downloaded.")}]];
			return;
		}
		UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];
		share.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
			(void)activityType;
			(void)completed;
			(void)returnedItems;
			(void)activityError;
			[[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
		};
		share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
		[self presentViewController:share animated:YES completion:nil];
	}];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Download")
	                                                                 message:error.localizedDescription ?: _(@"The shared file could not be downloaded.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end

@implementation SharedLinkGuestViewController

- (instancetype)initWithPublicURL:(NSURL *)publicURL {
	self = [super init];
	if (self) {
		_publicURL = [publicURL copy];
		_assets = @[];
		_imageCache = [[NSCache alloc] init];
		_imageCache.countLimit = 80;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Shared Link");
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                                                                                         target:self
	                                                                                         action:@selector(closeTapped)];
	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.minimumInteritemSpacing = kGuestSpacing;
	layout.minimumLineSpacing = kGuestSpacing;
	self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
	self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
	self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
	self.collectionView.dataSource = self;
	self.collectionView.delegate = self;
	[self.collectionView registerClass:[IMGuestAssetCell class] forCellWithReuseIdentifier:@"guest-asset"];
	[self.view addSubview:self.collectionView];
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.collectionView.backgroundView = self.statusLabel;
	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	self.spinner.hidesWhenStopped = YES;
	[self.view addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[
		[self.collectionView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];
	[self reload];
}

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)reload {
	if (self.loading) return;
	self.loading = YES;
	self.statusLabel.text = _(@"Loading shared photos…");
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMSharedLinkApi linkForPublicURL:self.publicURL completion:^(IMSharedLink *link, NSError *error) {
		SharedLinkGuestViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		[self.spinner stopAnimating];
		if (link) {
			[self applyLink:link];
			return;
		}
		NSInteger status = [IMApiClient HTTPStatusForError:error];
		if (status == 401 || status == 403) {
			self.statusLabel.text = _(@"This link is password protected. Tap to enter its password.");
			[self showPasswordPrompt:nil];
		} else {
			self.statusLabel.text = error.localizedDescription.length ? [NSString stringWithFormat:_(@"%@\nTap to retry."), error.localizedDescription] : _(@"Couldn't load this shared link. Tap to retry.");
		}
	}];
}

- (void)applyLink:(IMSharedLink *)link {
	self.link = link;
	self.assets = link.assets ?: @[];
	self.title = link.title.length ? link.title : _(@"Shared Link");
	self.statusLabel.text = self.assets.count ? nil : _(@"This shared link has no photos.");
	[self.collectionView reloadData];
}

- (void)showPasswordPrompt:(NSString *)message {
	if (self.passwordPromptVisible || !self.viewIfLoaded.window) return;
	self.passwordPromptVisible = YES;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Shared Link Password")
	                                                                 message:message ?: _(@"Enter the password for this shared link.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Password");
		field.secureTextEntry = YES;
		field.returnKeyType = UIReturnKeyGo;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
		self.passwordPromptVisible = NO;
	}]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Unlock") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		SharedLinkGuestViewController *self = weakSelf;
		if (!self) return;
		self.passwordPromptVisible = NO;
		NSString *password = alert.textFields.firstObject.text ?: @"";
		self.loading = YES;
		self.statusLabel.text = _(@"Unlocking shared link…");
		[self.spinner startAnimating];
		[IMSharedLinkApi loginForPublicURL:self.publicURL password:password completion:^(IMSharedLink *link, NSError *error) {
			SharedLinkGuestViewController *inner = weakSelf;
			if (!inner) return;
			inner.loading = NO;
			[inner.spinner stopAnimating];
			if (link) {
				[inner applyLink:link];
			} else {
				inner.statusLabel.text = error.localizedDescription ?: _(@"The password was not accepted.");
				[inner showPasswordPrompt:inner.statusLabel.text];
			}
		}];
	}]];
	[self presentViewController:alert animated:YES completion:^{
		[alert.textFields.firstObject becomeFirstResponder];
	}];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return self.assets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
	             cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	IMGuestAssetCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"guest-asset" forIndexPath:indexPath];
	if (indexPath.item < (NSInteger)self.assets.count) {
		[cell configureWithAsset:self.assets[indexPath.item] publicURL:self.publicURL imageCache:self.imageCache];
	}
	return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
	              layout:(UICollectionViewLayout *)collectionViewLayout
	 sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat width = collectionView.bounds.size.width;
	CGFloat side = (width - (kGuestColumns - 1) * kGuestSpacing) / kGuestColumns;
	return CGSizeMake(MAX(1, side), MAX(1, side));
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	[collectionView deselectItemAtIndexPath:indexPath animated:YES];
	if (indexPath.item >= (NSInteger)self.assets.count || !self.link) return;
	IMAsset *asset = self.assets[indexPath.item];
	UIImage *image = [self.imageCache objectForKey:asset.assetId];
	IMGuestPreviewViewController *preview = [[IMGuestPreviewViewController alloc] initWithAsset:asset
	                                                                                     publicURL:self.publicURL
	                                                                                          image:image
	                                                                                 allowDownload:self.link.allowDownload];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:preview];
	nav.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:nav animated:YES completion:nil];
}

@end
