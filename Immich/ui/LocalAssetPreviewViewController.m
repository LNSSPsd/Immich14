#import "LocalAssetPreviewViewController.h"
#import "common.h"
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>

@interface LocalAssetPreviewViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic, strong, nullable) UIScrollView *scrollView;
@property (nonatomic, strong, nullable) UIImageView *imageView;
@property (nonatomic, strong, nullable) AVPlayerViewController *playerViewController;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic) PHImageRequestID imageRequestID;
@property (nonatomic) BOOL imageGeometryConfigured;
@end

@implementation LocalAssetPreviewViewController

+ (instancetype)previewWithAsset:(PHAsset *)asset {
	LocalAssetPreviewViewController *controller = [[self alloc] init];
	controller.asset = asset;
	return controller;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_imageRequestID = PHInvalidImageRequestID;
	}
	return self;
}

- (void)dealloc {
	if (self.imageRequestID != PHInvalidImageRequestID) {
		[[PHImageManager defaultManager] cancelImageRequest:self.imageRequestID];
		_imageRequestID = PHInvalidImageRequestID;
	}
	[self.playerViewController.player pause];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.blackColor;
	self.title = self.asset.mediaType == PHAssetMediaTypeVideo ? _(@"Pending video") : _(@"Pending photo");

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.spinner];
	[self.spinner startAnimating];

	self.errorLabel = [[UILabel alloc] init];
	self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.errorLabel.text = _(@"Couldn't load this local asset. Tap to retry.");
	self.errorLabel.textColor = UIColor.whiteColor;
	self.errorLabel.textAlignment = NSTextAlignmentCenter;
	self.errorLabel.numberOfLines = 0;
	self.errorLabel.hidden = YES;
	self.errorLabel.userInteractionEnabled = YES;
	[self.errorLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(retryLoad)]];
	[self.view addSubview:self.errorLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.errorLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.errorLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.errorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
		[self.errorLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
	]];

	if (self.asset.mediaType == PHAssetMediaTypeVideo) {
		[self startVideoLoad];
	} else {
		[self startImageLoad];
	}
}

- (void)showLoadError {
	[self.spinner stopAnimating];
	self.errorLabel.hidden = NO;
	[self.view bringSubviewToFront:self.errorLabel];
}

- (void)retryLoad {
	if (self.imageRequestID != PHInvalidImageRequestID) {
		[[PHImageManager defaultManager] cancelImageRequest:self.imageRequestID];
		self.imageRequestID = PHInvalidImageRequestID;
	}
	self.errorLabel.hidden = YES;
	[self.spinner startAnimating];
	if (self.asset.mediaType == PHAssetMediaTypeVideo) {
		[self startVideoLoad];
	} else {
		[self startImageLoad];
	}
}

- (void)startImageLoad {
	if (!self.asset) {
		[self showLoadError];
		return;
	}
	PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
	options.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
	options.resizeMode = PHImageRequestOptionsResizeModeFast;
	options.version = PHImageRequestOptionsVersionCurrent;
	options.networkAccessAllowed = YES;
	CGFloat longEdge = MAX(UIScreen.mainScreen.nativeBounds.size.width,
	                       UIScreen.mainScreen.nativeBounds.size.height);
	CGFloat maxPixelSize = MIN(4096.0, MAX(1024.0, longEdge * 2.0));
	__weak typeof(self) weakSelf = self;
	self.imageRequestID = [[PHImageManager defaultManager]
	    requestImageForAsset:self.asset
              targetSize:CGSizeMake(maxPixelSize, maxPixelSize)
             contentMode:PHImageContentModeAspectFit
                 options:options
           resultHandler:^(UIImage *_Nullable image, NSDictionary *_Nullable info) {
		    dispatch_async(dispatch_get_main_queue(), ^{
			    LocalAssetPreviewViewController *strongSelf = weakSelf;
			    if (!strongSelf) return;
			    BOOL cancelled = [info[PHImageCancelledKey] boolValue];
			    NSError *error = [info[PHImageErrorKey] isKindOfClass:[NSError class]] ? info[PHImageErrorKey] : nil;
			    if (cancelled || error) {
				    if (!image && !cancelled) [strongSelf showLoadError];
				    return;
			    }
			    if (!image) {
				    [strongSelf showLoadError];
				    return;
			    }
			    strongSelf.imageView.image = image;
			    strongSelf.imageView.accessibilityLabel = _(@"Pending photo");
			    strongSelf.errorLabel.hidden = YES;
			    [strongSelf.spinner stopAnimating];
			    [strongSelf configureImageGeometry];
		    });
	       }];
}

- (void)configureImageGeometry {
	if (!self.imageView.image || !self.scrollView || self.scrollView.bounds.size.width <= 0 ||
	    self.scrollView.bounds.size.height <= 0) return;
	CGSize size = self.imageView.image.size;
	if (size.width <= 0 || size.height <= 0) return;
	self.imageView.frame = (CGRect){ CGPointZero, size };
	self.scrollView.contentSize = size;
	CGFloat fit = MIN(self.scrollView.bounds.size.width / size.width,
	                  self.scrollView.bounds.size.height / size.height);
	self.scrollView.minimumZoomScale = MIN(1.0, fit);
	self.scrollView.maximumZoomScale = MAX(4.0, fit * 4.0);
	if (!self.imageGeometryConfigured) {
		self.scrollView.zoomScale = self.scrollView.minimumZoomScale;
		self.imageGeometryConfigured = YES;
	}
	[self centerImage];
}

- (void)centerImage {
	if (!self.imageView.image) return;
	CGSize scaled = CGSizeMake(self.imageView.bounds.size.width * self.scrollView.zoomScale,
	                           self.imageView.bounds.size.height * self.scrollView.zoomScale);
	self.scrollView.contentInset = UIEdgeInsetsMake(MAX(0, (self.scrollView.bounds.size.height - scaled.height) / 2.0),
	                                                 MAX(0, (self.scrollView.bounds.size.width - scaled.width) / 2.0),
	                                                 0,
	                                                 0);
}

- (void)startVideoLoad {
	if (!self.asset) {
		[self showLoadError];
		return;
	}
	PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
	options.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;
	options.version = PHVideoRequestOptionsVersionCurrent;
	options.networkAccessAllowed = YES;
	__weak typeof(self) weakSelf = self;
	self.imageRequestID = [[PHImageManager defaultManager]
	    requestPlayerItemForVideo:self.asset
                        options:options
                  resultHandler:^(AVPlayerItem *_Nullable playerItem, NSDictionary *_Nullable info) {
		    dispatch_async(dispatch_get_main_queue(), ^{
			    LocalAssetPreviewViewController *strongSelf = weakSelf;
			    if (!strongSelf) return;
			    BOOL cancelled = [info[PHImageCancelledKey] boolValue];
			    NSError *error = [info[PHImageErrorKey] isKindOfClass:[NSError class]] ? info[PHImageErrorKey] : nil;
			    if (cancelled || error || !playerItem) {
				    if (!cancelled) [strongSelf showLoadError];
				    return;
			    }
			    strongSelf.imageRequestID = PHInvalidImageRequestID;
			    AVPlayerViewController *playerController = [[AVPlayerViewController alloc] init];
			    playerController.player = [AVPlayer playerWithPlayerItem:playerItem];
			    playerController.showsPlaybackControls = YES;
			    playerController.videoGravity = AVLayerVideoGravityResizeAspect;
			    strongSelf.playerViewController = playerController;
			    [strongSelf addChildViewController:playerController];
			    playerController.view.translatesAutoresizingMaskIntoConstraints = NO;
			    [strongSelf.view insertSubview:playerController.view atIndex:0];
			    [NSLayoutConstraint activateConstraints:@[
				    [playerController.view.topAnchor constraintEqualToAnchor:strongSelf.view.topAnchor],
				    [playerController.view.leadingAnchor constraintEqualToAnchor:strongSelf.view.leadingAnchor],
				    [playerController.view.trailingAnchor constraintEqualToAnchor:strongSelf.view.trailingAnchor],
				    [playerController.view.bottomAnchor constraintEqualToAnchor:strongSelf.view.bottomAnchor],
			    ]];
			    [playerController didMoveToParentViewController:strongSelf];
			    strongSelf.errorLabel.hidden = YES;
			    [strongSelf.spinner stopAnimating];
			    [playerController.player play];
		    });
	       }];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self configureImageGeometry];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
	[self centerImage];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.isMovingFromParentViewController || self.isBeingDismissed) {
		[self.playerViewController.player pause];
		if (self.imageRequestID != PHInvalidImageRequestID) {
			[[PHImageManager defaultManager] cancelImageRequest:self.imageRequestID];
			self.imageRequestID = PHInvalidImageRequestID;
		}
	}
}

- (void)loadView {
	[super loadView];
	if (self.asset.mediaType != PHAssetMediaTypeVideo) {
		self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
		self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
		self.scrollView.delegate = self;
		self.scrollView.minimumZoomScale = 1.0;
		self.scrollView.maximumZoomScale = 4.0;
		self.scrollView.showsHorizontalScrollIndicator = NO;
		self.scrollView.showsVerticalScrollIndicator = NO;
		[self.view insertSubview:self.scrollView atIndex:0];
		self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
		self.imageView.contentMode = UIViewContentModeScaleAspectFit;
		self.imageView.userInteractionEnabled = YES;
		self.imageView.isAccessibilityElement = YES;
		[self.scrollView addSubview:self.imageView];
		[NSLayoutConstraint activateConstraints:@[
			[self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
			[self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
			[self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
			[self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		]];
	}
}

@end
