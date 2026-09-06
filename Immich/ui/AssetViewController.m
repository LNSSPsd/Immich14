#import "AssetViewController.h"
#import "AssetDetailViewController.h"
#import "AssetEditViewController.h"
#import "AddToAlbumViewController.h"
#import "IMAssetApi.h"
#import "IMSharedLinkApi.h"
#import "SharedLinkEditorViewController.h"
#import "IMThumbCache.h"
#import "IMSession.h"
#import "common.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <PhotosUI/PhotosUI.h>
#import <objc/message.h>

static NSString *IMVideoCacheDirectory(void) {
	return [NSTemporaryDirectory() stringByAppendingPathComponent:@"IMVideoCache"];
}

static NSString *IMLivePairDirectory(void) {
	return [NSTemporaryDirectory() stringByAppendingPathComponent:@"IMLiveCache"];
}

static CGFloat IMViewerMaxPixelSize(void) {
	CGRect native = UIScreen.mainScreen.nativeBounds;
	CGFloat longEdge = MAX(native.size.width, native.size.height);
	return MIN(4096, longEdge * 2);
}

static UIImage *_Nullable IMDownsampledImageFromData(NSData *data, CGFloat maxPixelSize) {
	CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
	if (!source) {
		return nil;
	}
	NSDictionary *options = @{
		(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
		(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
		(__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
		(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
	};
	CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
	CFRelease(source);
	if (!cgImage) {
		return nil;
	}
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	return image;
}

static UIImage *_Nullable IMDownsampledImageFromURL(NSURL *url, CGFloat maxPixelSize) {
	if (!url.isFileURL || url.path.length == 0) {
		return nil;
	}
	CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
	if (!source) {
		return nil;
	}
	NSDictionary *options = @{
		(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
		(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
		(__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
		(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize),
	};
	CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
	CFRelease(source);
	if (!cgImage) {
		return nil;
	}
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	return image;
}

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
@property (nonatomic, strong, nullable) UIImage *placeholderImage;
- (instancetype)initWithAsset:(IMAsset *)asset;
- (void)playIfVideo;
- (void)pauseIfVideo;
- (BOOL)canBeginDismissPan;
- (nullable UIImageView *)transitionImageViewForDismissal;
- (void)setOCRVisible:(BOOL)visible;
- (void)setEditedImage:(nullable UIImage *)image;
- (void)reloadEditedImage;
@end

@interface AssetPageContentViewController () <UIScrollViewDelegate, PHLivePhotoViewDelegate>
@property (nonatomic, strong) IMAsset *asset;
@property (nonatomic, strong, nullable) UIScrollView *scrollView;
@property (nonatomic, strong, nullable) UIImageView *imageView;
@property (nonatomic, strong, nullable) UIActivityIndicatorView *spinner;
@property (nonatomic, strong, nullable) NSURLSessionTask *loadTask;
@property (nonatomic, strong, nullable) UILabel *errorLabel;
@property (nonatomic) BOOL wantsAutoplay;
@property (nonatomic) BOOL hasFitInitialZoom;
@property (nonatomic) BOOL prefersEditedMedia;
@property (nonatomic, strong, nullable) IMOcrOverlayView *ocrOverlayView;
@property (nonatomic, strong, nullable) NSNumber *ocrHasText;
@property (nonatomic) BOOL ocrVisible;

@property (nonatomic, strong, nullable) AVPlayer *player;
@property (nonatomic, strong, nullable) AVPlayerLayer *playerLayer;
@property (nonatomic, strong, nullable) UIImageView *posterView; 
@property (nonatomic, copy, nullable) NSString *videoFilePath;
@property (nonatomic, strong, nullable) UIVisualEffectView *videoControlsBar;
@property (nonatomic, strong, nullable) UIButton *playPauseButton;
@property (nonatomic, strong, nullable) UIButton *muteButton;
@property (nonatomic, strong, nullable) UISlider *videoSlider;
@property (nonatomic, strong, nullable) UILabel *elapsedLabel;
@property (nonatomic, strong, nullable) UILabel *remainingLabel;
@property (nonatomic, strong, nullable) id timeObserverToken;
@property (nonatomic) BOOL scrubbing;
@property (nonatomic) BOOL scrubbingWasPlaying;
@property (nonatomic) BOOL playbackReachedEnd;

@property (nonatomic, strong, nullable) NSURLSessionTask *liveVideoTask;
@property (nonatomic, copy, nullable) NSString *livePairImagePath;
@property (nonatomic, copy, nullable) NSString *livePairVideoPath;
@property (nonatomic, strong, nullable) PHLivePhoto *livePhoto;
@property (nonatomic, strong, nullable) PHLivePhotoView *livePhotoView;
@property (nonatomic, strong, nullable) UIVisualEffectView *liveBadgeView;
@property (nonatomic) PHLivePhotoRequestID livePhotoRequestId;
@end

static void *IMPlayerLayerReadyForDisplayContext = &IMPlayerLayerReadyForDisplayContext;

static NSString *IMTimeString(NSTimeInterval seconds) {
	if (!isfinite(seconds) || seconds < 0) {
		seconds = 0;
	}
	NSInteger total = (NSInteger)(seconds + 0.5);
	return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

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

	self.errorLabel = [[UILabel alloc] init];
	self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.errorLabel.text = _(@"Couldn't load. Tap to retry.");
	self.errorLabel.textColor = UIColor.whiteColor;
	self.errorLabel.textAlignment = NSTextAlignmentCenter;
	self.errorLabel.numberOfLines = 0;
	self.errorLabel.hidden = YES;
	self.errorLabel.userInteractionEnabled = YES;
	[self.errorLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(retryLoad)]];
	[self.view addSubview:self.errorLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.errorLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.errorLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.errorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
	]];

	if (self.asset.isImage) {
		[self setUpImagePage];
	} else {
		[self setUpVideoPage];
	}
}

- (void)showLoadError {
	[self.spinner stopAnimating];
	if (self.asset.isImage && self.imageView.image) {
		return; 
	}
	self.errorLabel.hidden = NO;
	[self.view bringSubviewToFront:self.errorLabel];
}

- (void)retryLoad {
	if (!self.errorLabel.hidden) {
		self.errorLabel.hidden = YES;
		[self.spinner startAnimating];
		if (self.asset.isImage) {
			[self startImageLoad];
		} else {
			[self startVideoLoad];
		}
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

	if (self.placeholderImage) {
		[self showImage:self.placeholderImage];
	}

	NSString *assetId = self.asset.assetId;
	__weak typeof(self) weakSelf = self;

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

	[self startImageLoad];
}

- (void)startImageLoad {
	NSString *assetId = self.asset.assetId;
	__weak typeof(self) weakSelf = self;

	[[IMThumbCache shared] thumbnailForAssetId:assetId
	                                        size:IMAssetMediaSizePreview
	                                  completion:^(UIImage *_Nullable image) {
		    [weakSelf showImage:image];
	    }];

	CGFloat maxPixelSize = IMViewerMaxPixelSize();
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"IMOriginalCache"];
	NSString *suffix = self.prefersEditedMedia ? @"edited" : @"original";
	NSString *fileName = [NSString stringWithFormat:@"%@-%@-%@", assetId, suffix, [[NSUUID UUID] UUIDString]];
	NSURL *destinationURL = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:fileName]];
	self.loadTask = [IMAssetApi originalFileForAssetId:assetId
	                                               edited:self.prefersEditedMedia
	                                      destinationURL:destinationURL
	                                          completion:^(NSURL *_Nullable fileURL, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    if (!fileURL) {
			    [strongSelf showLoadError];
			    return;
		    }
		    if (!strongSelf.prefersEditedMedia && strongSelf.asset.livePhotoVideoId) {
			    NSData *pairData = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:NULL];
			    if (pairData) [strongSelf stageLivePairImageData:pairData];
		    }
		    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			    UIImage *original = IMDownsampledImageFromURL(fileURL, maxPixelSize);
			    [[NSFileManager defaultManager] removeItemAtURL:fileURL error:NULL];
			    dispatch_async(dispatch_get_main_queue(), ^{
				    typeof(self) innerSelf = weakSelf;
				    if (!innerSelf) {
					    return;
				    }
				    if (original) {
					    [innerSelf showImage:original];
				    } else {
					    [innerSelf showLoadError];
				    }
			    });
		    });
	    }];
}

- (void)showImage:(nullable UIImage *)image {
	if (!image) {
		return;
	}
	[self.spinner stopAnimating];
	self.errorLabel.hidden = YES;

	CGFloat relativeZoom = 1.0;
	if (self.hasFitInitialZoom && self.scrollView.minimumZoomScale > 0) {
		relativeZoom = self.scrollView.zoomScale / self.scrollView.minimumZoomScale;
	}

	self.imageView.image = image;
	self.imageView.frame = (CGRect){ CGPointZero, image.size };
	self.scrollView.contentSize = image.size;
	[self fitImagePreservingRelativeZoom:relativeZoom];
}

- (void)setEditedImage:(nullable UIImage *)image {
	if (!self.asset.isImage) {
		return;
	}
	if (image) {
		self.prefersEditedMedia = YES;
		[self showImage:image];
		return;
	}
	self.prefersEditedMedia = NO;
	[self startImageLoad];
}

- (void)reloadEditedImage {
	if (!self.asset.isImage) {
		return;
	}
	NSString *assetId = self.asset.assetId;
	CGFloat maxPixelSize = IMViewerMaxPixelSize();
	__weak typeof(self) weakSelf = self;
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"IMOriginalCache"];
	NSString *fileName = [NSString stringWithFormat:@"%@-edited-%@", assetId, [[NSUUID UUID] UUIDString]];
	NSURL *destinationURL = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:fileName]];
	[IMAssetApi originalFileForAssetId:assetId
	                             edited:YES
	                    destinationURL:destinationURL
	                        completion:^(NSURL *_Nullable fileURL, NSError *_Nullable error) {
		if (!fileURL) {
			return; 
		}
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			UIImage *edited = IMDownsampledImageFromURL(fileURL, maxPixelSize);
			[[NSFileManager defaultManager] removeItemAtURL:fileURL error:NULL];
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (strongSelf && edited) {
					[strongSelf showImage:edited];
				}
			});
		});
	}];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (!self.asset.isImage) {
		if (!self.playerLayer.hidden) {
			[CATransaction begin];
			[CATransaction setDisableActions:YES];
			self.playerLayer.frame = self.view.bounds;
			[CATransaction commit];
			if (!self.posterView.hidden) {
				self.posterView.frame = self.view.bounds;
			}
		}
		return;
	}
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
	if (visible && !self.ocrHasText.boolValue) {
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
	self.posterView = [[UIImageView alloc] initWithFrame:self.view.bounds];
	self.posterView.contentMode = UIViewContentModeScaleAspectFit;
	self.posterView.image = self.placeholderImage;
	[self.view insertSubview:self.posterView atIndex:0];

	NSString *assetId = self.asset.assetId;
	__weak typeof(self) weakSelf = self;
	[[IMThumbCache shared] thumbnailForAssetId:assetId
	                                        size:IMAssetMediaSizePreview
	                                  completion:^(UIImage *_Nullable image) {
		    typeof(self) strongSelf = weakSelf;
		    if (strongSelf && image && !strongSelf.playerLayer.readyForDisplay) {
			    strongSelf.posterView.image = image;
		    }
	    }];

	[self setUpVideoControls];
	[self startVideoLoad];
}

- (UILabel *)makeVideoTimeLabel {
	UILabel *label = [[UILabel alloc] init];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.textColor = UIColor.whiteColor;
	label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
	return label;
}

- (UIButton *)makeVideoControlButton {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tintColor = UIColor.whiteColor;
	return button;
}

- (void)setUpVideoControls {
	UIVisualEffectView *bar = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
	bar.translatesAutoresizingMaskIntoConstraints = NO;
	bar.layer.cornerRadius = 12;
	bar.clipsToBounds = YES;
	[self.view addSubview:bar];
	self.videoControlsBar = bar;

	self.playPauseButton = [self makeVideoControlButton];
	[self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
	[bar.contentView addSubview:self.playPauseButton];

	self.muteButton = [self makeVideoControlButton];
	[self.muteButton addTarget:self action:@selector(muteTapped) forControlEvents:UIControlEventTouchUpInside];
	[bar.contentView addSubview:self.muteButton];

	self.elapsedLabel = [self makeVideoTimeLabel];
	[bar.contentView addSubview:self.elapsedLabel];
	self.remainingLabel = [self makeVideoTimeLabel];
	[bar.contentView addSubview:self.remainingLabel];

	self.videoSlider = [[UISlider alloc] init];
	self.videoSlider.translatesAutoresizingMaskIntoConstraints = NO;
	self.videoSlider.minimumTrackTintColor = UIColor.whiteColor;
	self.videoSlider.maximumTrackTintColor = [UIColor.whiteColor colorWithAlphaComponent:0.3];
	[self.videoSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
	[self.videoSlider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
	[self.videoSlider addTarget:self
	                      action:@selector(sliderTouchUp)
	            forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
	[bar.contentView addSubview:self.videoSlider];

	[NSLayoutConstraint activateConstraints:@[
		[bar.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
		[bar.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
		[bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-58],
		[bar.heightAnchor constraintEqualToConstant:44],

		[self.playPauseButton.leadingAnchor constraintEqualToAnchor:bar.contentView.leadingAnchor constant:6],
		[self.playPauseButton.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor],
		[self.playPauseButton.widthAnchor constraintEqualToConstant:32],
		[self.playPauseButton.heightAnchor constraintEqualToAnchor:bar.contentView.heightAnchor],

		[self.elapsedLabel.leadingAnchor constraintEqualToAnchor:self.playPauseButton.trailingAnchor constant:2],
		[self.elapsedLabel.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor],

		[self.videoSlider.leadingAnchor constraintEqualToAnchor:self.elapsedLabel.trailingAnchor constant:8],
		[self.videoSlider.trailingAnchor constraintEqualToAnchor:self.remainingLabel.leadingAnchor constant:-8],
		[self.videoSlider.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor],

		[self.remainingLabel.trailingAnchor constraintEqualToAnchor:self.muteButton.leadingAnchor constant:-2],
		[self.remainingLabel.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor],

		[self.muteButton.trailingAnchor constraintEqualToAnchor:bar.contentView.trailingAnchor constant:-6],
		[self.muteButton.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor],
		[self.muteButton.widthAnchor constraintEqualToConstant:32],
		[self.muteButton.heightAnchor constraintEqualToAnchor:bar.contentView.heightAnchor],
	]];

	[self updatePlayPauseButton];
	[self updateMuteButton];
	[self updateTimeLabelsForCurrent:0 duration:self.asset.durationMs / 1000.0];
}

- (void)startVideoLoad {
	NSString *assetId = self.asset.assetId;
	NSString *cachePath = [IMVideoCacheDirectory() stringByAppendingPathComponent:
	                                                   [NSString stringWithFormat:@"%@.mp4", assetId]];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if ([fileManager fileExistsAtPath:cachePath]) {
		[fileManager setAttributes:@{ NSFileModificationDate: [NSDate date] } ofItemAtPath:cachePath error:NULL];
		[self attachPlayerWithPath:cachePath];
		return;
	}
	__weak typeof(self) weakSelf = self;
	self.loadTask = [IMAssetApi videoPlaybackFileForAssetId:assetId
	                                           destinationURL:[NSURL fileURLWithPath:cachePath]
	                                               completion:^(NSURL *_Nullable fileURL, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    if (!fileURL) {
			    [strongSelf showLoadError];
			    return;
		    }
		    [strongSelf attachPlayerWithPath:fileURL.path ?: cachePath];
	    }];
}

- (void)attachPlayerWithPath:(NSString *)path {
	[self.spinner stopAnimating];
	self.errorLabel.hidden = YES;
	self.videoFilePath = path;

	self.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
	self.player.muted = YES; 

	self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
	self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
	self.playerLayer.frame = self.view.bounds;
	[self.view.layer insertSublayer:self.playerLayer above:self.posterView.layer];
	[self.playerLayer addObserver:self
	                    forKeyPath:@"readyForDisplay"
	                       options:0
	                       context:IMPlayerLayerReadyForDisplayContext];

	__weak typeof(self) weakSelf = self;
	self.timeObserverToken = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.25, 600)
	                                                                    queue:dispatch_get_main_queue()
	                                                               usingBlock:^(CMTime time) {
		    [weakSelf updateVideoProgress];
	    }];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(playerDidPlayToEnd:)
	                                              name:AVPlayerItemDidPlayToEndTimeNotification
	                                            object:self.player.currentItem];

	if (self.wantsAutoplay) {
		[self.player play];
	}
	[self updatePlayPauseButton];
	[self updateVideoProgress];
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                      ofObject:(nullable id)object
                        change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(nullable void *)context {
	if (context == IMPlayerLayerReadyForDisplayContext) {
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (strongSelf && strongSelf.playerLayer.readyForDisplay) {
				strongSelf.posterView.hidden = YES;
			}
		});
		return;
	}
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark Video controls

- (NSTimeInterval)videoDuration {
	NSTimeInterval duration = CMTimeGetSeconds(self.player.currentItem.duration);
	if (!isfinite(duration) || duration <= 0) {
		duration = self.asset.durationMs / 1000.0;
	}
	return duration;
}

- (void)updateTimeLabelsForCurrent:(NSTimeInterval)current duration:(NSTimeInterval)duration {
	self.elapsedLabel.text = IMTimeString(current);
	self.remainingLabel.text = [@"-" stringByAppendingString:IMTimeString(MAX(0, duration - current))];
}

- (void)updateVideoProgress {
	if (!self.player || self.scrubbing) {
		return;
	}
	NSTimeInterval duration = [self videoDuration];
	NSTimeInterval current = CMTimeGetSeconds(self.player.currentTime);
	if (!isfinite(current) || current < 0) {
		current = 0;
	}
	self.videoSlider.value = duration > 0 ? (float)(current / duration) : 0;
	[self updateTimeLabelsForCurrent:current duration:duration];
	[self updatePlayPauseButton];
}

- (void)updatePlayPauseButton {
	BOOL playing = self.player.rate != 0;
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
		[self.playPauseButton setImage:[UIImage systemImageNamed:(playing ? @"pause.fill" : @"play.fill")
		                                        withConfiguration:config]
		                      forState:UIControlStateNormal];
	}
}

- (void)updateMuteButton {
	BOOL muted = self.player ? self.player.muted : YES;
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
		[self.muteButton setImage:[UIImage systemImageNamed:(muted ? @"speaker.slash.fill" : @"speaker.wave.2.fill")
		                                   withConfiguration:config]
		                 forState:UIControlStateNormal];
	}
}

- (void)playPauseTapped {
	if (!self.player) {
		return;
	}
	if (self.player.rate != 0) {
		self.wantsAutoplay = NO;
		[self.player pause];
	} else {
		if (self.playbackReachedEnd) {
			self.playbackReachedEnd = NO;
			[self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
		}
		[self.player play];
	}
	[self updatePlayPauseButton];
}

- (void)muteTapped {
	if (!self.player) {
		return;
	}
	BOOL nowMuted = !self.player.muted;
	self.player.muted = nowMuted;
	if (!nowMuted) {
		Class sessionClass = NSClassFromString(@"AVAudioSession");
		id session = ((id (*)(Class, SEL))objc_msgSend)(sessionClass, @selector(sharedInstance));
		if (session) {
			((BOOL (*)(id, SEL, NSString *, NSError **))objc_msgSend)(
			    session, @selector(setCategory:error:), @"AVAudioSessionCategoryPlayback", NULL);
			((BOOL (*)(id, SEL, BOOL, NSError **))objc_msgSend)(session, @selector(setActive:error:), YES, NULL);
		}
	}
	[self updateMuteButton];
}

- (void)sliderTouchDown {
	self.scrubbing = YES;
	self.scrubbingWasPlaying = self.player.rate != 0;
	[self.player pause];
}

- (void)sliderChanged {
	NSTimeInterval duration = [self videoDuration];
	NSTimeInterval target = self.videoSlider.value * duration;
	[self updateTimeLabelsForCurrent:target duration:duration];
	[self.player seekToTime:CMTimeMakeWithSeconds(target, 600)
	         toleranceBefore:kCMTimePositiveInfinity
	          toleranceAfter:kCMTimePositiveInfinity];
}

- (void)sliderTouchUp {
	NSTimeInterval duration = [self videoDuration];
	NSTimeInterval target = self.videoSlider.value * duration;
	[self.player seekToTime:CMTimeMakeWithSeconds(target, 600)
	         toleranceBefore:kCMTimeZero
	          toleranceAfter:kCMTimeZero];
	self.scrubbing = NO;
	self.playbackReachedEnd = NO;
	if (self.scrubbingWasPlaying) {
		[self.player play];
	}
	[self updatePlayPauseButton];
}

- (void)playerDidPlayToEnd:(NSNotification *)note {
	self.playbackReachedEnd = YES;
	self.wantsAutoplay = NO;
	[self updatePlayPauseButton];
}

- (void)playIfVideo {
	if (self.asset.isImage) {
		return;
	}
	self.wantsAutoplay = YES; 
	if (self.playbackReachedEnd) {
		self.playbackReachedEnd = NO;
		[self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
	}
	[self.player play];
	[self updatePlayPauseButton];
}

- (void)pauseIfVideo {
	self.wantsAutoplay = NO;
	[self.player pause];
	[self updatePlayPauseButton];
}

- (BOOL)canBeginDismissPan {
	if (!self.asset.isImage) {
		return YES; 
	}
	return self.scrollView.zoomScale <= self.scrollView.minimumZoomScale + 0.01;
}

#pragma mark Zoom-dismiss anchor

- (nullable UIImageView *)transitionImageViewForDismissal {
	if (self.asset.isImage) {
		return self.imageView.image ? self.imageView : nil;
	}
	self.wantsAutoplay = NO;
	[self.player pause];
	UIImage *frame = [self currentVideoFrame] ?: self.posterView.image;
	if (!frame) {
		return nil; 
	}
	CGRect videoRect = self.playerLayer.readyForDisplay ? self.playerLayer.videoRect : CGRectZero;
	CGRect anchor;
	if (!CGRectIsEmpty(videoRect)) {
		anchor = [self.view.layer convertRect:videoRect fromLayer:self.playerLayer];
	} else {
		CGFloat ratio = frame.size.height > 0 ? frame.size.width / frame.size.height : 1;
		CGFloat width = self.view.bounds.size.width;
		CGFloat height = ratio > 0 ? width / ratio : width;
		if (height > self.view.bounds.size.height) {
			height = self.view.bounds.size.height;
			width = height * ratio;
		}
		anchor = CGRectMake((self.view.bounds.size.width - width) / 2,
		                    (self.view.bounds.size.height - height) / 2, width, height);
	}
	self.posterView.image = frame;
	self.posterView.frame = anchor; 
	self.posterView.hidden = NO;
	self.playerLayer.hidden = YES; 
	return self.posterView;
}

- (nullable UIImage *)currentVideoFrame {
	if (!self.videoFilePath || !self.player) {
		return nil;
	}
	AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:self.videoFilePath] options:nil];
	AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:avAsset];
	generator.appliesPreferredTrackTransform = YES;
	generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(1.0, 600);
	generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(1.0, 600);
	CGImageRef cgImage = [generator copyCGImageAtTime:self.player.currentTime actualTime:NULL error:NULL];
	if (!cgImage) {
		return nil;
	}
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	return image;
}

#pragma mark Live Photo

- (void)stageLivePairImageData:(NSData *)data {
	if (!self.asset.livePhotoVideoId || self.livePairImagePath) {
		return;
	}
	const uint8_t *bytes = data.bytes;
	BOOL isJpeg = data.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
	NSString *name = [NSString stringWithFormat:@"%@.%@", self.asset.assetId, isJpeg ? @"jpg" : @"heic"];
	NSString *path = [IMLivePairDirectory() stringByAppendingPathComponent:name];
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		[[NSFileManager defaultManager] createDirectoryAtPath:IMLivePairDirectory()
		                          withIntermediateDirectories:YES
		                                           attributes:nil
		                                                error:NULL];
		BOOL wrote = [data writeToFile:path atomically:YES];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || !wrote) {
				return;
			}
			strongSelf.livePairImagePath = path;
			[strongSelf requestLivePhotoIfPaired];
		});
	});
	[self fetchLivePairVideo];
}

- (void)fetchLivePairVideo {
	if (self.liveVideoTask || self.livePairVideoPath) {
		return;
	}
	NSString *liveVideoId = self.asset.livePhotoVideoId;
	NSString *path = [IMLivePairDirectory() stringByAppendingPathComponent:
	                                            [liveVideoId stringByAppendingPathExtension:@"mov"]];
	if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
		self.livePairVideoPath = path;
		[self requestLivePhotoIfPaired];
		return;
	}
	__weak typeof(self) weakSelf = self;
	self.liveVideoTask = [IMAssetApi videoPlaybackFileForAssetId:liveVideoId
	                                             destinationURL:[NSURL fileURLWithPath:path]
	                                                 completion:^(NSURL *_Nullable fileURL, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || !fileURL) {
			    return;
		    }
		    strongSelf.livePairVideoPath = fileURL.path ?: path;
		    [strongSelf requestLivePhotoIfPaired];
	    }];
}

- (void)requestLivePhotoIfPaired {
	if (!self.livePairImagePath || !self.livePairVideoPath || self.livePhoto ||
	    self.livePhotoRequestId != PHLivePhotoRequestIDInvalid) {
		return;
	}
	NSArray<NSURL *> *urls = @[
		[NSURL fileURLWithPath:self.livePairImagePath],
		[NSURL fileURLWithPath:self.livePairVideoPath],
	];
	__weak typeof(self) weakSelf = self;
	self.livePhotoRequestId =
	    [PHLivePhoto requestLivePhotoWithResourceFileURLs:urls
	                                     placeholderImage:self.imageView.image
	                                           targetSize:CGSizeZero
	                                          contentMode:PHImageContentModeAspectFit
	                                        resultHandler:^(PHLivePhoto *_Nullable livePhoto, NSDictionary *_Nullable info) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || !livePhoto) {
			    return;
		    }
		    strongSelf.livePhoto = livePhoto;
		    [strongSelf showLiveBadge];
	    }];
}

- (void)showLiveBadge {
	if (self.liveBadgeView) {
		return;
	}
	UIVisualEffectView *badge = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
	badge.translatesAutoresizingMaskIntoConstraints = NO;
	badge.layer.cornerRadius = 12;
	badge.clipsToBounds = YES;
	[self.view addSubview:badge];
	self.liveBadgeView = badge;

	UIImageView *icon = [[UIImageView alloc] init];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.tintColor = UIColor.whiteColor;
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
		icon.image = [UIImage systemImageNamed:@"livephoto" withConfiguration:config];
	}
	[badge.contentView addSubview:icon];

	UILabel *label = [[UILabel alloc] init];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = _(@"LIVE");
	label.textColor = UIColor.whiteColor;
	label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
	[badge.contentView addSubview:label];

	[NSLayoutConstraint activateConstraints:@[
		[badge.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
		[badge.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:52],
		[badge.heightAnchor constraintEqualToConstant:24],

		[icon.leadingAnchor constraintEqualToAnchor:badge.contentView.leadingAnchor constant:8],
		[icon.centerYAnchor constraintEqualToAnchor:badge.contentView.centerYAnchor],
		[label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:4],
		[label.trailingAnchor constraintEqualToAnchor:badge.contentView.trailingAnchor constant:-8],
		[label.centerYAnchor constraintEqualToAnchor:badge.contentView.centerYAnchor],
	]];

	UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self
	                                                                                    action:@selector(handleLivePhotoPress:)];
	press.minimumPressDuration = 0.3;
	[self.view addGestureRecognizer:press];
}

- (void)handleLivePhotoPress:(UILongPressGestureRecognizer *)press {
	if (!self.livePhoto) {
		return;
	}
	if (press.state == UIGestureRecognizerStateBegan) {
		if (!self.livePhotoView) {
			self.livePhotoView = [[PHLivePhotoView alloc] init];
			self.livePhotoView.delegate = self;
			self.livePhotoView.contentMode = UIViewContentModeScaleAspectFit;
			self.livePhotoView.userInteractionEnabled = NO;
		}
		self.livePhotoView.livePhoto = self.livePhoto;
		self.livePhotoView.frame = self.imageView.bounds; 
		[self.imageView addSubview:self.livePhotoView];
		[self.livePhotoView startPlaybackWithStyle:PHLivePhotoViewPlaybackStyleFull];
	} else if (press.state == UIGestureRecognizerStateEnded || press.state == UIGestureRecognizerStateCancelled ||
	           press.state == UIGestureRecognizerStateFailed) {
		[self.livePhotoView stopPlayback];
	}
}

- (void)livePhotoView:(PHLivePhotoView *)livePhotoView didEndPlaybackWithStyle:(PHLivePhotoViewPlaybackStyle)playbackStyle {
	[livePhotoView removeFromSuperview];
}

- (void)dealloc {
	[_loadTask cancel];
	[_liveVideoTask cancel];
	if (_timeObserverToken) {
		[_player removeTimeObserver:_timeObserverToken];
	}
	if (_playerLayer) {
		[_playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:IMPlayerLayerReadyForDisplayContext];
	}
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (_livePhotoRequestId != PHLivePhotoRequestIDInvalid) {
		[PHLivePhoto cancelLivePhotoRequestWithRequestID:_livePhotoRequestId];
	}
}

@end

#pragma mark - AssetViewController

static UIImage *_Nullable IMThumbRedrawnToRatio(UIImage *_Nullable thumb, double ratio) {
	if (!thumb || ratio <= 0 || thumb.size.width <= 0 || thumb.size.height <= 0) {
		return thumb;
	}
	CGFloat area = thumb.size.width * thumb.size.height;
	CGSize canvas = CGSizeMake(sqrt(area * ratio), sqrt(area / ratio));
	CGFloat fillScale = MAX(canvas.width / thumb.size.width, canvas.height / thumb.size.height);
	CGRect drawRect = CGRectMake((canvas.width - thumb.size.width * fillScale) / 2,
	                             (canvas.height - thumb.size.height * fillScale) / 2,
	                             thumb.size.width * fillScale,
	                             thumb.size.height * fillScale);
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.opaque = YES;
	format.scale = 1;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:canvas format:format];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[thumb drawInRect:drawRect];
	}];
}

@interface AssetViewController () <UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate, UIViewControllerTransitioningDelegate>
@property (nonatomic, strong) NSArray<IMAsset *> *assets;
@property (nonatomic) NSInteger currentIndex;
@property (nonatomic) BOOL readOnly;
@property (nonatomic) BOOL ownerAware;
@property (nonatomic, strong) UIPageViewController *pageViewController;
@property (nonatomic, strong) UIVisualEffectView *topBar;
@property (nonatomic, strong) UIVisualEffectView *bottomBar;
@property (nonatomic, strong) UIButton *slideshowButton;
@property (nonatomic, strong) UIButton *ocrButton;
@property (nonatomic, strong) UIButton *addToAlbumButton;
@property (nonatomic, strong) UIButton *favoriteButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIButton *editButton;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *favoriteOverrides;
@property (nonatomic) BOOL ocrOn;
@property (nonatomic) BOOL slideshowPlaying;
@property (nonatomic) BOOL slideshowTransitioning;
@property (nonatomic, strong, nullable) NSTimer *slideshowTimer;
- (BOOL)currentAssetAllowsMutations;
- (void)shareOriginalFileForAsset:(IMAsset *)asset;
- (void)createSharedLinkForAsset:(IMAsset *)asset;
- (void)editCurrentAsset;
- (void)updateEditButton;
- (void)presentShareFailure;
- (void)presentShareFailureWithMessage:(NSString *)message;
@end

@implementation AssetViewController

+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets startIndex:(NSInteger)startIndex {
	return [self viewerWithAssets:assets startIndex:startIndex readOnly:NO];
}

+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets
                       startIndex:(NSInteger)startIndex
                         readOnly:(BOOL)readOnly {
	return [self viewerWithAssets:assets startIndex:startIndex readOnly:readOnly ownerAware:NO];
}

+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets
                       startIndex:(NSInteger)startIndex
                         readOnly:(BOOL)readOnly
                        ownerAware:(BOOL)ownerAware {
	AssetViewController *vc = [[AssetViewController alloc] init];
	vc.assets = assets;
	vc.currentIndex = startIndex;
	vc.readOnly = readOnly;
	vc.ownerAware = ownerAware;
	vc.favoriteOverrides = [NSMutableDictionary dictionary];
	vc.modalPresentationStyle = UIModalPresentationFullScreen;
	vc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
	vc.transitioningDelegate = vc;
	return vc;
}

#pragma mark Zoom transition plumbing

- (IMAsset *)currentAsset {
	return self.assets[self.currentIndex];
}

- (BOOL)currentAssetAllowsMutations {
	if (self.readOnly || self.assets.count == 0 || self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.assets.count) {
		return NO;
	}
	if (!self.ownerAware) {
		return YES;
	}
	NSString *ownerId = self.currentAsset.ownerId;
	NSString *userId = IMSession.shared.userId;
	return ownerId.length > 0 && userId.length > 0 && [ownerId isEqualToString:userId];
}

- (nullable UIImageView *)currentPageImageView {
	AssetPageContentViewController *current =
	    (AssetPageContentViewController *)self.pageViewController.viewControllers.firstObject;
	return [current transitionImageViewForDismissal];
}

- (nullable id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                            presentingController:(UIViewController *)presenting
                                                                                sourceController:(UIViewController *)source {
	return self.zoomSource ? [IMZoomTransition transitionPresenting:YES] : nil;
}

- (nullable id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
	return self.zoomSource ? [IMZoomTransition transitionPresenting:NO] : nil;
}

+ (void)pruneVideoCache {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			NSFileManager *fileManager = [NSFileManager defaultManager];
			NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-3 * 24 * 60 * 60];
			for (NSString *directory in @[ IMVideoCacheDirectory(), IMLivePairDirectory() ]) {
				for (NSString *name in [fileManager contentsOfDirectoryAtPath:directory error:NULL]) {
					NSString *path = [directory stringByAppendingPathComponent:name];
					NSDate *modified = [fileManager attributesOfItemAtPath:path error:NULL][NSFileModificationDate];
					if (modified && [modified compare:cutoff] == NSOrderedAscending) {
						[fileManager removeItemAtPath:path error:NULL];
					}
				}
			}
		});
	});
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.blackColor;
	[AssetViewController pruneVideoCache];

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
	IMAsset *startAsset = self.assets[self.currentIndex];
	UIImage *gridThumb = [self.zoomSource zoomTransitionImageViewForAssetId:startAsset.assetId].image;
	first.placeholderImage = IMThumbRedrawnToRatio(gridThumb, startAsset.ratio);
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

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self stopSlideshow];
}

- (void)setUpChrome {
	self.topBar = [self blurBar];
	[self.view addSubview:self.topBar];

	UIButton *closeButton = [self chromeButtonWithSymbol:@"xmark.circle.fill"];
	[closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.topBar.contentView addSubview:closeButton];
	self.slideshowButton = [self chromeButtonWithSymbol:@"play.circle"];
	self.slideshowButton.accessibilityLabel = _(@"Start slideshow");
	self.slideshowButton.enabled = self.assets.count > 1;
	[self.slideshowButton addTarget:self action:@selector(toggleSlideshow) forControlEvents:UIControlEventTouchUpInside];
	[self.topBar.contentView addSubview:self.slideshowButton];

	self.bottomBar = [self blurBar];
	[self.view addSubview:self.bottomBar];

	self.shareButton = [self chromeButtonWithSymbol:@"square.and.arrow.up"];
	[self.shareButton addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.bottomBar.contentView addSubview:self.shareButton];

	self.favoriteButton = [self chromeButtonWithSymbol:@"heart"];
	self.favoriteButton.hidden = ![self currentAssetAllowsMutations];
	[self.favoriteButton addTarget:self action:@selector(favoriteTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.bottomBar.contentView addSubview:self.favoriteButton];

	self.editButton = [self chromeButtonWithSymbol:@"slider.horizontal.3"];
	self.editButton.hidden = ![self currentAssetAllowsMutations];
	self.editButton.accessibilityLabel = _(@"Edit photo");
	[self.editButton addTarget:self action:@selector(editCurrentAsset) forControlEvents:UIControlEventTouchUpInside];
	[self.bottomBar.contentView addSubview:self.editButton];

	self.addToAlbumButton = [self chromeButtonWithSymbol:@"folder.badge.plus"];
	self.addToAlbumButton.hidden = ![self currentAssetAllowsMutations];
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
		[self.slideshowButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
		[self.slideshowButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],

		[closeButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
		[closeButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],

		[self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.bottomBar.topAnchor constraintEqualToAnchor:infoButton.topAnchor constant:-10],

		[self.shareButton.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
		[self.shareButton.centerYAnchor constraintEqualToAnchor:infoButton.centerYAnchor],

		[self.favoriteButton.leadingAnchor constraintEqualToAnchor:self.shareButton.trailingAnchor constant:32],
		[self.favoriteButton.centerYAnchor constraintEqualToAnchor:infoButton.centerYAnchor],

		[self.editButton.leadingAnchor constraintEqualToAnchor:self.favoriteButton.trailingAnchor constant:24],
		[self.editButton.centerYAnchor constraintEqualToAnchor:infoButton.centerYAnchor],
		[self.editButton.trailingAnchor constraintLessThanOrEqualToAnchor:infoButton.leadingAnchor constant:-24],

		[infoButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[infoButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-6],

		[self.addToAlbumButton.trailingAnchor constraintEqualToAnchor:self.ocrButton.leadingAnchor constant:-32],
		[self.addToAlbumButton.centerYAnchor constraintEqualToAnchor:infoButton.centerYAnchor],

		[self.ocrButton.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
		[self.ocrButton.centerYAnchor constraintEqualToAnchor:infoButton.centerYAnchor],
	]];

	[self updateFavoriteButton];
	[self updateEditButton];
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
	[self stopSlideshow];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)toggleSlideshow {
	if (self.slideshowPlaying) {
		[self stopSlideshow];
		return;
	}
	if (self.assets.count < 2) return;
	self.slideshowPlaying = YES;
	self.slideshowButton.accessibilityLabel = _(@"Stop slideshow");
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
		[self.slideshowButton setImage:[UIImage systemImageNamed:@"pause.circle" withConfiguration:config] forState:UIControlStateNormal];
	}
	[self.slideshowTimer invalidate];
	self.slideshowTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
	                                                       target:self
	                                                     selector:@selector(advanceSlideshow)
	                                                     userInfo:nil
	                                                      repeats:YES];
}

- (void)stopSlideshow {
	self.slideshowPlaying = NO;
	self.slideshowTransitioning = NO;
	[self.slideshowTimer invalidate];
	self.slideshowTimer = nil;
	if (!self.slideshowButton) return;
	self.slideshowButton.accessibilityLabel = _(@"Start slideshow");
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
		[self.slideshowButton setImage:[UIImage systemImageNamed:@"play.circle" withConfiguration:config] forState:UIControlStateNormal];
	}
}

- (void)advanceSlideshow {
	if (!self.slideshowPlaying || self.slideshowTransitioning || self.assets.count < 2 || !self.pageViewController) return;
	NSInteger nextIndex = self.currentIndex + 1;
	if (nextIndex >= (NSInteger)self.assets.count) nextIndex = 0;
	AssetPageContentViewController *next = [self pageForIndex:nextIndex];
	self.slideshowTransitioning = YES;
	UIPageViewControllerNavigationDirection direction = nextIndex >= self.currentIndex
	    ? UIPageViewControllerNavigationDirectionForward
	    : UIPageViewControllerNavigationDirectionReverse;
	__weak typeof(self) weakSelf = self;
	[self.pageViewController setViewControllers:@[ next ]
                                    direction:direction
                                     animated:YES
	                                   completion:^(BOOL finished) {
		AssetViewController *strongSelf = weakSelf;
		if (strongSelf) strongSelf.slideshowTransitioning = NO;
		if (!strongSelf || !finished || !strongSelf.slideshowPlaying) return;
		AssetPageContentViewController *current = (AssetPageContentViewController *)strongSelf.pageViewController.viewControllers.firstObject;
		strongSelf.currentIndex = [strongSelf indexOfPage:current];
		[current playIfVideo];
		[strongSelf updateFavoriteButton];
		[strongSelf updateEditButton];
		strongSelf.ocrButton.hidden = !(current.asset.isImage && current.ocrHasText.boolValue);
	}];
}

- (void)infoTapped {
	IMAsset *asset = self.assets[self.currentIndex];
	AssetDetailViewController *detail = [AssetDetailViewController detailViewControllerForAssetId:asset.assetId];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:detail];
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)addToAlbumTapped {
	if (![self currentAssetAllowsMutations]) return;
	IMAsset *asset = self.assets[self.currentIndex];
	AddToAlbumViewController *picker = [AddToAlbumViewController pickerForAssetId:asset.assetId];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
	[self presentViewController:nav animated:YES completion:nil];
}

- (BOOL)isCurrentAssetFavorite {
	IMAsset *asset = self.assets[self.currentIndex];
	NSNumber *override = self.favoriteOverrides[asset.assetId];
	return override ? override.boolValue : asset.isFavorite;
}

- (void)updateFavoriteButton {
	BOOL allowsMutations = [self currentAssetAllowsMutations];
	self.favoriteButton.hidden = !allowsMutations;
	self.favoriteButton.enabled = allowsMutations;
	BOOL favorite = [self isCurrentAssetFavorite];
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
		[self.favoriteButton setImage:[UIImage systemImageNamed:(favorite ? @"heart.fill" : @"heart") withConfiguration:config]
		                     forState:UIControlStateNormal];
	}
	self.favoriteButton.tintColor = favorite ? UIColor.systemRedColor : UIColor.whiteColor;
}

- (void)updateEditButton {
	if (!self.editButton || self.assets.count == 0) {
		return;
	}
	IMAsset *asset = self.assets[self.currentIndex];
	BOOL available = [self currentAssetAllowsMutations] && asset.isImage && asset.livePhotoVideoId.length == 0 &&
	                 ![asset.projectionType isEqualToString:@"EQUIRECTANGULAR"];
	self.editButton.hidden = !available;
	self.editButton.enabled = available;
}

- (void)editCurrentAsset {
	if (![self currentAssetAllowsMutations]) {
		return;
	}
	IMAsset *asset = self.assets[self.currentIndex];
	if (!asset.isImage || asset.livePhotoVideoId.length > 0 || [asset.projectionType isEqualToString:@"EQUIRECTANGULAR"]) {
		return;
	}
	AssetEditViewController *editor = [[AssetEditViewController alloc] initWithAsset:asset];
	__weak typeof(self) weakSelf = self;
	editor.onSaved = ^(UIImage *_Nullable previewImage) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || strongSelf.assets.count == 0) {
			return;
		}
		AssetPageContentViewController *current =
		    (AssetPageContentViewController *)strongSelf.pageViewController.viewControllers.firstObject;
		if (previewImage) {
			[current setEditedImage:previewImage];
		} else {
			[current setEditedImage:nil];
		}
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	nav.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)favoriteTapped {
	if (![self currentAssetAllowsMutations]) return;
	IMAsset *asset = self.assets[self.currentIndex];
	NSString *assetId = asset.assetId;
	BOOL newValue = ![self isCurrentAssetFavorite];
	self.favoriteOverrides[assetId] = @(newValue); 
	[self updateFavoriteButton];
	__weak typeof(self) weakSelf = self;
	[IMAssetApi setFavorite:newValue
	            forAssetIds:@[ assetId ]
	             completion:^(BOOL success, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || success) {
			    return;
		    }
		    strongSelf.favoriteOverrides[assetId] = @(!newValue);
		    [strongSelf updateFavoriteButton];
	    }];
}

- (void)shareTapped {
	IMAsset *asset = self.assets[self.currentIndex];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Share")
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Share original file")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
		[weakSelf shareOriginalFileForAsset:asset];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Create Immich link")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
		[weakSelf createSharedLinkForAsset:asset];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.shareButton;
	sheet.popoverPresentationController.sourceRect = self.shareButton.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)shareOriginalFileForAsset:(IMAsset *)asset {
	NSString *assetId = asset.assetId;
	NSString *fallbackName = [NSString stringWithFormat:@"%@.%@", assetId, asset.isImage ? @"jpg" : @"mp4"];
	self.shareButton.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMAssetApi assetDetailForAssetId:assetId
	                        completion:^(IMAssetDetail *_Nullable detail, NSError *_Nullable error) {
			    NSString *filename = detail.originalFileName.length > 0 ? detail.originalFileName : fallbackName;
			    filename = filename.lastPathComponent;
			    filename = [filename stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
			    filename = [filename stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
			    filename = [filename stringByTrimmingCharactersInSet:NSCharacterSet.controlCharacterSet];
			    if (filename.length == 0 || [filename isEqualToString:@"."] || [filename isEqualToString:@".."]) {
				    filename = fallbackName;
			    }
			NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"IMShare"];
			NSURL *destinationURL = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:filename]];
			[IMAssetApi originalFileForAssetId:assetId
			                             edited:NO
			                    destinationURL:destinationURL
			                        completion:^(NSURL *_Nullable fileURL, NSError *_Nullable dataError) {
				    typeof(self) strongSelf = weakSelf;
				    if (!strongSelf) {
					    return;
				    }
				    if (!fileURL) {
					    strongSelf.shareButton.enabled = YES;
					    [strongSelf presentShareFailure];
					    return;
				    }
				    strongSelf.shareButton.enabled = YES;
				    UIActivityViewController *activity =
				        [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ]
				                                                  applicationActivities:nil];
				    activity.popoverPresentationController.sourceView = strongSelf.shareButton;
				    activity.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
					    (void)activityType;
					    (void)completed;
					    (void)returnedItems;
					    (void)activityError;
					    [[NSFileManager defaultManager] removeItemAtURL:fileURL error:NULL];
				    };
				    [strongSelf presentViewController:activity animated:YES completion:nil];
			    }];
	    }];
}

- (void)createSharedLinkForAsset:(IMAsset *)asset {
	__weak typeof(self) weakSelf = self;
	__weak SharedLinkEditorViewController *weakEditor = nil;
	SharedLinkEditorViewController *editor = [SharedLinkEditorViewController editorForNewLinkWithTitle:_(@"Individual photo")
	                                                                                         saveHandler:^(NSDictionary<NSString *,id> *fields) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.shareButton.enabled = NO;
		[IMSharedLinkApi createLinkForAssetIds:@[ asset.assetId ] options:fields completion:^(IMSharedLink *link, NSError *error) {
			typeof(self) inner = weakSelf;
			if (!inner) return;
			inner.shareButton.enabled = YES;
			if (!link || error) {
				[weakEditor setSaving:NO];
				[inner presentShareFailureWithMessage:error.localizedDescription ?: _(@"The server could not create a shared link.")];
				return;
			}
			NSURL *url = [IMSharedLinkApi publicURLForLink:link];
			if (!url) {
				[weakEditor setSaving:NO];
				[inner presentShareFailureWithMessage:_(@"The server returned an invalid shared link.")];
				return;
			}
			[inner dismissViewControllerAnimated:YES completion:^{
				UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Immich link ready")
				                                                                 message:url.absoluteString
				                                                          preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:_(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
					[UIPasteboard generalPasteboard].string = url.absoluteString;
				}]];
				[alert addAction:[UIAlertAction actionWithTitle:_(@"Share") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
					UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ url ]
					                                                                  applicationActivities:nil];
					activity.popoverPresentationController.sourceView = inner.shareButton;
					[inner presentViewController:activity animated:YES completion:nil];
				}]];
				[alert addAction:[UIAlertAction actionWithTitle:_(@"Done") style:UIAlertActionStyleCancel handler:nil]];
				[inner presentViewController:alert animated:YES completion:nil];
			}];
		}];
	}];
	weakEditor = editor;
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)presentShareFailure {
	[self presentShareFailureWithMessage:_(@"The original file could not be downloaded.")];
}

- (void)presentShareFailureWithMessage:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn't Share")
	                                                               message:message
	                                                        preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
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
			if (strongSelf.ocrOn && hasText) {
				[weakPage setOCRVisible:YES]; 
			}
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
	if (!completed) {
		return;
	}
	self.slideshowTransitioning = NO;
	for (AssetPageContentViewController *previous in previousViewControllers) {
		[previous pauseIfVideo];
	}
	AssetPageContentViewController *current = (AssetPageContentViewController *)self.pageViewController.viewControllers.firstObject;
	self.currentIndex = [self indexOfPage:current];
	[current playIfVideo];
	[self updateFavoriteButton];
	[self updateEditButton];

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
