#import "AssetViewController.h"
#import "AssetDetailViewController.h"
#import "AddToAlbumViewController.h"
#import "IMAssetApi.h"
#import "IMThumbCache.h"
#import "common.h"
#import <AVKit/AVKit.h>

#pragma mark - IMOcrOverlayView (private): visible, same-size text layer + drag-to-select

@interface IMOcrOverlayView : UIView
@property (nonatomic, copy, nullable) NSArray<IMOcrLine *> *lines; 
- (void)layoutBoxes; 
@end

@interface IMOcrOverlayView ()
@property (nonatomic, strong) NSArray<IMOcrLine *> *orderedLines; 
@property (nonatomic, strong) NSArray<UIView *> *boxViews;        
@property (nonatomic, strong) NSMutableIndexSet *selectedIndices;
@property (nonatomic) NSInteger anchorIndex;
@end

@implementation IMOcrOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_selectedIndices = [NSMutableIndexSet indexSet];
		_anchorIndex = NSNotFound;
		UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
		[self addGestureRecognizer:pan];
		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
		[self addGestureRecognizer:tap];
	}
	return self;
}

- (void)setLines:(nullable NSArray<IMOcrLine *> *)lines {
	_lines = lines;
	self.orderedLines = [(lines ?: @[]) sortedArrayUsingComparator:^NSComparisonResult(IMOcrLine *a, IMOcrLine *b) {
		CGFloat ay = round(a.normalizedRect.origin.y * 200);
		CGFloat by = round(b.normalizedRect.origin.y * 200);
		if (ay != by) {
			return ay < by ? NSOrderedAscending : NSOrderedDescending;
		}
		CGFloat ax = a.normalizedRect.origin.x, bx = b.normalizedRect.origin.x;
		return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
	}];
	[self clearSelection];
	[self rebuildBoxes];
}

- (void)rebuildBoxes {
	for (UIView *box in self.boxViews) {
		[box removeFromSuperview];
	}
	NSMutableArray<UIView *> *boxes = [NSMutableArray arrayWithCapacity:self.orderedLines.count];
	for (IMOcrLine *line in self.orderedLines) {
		UIView *box = [[UIView alloc] init];
		box.layer.cornerRadius = 2;
		box.clipsToBounds = YES;

		UILabel *label = [[UILabel alloc] init];
		label.text = line.text;
		label.numberOfLines = 1;
		label.textAlignment = NSTextAlignmentCenter;
		label.adjustsFontSizeToFitWidth = YES;
		label.minimumScaleFactor = 0.2;
		label.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
		[box addSubview:label];

		[self addSubview:box];
		[boxes addObject:box];
	}
	self.boxViews = boxes;
	[self applyHighlightStyling];
	[self layoutBoxes];
}

- (void)layoutBoxes {
	if (self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
		return;
	}
	[self.orderedLines enumerateObjectsUsingBlock:^(IMOcrLine *line, NSUInteger idx, BOOL *stop) {
		if (idx >= self.boxViews.count) {
			return;
		}
		UIView *box = self.boxViews[idx];
		CGRect r = line.normalizedRect;
		CGRect frame = CGRectMake(r.origin.x * self.bounds.size.width, r.origin.y * self.bounds.size.height,
		                          r.size.width * self.bounds.size.width, r.size.height * self.bounds.size.height);
		box.frame = frame;
		UILabel *label = box.subviews.firstObject;
		label.frame = box.bounds;
		label.font = [UIFont boldSystemFontOfSize:MAX(6, frame.size.height * 0.72)];
	}];
}

#pragma mark Selection

- (NSInteger)boxIndexAtPoint:(CGPoint)point {
	__block NSInteger found = NSNotFound;
	[self.boxViews enumerateObjectsUsingBlock:^(UIView *box, NSUInteger idx, BOOL *stop) {
		if (CGRectContainsPoint(box.frame, point)) {
			found = idx;
			*stop = YES;
		}
	}];
	return found;
}

- (void)selectRangeFrom:(NSInteger)a to:(NSInteger)b {
	NSInteger lo = MIN(a, b), hi = MAX(a, b);
	[self.selectedIndices removeAllIndexes];
	[self.selectedIndices addIndexesInRange:NSMakeRange(lo, hi - lo + 1)];
	[self applyHighlightStyling];
}

- (void)clearSelection {
	[self.selectedIndices removeAllIndexes];
	self.anchorIndex = NSNotFound;
	[self applyHighlightStyling];
}

- (void)applyHighlightStyling {
	[self.boxViews enumerateObjectsUsingBlock:^(UIView *box, NSUInteger idx, BOOL *stop) {
		BOOL selected = [self.selectedIndices containsIndex:idx];
		box.backgroundColor = selected ? [UIColor.systemBlueColor colorWithAlphaComponent:0.55]
		                                : [UIColor.systemYellowColor colorWithAlphaComponent:0.85];
		UILabel *label = box.subviews.firstObject;
		label.textColor = selected ? UIColor.whiteColor : UIColor.blackColor;
	}];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
	CGPoint point = [pan locationInView:self];
	NSInteger index = [self boxIndexAtPoint:point];
	switch (pan.state) {
		case UIGestureRecognizerStateBegan:
			if (index == NSNotFound) {
				return;
			}
			self.anchorIndex = index;
			[self selectRangeFrom:index to:index];
			break;
		case UIGestureRecognizerStateChanged:
			if (index != NSNotFound && self.anchorIndex != NSNotFound) {
				[self selectRangeFrom:self.anchorIndex to:index];
			}
			break;
		case UIGestureRecognizerStateEnded:
		case UIGestureRecognizerStateCancelled:
			if (self.selectedIndices.count > 0) {
				[self showCopyMenu];
			}
			self.anchorIndex = NSNotFound;
			break;
		default:
			break;
	}
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
	if (self.selectedIndices.count > 0) {
		[self clearSelection];
		[UIMenuController.sharedMenuController hideMenu];
	}
}

- (void)showCopyMenu {
	[self becomeFirstResponder];
	CGRect unionRect = CGRectNull;
	for (NSUInteger idx = self.selectedIndices.firstIndex; idx != NSNotFound;
	     idx = [self.selectedIndices indexGreaterThanIndex:idx]) {
		unionRect = CGRectUnion(unionRect, self.boxViews[idx].frame);
	}
	if (CGRectIsNull(unionRect)) {
		return;
	}
	if (@available(iOS 13.0, *)) {
		[UIMenuController.sharedMenuController showMenuFromView:self rect:unionRect];
	}
}

- (BOOL)canBecomeFirstResponder {
	return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(nullable id)sender {
	if (action == @selector(copy:)) {
		return self.selectedIndices.count > 0;
	}
	return NO;
}

- (void)copy:(nullable id)sender {
	NSMutableArray<NSString *> *texts = [NSMutableArray array];
	for (NSUInteger idx = self.selectedIndices.firstIndex; idx != NSNotFound;
	     idx = [self.selectedIndices indexGreaterThanIndex:idx]) {
		[texts addObject:self.orderedLines[idx].text];
	}
	UIPasteboard.generalPasteboard.string = [texts componentsJoinedByString:@"\n"];
	[self clearSelection];
}

@end

#pragma mark - AssetPageContentViewController (private, one per page)

@interface AssetPageContentViewController : UIViewController
@property (nonatomic, strong, readonly) IMAsset *asset;
@property (nonatomic, copy, nullable) void (^onOCRAvailabilityKnown)(BOOL hasText);
@property (nonatomic, strong, readonly, nullable) NSNumber *ocrHasText;
- (instancetype)initWithAsset:(IMAsset *)asset;
- (void)playIfVideo;
- (void)pauseIfVideo;
- (BOOL)canBeginDismissPan;
- (void)setOCRVisible:(BOOL)visible;
@end

@interface AssetPageContentViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) IMAsset *asset;
@property (nonatomic, strong, nullable) UIScrollView *scrollView;
@property (nonatomic, strong, nullable) UIImageView *imageView;
@property (nonatomic, strong, nullable) UIActivityIndicatorView *spinner;
@property (nonatomic, strong, nullable) AVPlayerViewController *playerViewController;
@property (nonatomic, strong, nullable) NSURLSessionTask *loadTask;
@property (nonatomic) BOOL hasFitInitialZoom;
@property (nonatomic, strong, nullable) IMOcrOverlayView *ocrOverlayView;
@property (nonatomic, strong, nullable) NSNumber *ocrHasText;
@property (nonatomic) BOOL ocrVisible;
@end

@implementation AssetPageContentViewController

- (instancetype)initWithAsset:(IMAsset *)asset {
	self = [super init];
	if (self) {
		_asset = asset;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.blackColor;

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];
	[self.spinner startAnimating];

	if (self.asset.isImage) {
		[self setUpImagePage];
	} else {
		[self setUpVideoPage];
	}
}

#pragma mark Image page

- (void)setUpImagePage {
	self.scrollView = [[UIScrollView alloc] init];
	self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.scrollView.delegate = self;
	self.scrollView.minimumZoomScale = 1.0;
	self.scrollView.maximumZoomScale = 4.0;
	self.scrollView.showsHorizontalScrollIndicator = NO;
	self.scrollView.showsVerticalScrollIndicator = NO;
	[self.view insertSubview:self.scrollView atIndex:0];

	self.imageView = [[UIImageView alloc] init];
	self.imageView.contentMode = UIViewContentModeScaleAspectFit;
	self.imageView.userInteractionEnabled = YES;
	[self.scrollView addSubview:self.imageView];

	self.ocrOverlayView = [[IMOcrOverlayView alloc] init];
	self.ocrOverlayView.hidden = YES;
	[self.imageView addSubview:self.ocrOverlayView];

	[NSLayoutConstraint activateConstraints:@[
		[self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	NSString *assetId = self.asset.assetId;
	__weak typeof(self) weakSelf = self;

	[[IMThumbCache shared] thumbnailForAssetId:assetId
	                                        size:IMAssetMediaSizePreview
	                                  completion:^(UIImage *_Nullable image) {
		    [weakSelf showImage:image];
	    }];

	[IMAssetApi ocrLinesForAssetId:assetId
	                     completion:^(NSArray<IMOcrLine *> *_Nullable lines, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    NSArray<IMOcrLine *> *ocrLines = lines ?: @[];
		    strongSelf.ocrHasText = @(ocrLines.count > 0);
		    strongSelf.ocrOverlayView.lines = ocrLines;
		    [strongSelf layoutOCROverlay];
		    if (strongSelf.onOCRAvailabilityKnown) {
			    strongSelf.onOCRAvailabilityKnown(ocrLines.count > 0);
		    }
	    }];

	self.loadTask = [IMAssetApi originalDataForAssetId:assetId
	                                          completion:^(NSData *_Nullable data, NSError *_Nullable error) {
		    if (!data) {
			    return;
		    }
		    UIImage *original = [UIImage imageWithData:data];
		    if (original) {
			    [weakSelf showImage:original];
		    }
	    }];
}

- (void)showImage:(nullable UIImage *)image {
	if (!image) {
		[self.spinner stopAnimating];
		return;
	}
	[self.spinner stopAnimating];

	CGFloat relativeZoom = 1.0;
	if (self.hasFitInitialZoom && self.scrollView.minimumZoomScale > 0) {
		relativeZoom = self.scrollView.zoomScale / self.scrollView.minimumZoomScale;
	}

	self.imageView.image = image;
	self.imageView.frame = (CGRect){ CGPointZero, image.size };
	self.scrollView.contentSize = image.size;
	[self fitImagePreservingRelativeZoom:relativeZoom];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (self.imageView.image && !self.hasFitInitialZoom) {
		[self fitImagePreservingRelativeZoom:1.0];
	} else {
		[self recenterImage];
	}
}

- (void)fitImagePreservingRelativeZoom:(CGFloat)relativeZoom {
	CGSize imageSize = self.imageView.image.size;
	CGSize boundsSize = self.scrollView.bounds.size;
	if (imageSize.width <= 0 || imageSize.height <= 0 || boundsSize.width <= 0) {
		return;
	}
	CGFloat fitScale = MIN(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height);
	self.scrollView.minimumZoomScale = MIN(1.0, fitScale);
	self.scrollView.maximumZoomScale = MAX(4.0, fitScale * 4);
	self.scrollView.zoomScale = self.scrollView.minimumZoomScale * relativeZoom;
	self.hasFitInitialZoom = YES;
	[self recenterImage];
}

- (void)recenterImage {
	if (!self.imageView.image) {
		return;
	}
	CGSize imageSize = self.imageView.image.size;
	CGSize boundsSize = self.scrollView.bounds.size;
	if (imageSize.width <= 0 || imageSize.height <= 0 || boundsSize.width <= 0) {
		return;
	}
	CGFloat scaledWidth = imageSize.width * self.scrollView.zoomScale;
	CGFloat scaledHeight = imageSize.height * self.scrollView.zoomScale;
	CGFloat offsetX = MAX(0, (boundsSize.width - scaledWidth) / 2);
	CGFloat offsetY = MAX(0, (boundsSize.height - scaledHeight) / 2);
	self.imageView.frame = CGRectMake(offsetX, offsetY, scaledWidth, scaledHeight);
	self.scrollView.contentSize = CGSizeMake(MAX(scaledWidth, boundsSize.width), MAX(scaledHeight, boundsSize.height));
	[self layoutOCROverlay];
}

- (nullable UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
	[self recenterImage];
}

#pragma mark OCR overlay

- (void)setOCRVisible:(BOOL)visible {
	if (!self.asset.isImage) {
		return;
	}
	self.ocrVisible = visible;
	self.ocrOverlayView.hidden = !visible;
	self.scrollView.panGestureRecognizer.enabled = !visible;
	if (!visible) {
		[self.ocrOverlayView clearSelection];
	}
}

- (void)layoutOCROverlay {
	if (self.imageView.bounds.size.width <= 0) {
		return;
	}
	self.ocrOverlayView.frame = self.imageView.bounds;
	[self.ocrOverlayView layoutBoxes];
}

#pragma mark Video page

- (void)setUpVideoPage {
	self.playerViewController = [[AVPlayerViewController alloc] init];
	self.playerViewController.showsPlaybackControls = YES;
	[self addChildViewController:self.playerViewController];
	self.playerViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
	self.playerViewController.view.backgroundColor = UIColor.blackColor;
	[self.view addSubview:self.playerViewController.view];
	[NSLayoutConstraint activateConstraints:@[
		[self.playerViewController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.playerViewController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.playerViewController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.playerViewController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
	[self.playerViewController didMoveToParentViewController:self];

	NSString *assetId = self.asset.assetId;
	__weak typeof(self) weakSelf = self;
	self.loadTask = [IMAssetApi videoPlaybackDataForAssetId:assetId
	                                              completion:^(NSData *_Nullable data, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    [strongSelf.spinner stopAnimating];
		    if (!strongSelf || !data) {
			    return;
		    }
		    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
		                                                      [NSString stringWithFormat:@"%@.mp4", assetId]];
		    if ([data writeToFile:tempPath atomically:YES]) {
			    strongSelf.playerViewController.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:tempPath]];
		    }
	    }];
}

- (void)playIfVideo {
	[self.playerViewController.player play];
}

- (void)pauseIfVideo {
	[self.playerViewController.player pause];
}

- (BOOL)canBeginDismissPan {
	if (!self.asset.isImage) {
		return YES; 
	}
	return self.scrollView.zoomScale <= self.scrollView.minimumZoomScale + 0.01;
}

- (void)dealloc {
	[self.loadTask cancel];
}

@end

#pragma mark - AssetViewController

@interface AssetViewController () <UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSArray<IMAsset *> *assets;
@property (nonatomic) NSInteger currentIndex;
@property (nonatomic, strong) UIPageViewController *pageViewController;
@property (nonatomic, strong) UIVisualEffectView *topBar;
@property (nonatomic, strong) UIVisualEffectView *bottomBar;
@property (nonatomic, strong) UIButton *ocrButton;
@property (nonatomic, strong) UIButton *addToAlbumButton;
@property (nonatomic) BOOL ocrOn;
@end

@implementation AssetViewController

+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets startIndex:(NSInteger)startIndex {
	AssetViewController *vc = [[AssetViewController alloc] init];
	vc.assets = assets;
	vc.currentIndex = startIndex;
	vc.modalPresentationStyle = UIModalPresentationFullScreen;
	vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
	return vc;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.blackColor;

	self.pageViewController = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll
	                                                              navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal
	                                                                            options:nil];
	self.pageViewController.dataSource = self;
	self.pageViewController.delegate = self;
	[self addChildViewController:self.pageViewController];
	self.pageViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.pageViewController.view];
	[NSLayoutConstraint activateConstraints:@[
		[self.pageViewController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.pageViewController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.pageViewController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.pageViewController.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
	[self.pageViewController didMoveToParentViewController:self];

	AssetPageContentViewController *first = [self pageForIndex:self.currentIndex];
	__weak typeof(self) weakSelf = self;
	[self.pageViewController setViewControllers:@[ first ]
	                                    direction:UIPageViewControllerNavigationDirectionForward
	                                     animated:NO
	                                   completion:^(BOOL finished) {
		    [first playIfVideo];
		    (void)weakSelf;
	    }];

	[self setUpChrome];

	UIPanGestureRecognizer *dismissPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
	dismissPan.delegate = self;
	[self.view addGestureRecognizer:dismissPan];
}

- (void)setUpChrome {
	self.topBar = [self blurBar];
	[self.view addSubview:self.topBar];

	UIButton *closeButton = [self chromeButtonWithSymbol:@"xmark.circle.fill"];
	[closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.topBar.contentView addSubview:closeButton];

	self.bottomBar = [self blurBar];
	[self.view addSubview:self.bottomBar];

	self.addToAlbumButton = [self chromeButtonWithSymbol:@"folder.badge.plus"];
	[self.addToAlbumButton addTarget:self action:@selector(addToAlbumTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.bottomBar.contentView addSubview:self.addToAlbumButton];

	UIButton *infoButton = [self chromeButtonWithSymbol:@"info.circle"];
	[infoButton addTarget:self action:@selector(infoTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.bottomBar.contentView addSubview:infoButton];

	self.ocrButton = [self chromeButtonWithSymbol:@"doc.text.viewfinder"];
	[self.ocrButton addTarget:self action:@selector(ocrTapped) forControlEvents:UIControlEventTouchUpInside];
	self.ocrButton.hidden = YES; 
	[self.bottomBar.contentView addSubview:self.ocrButton];

	[NSLayoutConstraint activateConstraints:@[
		[self.topBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.topBar.bottomAnchor constraintEqualToAnchor:closeButton.bottomAnchor constant:10],

		[closeButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
		[closeButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],

		[self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.bottomBar.topAnchor constraintEqualToAnchor:infoButton.topAnchor constant:-10],

		[self.addToAlbumButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
		[self.addToAlbumButton.centerYAnchor constraintEqualToAnchor:infoButton.centerYAnchor],

		[infoButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[infoButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-6],

		[self.ocrButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
		[self.ocrButton.centerYAnchor constraintEqualToAnchor:infoButton.centerYAnchor],
	]];
}

- (UIVisualEffectView *)blurBar {
	UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
	UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:effect];
	blur.translatesAutoresizingMaskIntoConstraints = NO;
	return blur;
}

- (UIButton *)chromeButtonWithSymbol:(NSString *)symbolName {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tintColor = UIColor.whiteColor;
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
		[button setImage:[UIImage systemImageNamed:symbolName withConfiguration:config] forState:UIControlStateNormal];
	}
	return button;
}

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)infoTapped {
	IMAsset *asset = self.assets[self.currentIndex];
	AssetDetailViewController *detail = [AssetDetailViewController detailViewControllerForAssetId:asset.assetId];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detail];
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)addToAlbumTapped {
	IMAsset *asset = self.assets[self.currentIndex];
	AddToAlbumViewController *picker = [AddToAlbumViewController pickerForAssetId:asset.assetId];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)ocrTapped {
	self.ocrOn = !self.ocrOn;
	if (@available(iOS 13.0, *)) {
		self.ocrButton.tintColor = self.ocrOn ? UIColor.systemYellowColor : UIColor.whiteColor;
	}
	AssetPageContentViewController *current = (AssetPageContentViewController *)self.pageViewController.viewControllers.firstObject;
	[current setOCRVisible:self.ocrOn];
}

#pragma mark Paging

- (AssetPageContentViewController *)pageForIndex:(NSInteger)index {
	AssetPageContentViewController *page = [[AssetPageContentViewController alloc] initWithAsset:self.assets[index]];
	__weak typeof(self) weakSelf = self;
	__weak AssetPageContentViewController *weakPage = page;
	page.onOCRAvailabilityKnown = ^(BOOL hasText) {
		typeof(self) strongSelf = weakSelf;
		if (strongSelf && strongSelf.pageViewController.viewControllers.firstObject == weakPage) {
			strongSelf.ocrButton.hidden = !hasText;
		}
	};
	return page;
}

- (NSInteger)indexOfPage:(AssetPageContentViewController *)page {
	return [self.assets indexOfObject:page.asset];
}

- (nullable UIViewController *)pageViewController:(UIPageViewController *)pageViewController
                    viewControllerBeforeViewController:(UIViewController *)viewController {
	NSInteger index = [self indexOfPage:(AssetPageContentViewController *)viewController];
	if (index == 0 || index == NSNotFound) {
		return nil;
	}
	return [self pageForIndex:index - 1];
}

- (nullable UIViewController *)pageViewController:(UIPageViewController *)pageViewController
                     viewControllerAfterViewController:(UIViewController *)viewController {
	NSInteger index = [self indexOfPage:(AssetPageContentViewController *)viewController];
	if (index == NSNotFound || index + 1 >= (NSInteger)self.assets.count) {
		return nil;
	}
	return [self pageForIndex:index + 1];
}

- (void)pageViewController:(UIPageViewController *)pageViewController
        didFinishAnimating:(BOOL)finished
   previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers
       transitionCompleted:(BOOL)completed {
	for (AssetPageContentViewController *previous in previousViewControllers) {
		[previous pauseIfVideo];
	}
	if (!completed) {
		return;
	}
	AssetPageContentViewController *current = (AssetPageContentViewController *)self.pageViewController.viewControllers.firstObject;
	self.currentIndex = [self indexOfPage:current];
	[current playIfVideo];

	self.ocrButton.hidden = !(current.asset.isImage && current.ocrHasText.boolValue);
	if (self.ocrOn) {
		[current setOCRVisible:YES]; 
	}
}

#pragma mark Swipe-down to dismiss

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
	UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
	CGPoint velocity = [pan velocityInView:self.view];
	if (fabs(velocity.y) <= fabs(velocity.x)) {
		return NO; 
	}
	AssetPageContentViewController *current = (AssetPageContentViewController *)self.pageViewController.viewControllers.firstObject;
	return [current canBeginDismissPan];
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)pan {
	CGPoint translation = [pan translationInView:self.view];
	switch (pan.state) {
		case UIGestureRecognizerStateChanged: {
			CGFloat progress = MAX(0, translation.y) / self.view.bounds.size.height;
			self.view.transform = CGAffineTransformMakeTranslation(0, MAX(0, translation.y));
			self.view.alpha = 1.0 - MIN(0.6, progress);
			break;
		}
		case UIGestureRecognizerStateEnded:
		case UIGestureRecognizerStateCancelled: {
			CGFloat velocityY = [pan velocityInView:self.view].y;
			if (translation.y > 120 || velocityY > 800) {
				[self dismissViewControllerAnimated:YES completion:nil];
			} else {
				[UIView animateWithDuration:0.25
				                 animations:^{
					                 self.view.transform = CGAffineTransformIdentity;
					                 self.view.alpha = 1.0;
				                 }];
			}
			break;
		}
		default:
			break;
	}
}

@end
