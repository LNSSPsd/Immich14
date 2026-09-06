#import "AssetEditViewController.h"
#import "IMAssetApi.h"
#import "IMAssetDetail.h"
#import "IMAssetEdit.h"
#import "common.h"
#import <ImageIO/ImageIO.h>
#import <math.h>

#pragma mark - Image helpers

static CGSize IMEditorPixelSize(UIImage *image) {
	if (image.CGImage) {
		return CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
	}
	CGFloat scale = image.scale > 0 ? image.scale : 1.0;
	return CGSizeMake(MAX(1, lround(image.size.width * scale)), MAX(1, lround(image.size.height * scale)));
}

static UIImage *_Nullable IMEditorDecode(NSData *data) {
	CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
	if (!source) {
		return nil;
	}
	CGFloat maxPixels = MIN(4096.0, MAX(UIScreen.mainScreen.nativeBounds.size.width,
	                                     UIScreen.mainScreen.nativeBounds.size.height) * 2.0);
	NSDictionary *options = @{
		(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
		(__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
		(__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
		(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixels),
	};
	CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
	CFRelease(source);
	if (!cgImage) {
		return nil;
	}
	UIImage *image = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
	CGImageRelease(cgImage);
	return image;
}

static CGFloat IMEditorClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
	return MIN(MAX(value, minimum), maximum);
}

static CGRect IMEditorClampRect(CGRect rect, CGRect bounds) {
	CGFloat width = MIN(CGRectGetWidth(rect), CGRectGetWidth(bounds));
	CGFloat height = MIN(CGRectGetHeight(rect), CGRectGetHeight(bounds));
	CGFloat x = IMEditorClamp(CGRectGetMinX(rect), CGRectGetMinX(bounds), CGRectGetMaxX(bounds) - width);
	CGFloat y = IMEditorClamp(CGRectGetMinY(rect), CGRectGetMinY(bounds), CGRectGetMaxY(bounds) - height);
	return CGRectMake(x, y, width, height);
}

static UIImage *IMEditorRotate(UIImage *input, NSInteger angle) {
	angle = ((angle % 360) + 360) % 360;
	if (angle == 0) {
		return input;
	}
	CGSize sourceSize = IMEditorPixelSize(input);
	BOOL swaps = angle == 90 || angle == 270;
	CGSize outputSize = swaps ? CGSizeMake(sourceSize.height, sourceSize.width) : sourceSize;
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.opaque = YES;
	format.scale = 1.0;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:outputSize format:format];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		CGContextRef cg = context.CGContext;
		if (angle == 90) {
			CGContextTranslateCTM(cg, outputSize.width, 0);
			CGContextRotateCTM(cg, (CGFloat)M_PI_2);
		} else if (angle == 180) {
			CGContextTranslateCTM(cg, outputSize.width, outputSize.height);
			CGContextRotateCTM(cg, (CGFloat)M_PI);
		} else {
			CGContextTranslateCTM(cg, 0, outputSize.height);
			CGContextRotateCTM(cg, (CGFloat)-M_PI_2);
		}
		[input drawInRect:CGRectMake(0, 0, sourceSize.width, sourceSize.height)];
	}];
}

static UIImage *IMEditorMirror(UIImage *input, NSString *axis) {
	CGSize size = IMEditorPixelSize(input);
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
	format.opaque = YES;
	format.scale = 1.0;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		CGContextRef cg = context.CGContext;
		if ([axis isEqualToString:IMAssetEditMirrorAxisHorizontal]) {
			CGContextTranslateCTM(cg, size.width, 0);
			CGContextScaleCTM(cg, -1, 1);
		} else {
			CGContextTranslateCTM(cg, 0, size.height);
			CGContextScaleCTM(cg, 1, -1);
		}
		[input drawInRect:CGRectMake(0, 0, size.width, size.height)];
	}];
}

static UIImage *IMEditorCrop(UIImage *input, NSDictionary *parameters, CGSize sourceDimensions) {
	CGSize imageSize = IMEditorPixelSize(input);
	CGFloat sourceWidth = sourceDimensions.width > 0 ? sourceDimensions.width : imageSize.width;
	CGFloat sourceHeight = sourceDimensions.height > 0 ? sourceDimensions.height : imageSize.height;
	CGFloat scaleX = imageSize.width / sourceWidth;
	CGFloat scaleY = imageSize.height / sourceHeight;
	CGFloat x = [parameters[@"x"] doubleValue] * scaleX;
	CGFloat y = [parameters[@"y"] doubleValue] * scaleY;
	CGFloat width = [parameters[@"width"] doubleValue] * scaleX;
	CGFloat height = [parameters[@"height"] doubleValue] * scaleY;
	CGRect crop = CGRectMake(floor(x), floor(y), floor(width), floor(height));
	crop = IMEditorClampRect(crop, CGRectMake(0, 0, imageSize.width, imageSize.height));
	if (CGRectGetWidth(crop) < 1 || CGRectGetHeight(crop) < 1 || !input.CGImage) {
		return input;
	}
	CGImageRef cgImage = CGImageCreateWithImageInRect(input.CGImage, crop);
	if (!cgImage) {
		return input;
	}
	UIImage *result = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
	CGImageRelease(cgImage);
	return result;
}

static UIImage *IMEditorApplyEdits(UIImage *source, NSArray<IMAssetEdit *> *edits, CGSize sourceDimensions) {
	IMAssetEdit *crop = nil;
	NSMutableArray<IMAssetEdit *> *affine = [NSMutableArray array];
	for (IMAssetEdit *edit in edits) {
		if ([edit.action isEqualToString:IMAssetEditActionCrop] && !crop) {
			crop = edit;
		} else if (![edit.action isEqualToString:IMAssetEditActionCrop]) {
			[affine addObject:edit];
		}
	}
	UIImage *result = crop ? IMEditorCrop(source, crop.parameters, sourceDimensions) : source;
	for (IMAssetEdit *edit in affine) {
		if ([edit.action isEqualToString:IMAssetEditActionRotate]) {
			result = IMEditorRotate(result, [edit.parameters[@"angle"] integerValue]);
		} else if ([edit.action isEqualToString:IMAssetEditActionMirror]) {
			result = IMEditorMirror(result, edit.parameters[@"axis"]);
		}
	}
	return result;
}

#pragma mark - Crop overlay

@interface IMEditorCropOverlay : UIView
@property (nonatomic) CGRect selectionRect;
@end

@implementation IMEditorCropOverlay

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = UIColor.clearColor;
		self.opaque = NO;
		_selectionRect = CGRectZero;
		self.userInteractionEnabled = YES;
	}
	return self;
}

- (void)setSelectionRect:(CGRect)selectionRect {
		_selectionRect = selectionRect;
		[self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
	[super drawRect:rect];
	UIBezierPath *outside = [UIBezierPath bezierPathWithRect:self.bounds];
	UIBezierPath *inside = [UIBezierPath bezierPathWithRect:self.selectionRect];
	[outside appendPath:inside];
	outside.usesEvenOddFillRule = YES;
	[[UIColor colorWithWhite:0 alpha:0.48] setFill];
	[outside fill];
	[[UIColor whiteColor] setStroke];
	UIBezierPath *border = [UIBezierPath bezierPathWithRect:self.selectionRect];
	border.lineWidth = 2.0;
	[border stroke];
	[[UIColor colorWithWhite:1 alpha:0.55] setStroke];
	UIBezierPath *guides = [UIBezierPath bezierPath];
	CGFloat x1 = CGRectGetMinX(self.selectionRect) + CGRectGetWidth(self.selectionRect) / 3.0;
	CGFloat x2 = CGRectGetMinX(self.selectionRect) + CGRectGetWidth(self.selectionRect) * 2.0 / 3.0;
	CGFloat y1 = CGRectGetMinY(self.selectionRect) + CGRectGetHeight(self.selectionRect) / 3.0;
	CGFloat y2 = CGRectGetMinY(self.selectionRect) + CGRectGetHeight(self.selectionRect) * 2.0 / 3.0;
	[guides moveToPoint:CGPointMake(x1, CGRectGetMinY(self.selectionRect))];
	[guides addLineToPoint:CGPointMake(x1, CGRectGetMaxY(self.selectionRect))];
	[guides moveToPoint:CGPointMake(x2, CGRectGetMinY(self.selectionRect))];
	[guides addLineToPoint:CGPointMake(x2, CGRectGetMaxY(self.selectionRect))];
	[guides moveToPoint:CGPointMake(CGRectGetMinX(self.selectionRect), y1)];
	[guides addLineToPoint:CGPointMake(CGRectGetMaxX(self.selectionRect), y1)];
	[guides moveToPoint:CGPointMake(CGRectGetMinX(self.selectionRect), y2)];
	[guides addLineToPoint:CGPointMake(CGRectGetMaxX(self.selectionRect), y2)];
	guides.lineWidth = 0.5;
	[guides stroke];
}

@end

#pragma mark - Controller

@interface AssetEditViewController ()
@property (nonatomic, strong) IMAsset *asset;
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, strong) UIImage *previewImage;
@property (nonatomic, strong) NSMutableArray<IMAssetEdit *> *edits;
@property (nonatomic) CGSize sourceDimensions;
@property (nonatomic, strong) IMAssetDetail *assetDetail;
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) IMEditorCropOverlay *cropOverlay;
@property (nonatomic, strong) UIStackView *toolbar;
@property (nonatomic, strong) UIButton *cropButton;
@property (nonatomic, strong) UIButton *previewButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL cropMode;
@property (nonatomic) BOOL showingOriginal;
@property (nonatomic) BOOL sourceLoaded;
@property (nonatomic) BOOL editsLoaded;
@property (nonatomic) BOOL detailLoaded;
@property (nonatomic) BOOL saving;
@property (nonatomic) BOOL hasChanges;
@property (nonatomic) CGPoint cropPanStart;
@property (nonatomic) CGRect cropSelectionStart;
@property (nonatomic) CGFloat cropPinchStartScale;
@property (nonatomic) CGRect cropPinchStartRect;
@end

@implementation AssetEditViewController

- (instancetype)initWithAsset:(IMAsset *)asset {
	self = [super init];
	if (self) {
		_asset = asset;
		_edits = [NSMutableArray array];
		_sourceDimensions = CGSizeZero;
		self.modalPresentationStyle = UIModalPresentationFullScreen;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Edit Photo");
	self.view.backgroundColor = UIColor.blackColor;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                         target:self
	                                                                                         action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
	                                                                                          target:self
	                                                                                          action:@selector(saveTapped)];
	self.navigationItem.rightBarButtonItem.enabled = NO;

	self.canvasView = [[UIView alloc] init];
	self.canvasView.translatesAutoresizingMaskIntoConstraints = NO;
	self.canvasView.backgroundColor = UIColor.blackColor;
	[self.view addSubview:self.canvasView];

	self.imageView = [[UIImageView alloc] init];
	self.imageView.contentMode = UIViewContentModeScaleToFill;
	self.imageView.backgroundColor = UIColor.blackColor;
	[self.canvasView addSubview:self.imageView];

	self.cropOverlay = [[IMEditorCropOverlay alloc] initWithFrame:CGRectZero];
	self.cropOverlay.hidden = YES;
	[self.canvasView addSubview:self.cropOverlay];

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(cropPan:)] ;
	[self.cropOverlay addGestureRecognizer:pan];
	UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(cropPinch:)];
	[self.cropOverlay addGestureRecognizer:pinch];

	self.toolbar = [[UIStackView alloc] init];
	self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
	self.toolbar.axis = UILayoutConstraintAxisHorizontal;
	self.toolbar.alignment = UIStackViewAlignmentCenter;
	self.toolbar.distribution = UIStackViewDistributionFillEqually;
	self.toolbar.spacing = 4;
	self.toolbar.layoutMargins = UIEdgeInsetsMake(8, 8, 14, 8);
	self.toolbar.layoutMarginsRelativeArrangement = YES;
	self.toolbar.backgroundColor = UIColor.systemGrayColor;
	[self.view addSubview:self.toolbar];

	self.cropButton = [self editorButtonWithTitle:_(@"Crop") symbol:@"crop" action:@selector(cropTapped)];
	UIButton *rotateButton = [self editorButtonWithTitle:_(@"Rotate") symbol:@"rotate.right" action:@selector(rotateTapped)];
	UIButton *flipHButton = [self editorButtonWithTitle:_(@"Flip H") symbol:@"arrow.left.and.right.righttriangle.left.righttriangle.right" action:@selector(flipHorizontalTapped)];
	UIButton *flipVButton = [self editorButtonWithTitle:_(@"Flip V") symbol:@"arrow.up.and.down.righttriangle.up.righttriangle.down" action:@selector(flipVerticalTapped)];
	self.previewButton = [self editorButtonWithTitle:_(@"Preview") symbol:@"eye" action:@selector(previewTapped)];
	UIButton *resetButton = [self editorButtonWithTitle:_(@"Reset") symbol:@"arrow.counterclockwise" action:@selector(resetTapped)];
	for (UIButton *button in @[ self.cropButton, rotateButton, flipHButton, flipVButton, self.previewButton, resetButton ]) {
		[self.toolbar addArrangedSubview:button];
	}

	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.statusLabel.textColor = UIColor.whiteColor;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.hidden = YES;
	[self.canvasView addSubview:self.statusLabel];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[self.canvasView addSubview:self.spinner];

	[NSLayoutConstraint activateConstraints:@[
		[self.canvasView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.canvasView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.canvasView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.canvasView.bottomAnchor constraintEqualToAnchor:self.toolbar.topAnchor],
		[self.toolbar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.toolbar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.toolbar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.statusLabel.centerXAnchor constraintEqualToAnchor:self.canvasView.centerXAnchor],
		[self.statusLabel.centerYAnchor constraintEqualToAnchor:self.canvasView.centerYAnchor],
		[self.statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.canvasView.leadingAnchor constant:24],
		[self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.canvasView.trailingAnchor constant:-24],
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.canvasView.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.canvasView.centerYAnchor],
	]];

	if (!self.asset.isImage || self.asset.livePhotoVideoId.length > 0 ||
	    [self.asset.projectionType isEqualToString:@"EQUIRECTANGULAR"]) {
		[self showError:_(@"Only regular still photos can be edited.")];
		return;
	}
	[self.spinner startAnimating];
	[self loadSourceImage];
	[self loadExistingEdits];
	[self loadAssetDetails];
}

- (UIButton *)editorButtonWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.tintColor = UIColor.whiteColor;
	button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
	button.titleLabel.adjustsFontSizeToFitWidth = YES;
	button.titleLabel.minimumScaleFactor = 0.7;
	[button setTitle:title forState:UIControlStateNormal];
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	button.accessibilityLabel = title;
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
		UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:configuration];
		if (image) {
			[button setImage:image forState:UIControlStateNormal];
			button.imageView.contentMode = UIViewContentModeScaleAspectFit;
			button.imageEdgeInsets = UIEdgeInsetsMake(0, -3, 0, 3);
		}
	}
	[button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
	return button;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutImage];
}

- (void)layoutImage {
	if (!self.previewImage || self.canvasView.bounds.size.width <= 0 || self.canvasView.bounds.size.height <= 0) {
		return;
	}
	CGSize size = IMEditorPixelSize(self.previewImage);
	CGFloat scale = MIN(self.canvasView.bounds.size.width / size.width, self.canvasView.bounds.size.height / size.height);
	CGFloat width = size.width * scale;
	CGFloat height = size.height * scale;
	CGRect frame = CGRectMake((self.canvasView.bounds.size.width - width) / 2.0,
	                          (self.canvasView.bounds.size.height - height) / 2.0,
	                          width,
	                          height);
	self.imageView.frame = frame;
	self.cropOverlay.frame = self.canvasView.bounds;
	if (self.cropMode && CGRectIsEmpty(self.cropOverlay.selectionRect)) {
		[self resetCropSelectionForImageFrame:frame];
	} else if (self.cropMode) {
		self.cropOverlay.selectionRect = IMEditorClampRect(self.cropOverlay.selectionRect, frame);
	}
}

#pragma mark Loading

- (void)loadSourceImage {
	__weak typeof(self) weakSelf = self;
	[IMAssetApi originalDataForAssetId:self.asset.assetId
	                           edited:NO
	                      completion:^(NSData *_Nullable data, NSError *_Nullable error) {
		if (!data) {
			[weakSelf showError:error.localizedDescription ?: _(@"The original photo could not be loaded.")];
			return;
		}
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			UIImage *image = IMEditorDecode(data);
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				if (!image) {
					[strongSelf showError:_(@"The original photo format is not supported on this device.")];
					return;
				}
				strongSelf.sourceImage = image;
				strongSelf.sourceLoaded = YES;
				if (strongSelf.sourceDimensions.width <= 0 || strongSelf.sourceDimensions.height <= 0) {
					strongSelf.sourceDimensions = IMEditorPixelSize(image);
				}
				[strongSelf finishLoadingIfReady];
			});
		});
	}];
}

- (void)loadExistingEdits {
	__weak typeof(self) weakSelf = self;
	[IMAssetApi assetEditsForAssetId:self.asset.assetId
	                      completion:^(NSArray<IMAssetEdit *> *_Nullable edits, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		if (edits) {
			[strongSelf.edits addObjectsFromArray:edits];
		} else if (error && !strongSelf.sourceLoaded) {
			[strongSelf showError:error.localizedDescription ?: _(@"Existing edits could not be loaded.")];
		}
		strongSelf.editsLoaded = YES;
		[strongSelf finishLoadingIfReady];
	}];
}

- (void)loadAssetDetails {
	__weak typeof(self) weakSelf = self;
	[IMAssetApi assetDetailForAssetId:self.asset.assetId
	                        completion:^(IMAssetDetail *_Nullable detail, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.assetDetail = detail;
		if (detail.width > 0 && detail.height > 0) {
			strongSelf.sourceDimensions = CGSizeMake(detail.width, detail.height);
		}
		strongSelf.detailLoaded = YES;
		[strongSelf finishLoadingIfReady];
	}];
}

- (void)finishLoadingIfReady {
	if (!self.sourceLoaded || !self.editsLoaded) {
		return;
	}
	[self.spinner stopAnimating];
	self.statusLabel.hidden = YES;
	self.previewImage = IMEditorApplyEdits(self.sourceImage, self.edits, self.sourceDimensions);
	[self layoutImage];
	self.navigationItem.rightBarButtonItem.enabled = self.edits.count > 0;
	self.hasChanges = NO;
}

- (void)showError:(NSString *)message {
	[self.spinner stopAnimating];
	self.statusLabel.hidden = NO;
	self.statusLabel.text = message;
	self.toolbar.userInteractionEnabled = NO;
	self.navigationItem.rightBarButtonItem.enabled = NO;
}

#pragma mark Crop

- (void)resetCropSelectionForImageFrame:(CGRect)frame {
	CGFloat insetX = MIN(24.0, CGRectGetWidth(frame) * 0.1);
	CGFloat insetY = MIN(24.0, CGRectGetHeight(frame) * 0.1);
	CGRect selection = CGRectInset(frame, insetX, insetY);
	if (CGRectGetWidth(selection) < 40 || CGRectGetHeight(selection) < 40) {
		selection = frame;
	}
	self.cropOverlay.selectionRect = selection;
}

- (void)setCropMode:(BOOL)cropMode {
	_cropMode = cropMode;
	self.cropOverlay.hidden = !cropMode;
	if (cropMode) {
		[self resetCropSelectionForImageFrame:self.imageView.frame];
		[self.cropButton setTitle:_(@"Apply") forState:UIControlStateNormal];
		self.cropButton.accessibilityLabel = _(@"Apply crop");
	} else {
		[self.cropButton setTitle:_(@"Crop") forState:UIControlStateNormal];
		self.cropButton.accessibilityLabel = _(@"Crop");
	}
}

- (void)cropTapped {
	if (self.saving || !self.sourceImage) return;
	if (self.showingOriginal) {
		self.showingOriginal = NO;
		self.imageView.image = self.previewImage;
		[self layoutImage];
	}
	if (self.cropMode) {
		[self applyCropSelection];
		self.cropMode = NO;
	} else {
		self.cropMode = YES;
	}
}

- (void)cropPan:(UIPanGestureRecognizer *)gesture {
	if (!self.cropMode || self.saving) return;
	if (gesture.state == UIGestureRecognizerStateBegan) {
		self.cropPanStart = [gesture locationInView:self.canvasView];
		self.cropSelectionStart = self.cropOverlay.selectionRect;
		return;
	}
	if (gesture.state == UIGestureRecognizerStateChanged) {
		CGPoint now = [gesture locationInView:self.canvasView];
		CGFloat dx = now.x - self.cropPanStart.x;
		CGFloat dy = now.y - self.cropPanStart.y;
		CGRect frame = CGRectOffset(self.cropSelectionStart, dx, dy);
		self.cropOverlay.selectionRect = IMEditorClampRect(frame, self.imageView.frame);
	}
}

- (void)cropPinch:(UIPinchGestureRecognizer *)gesture {
	if (!self.cropMode || self.saving) return;
	if (gesture.state == UIGestureRecognizerStateBegan) {
		self.cropPinchStartScale = gesture.scale;
		self.cropPinchStartRect = self.cropOverlay.selectionRect;
		return;
	}
	if (gesture.state == UIGestureRecognizerStateChanged) {
		CGFloat scale = gesture.scale / MAX(self.cropPinchStartScale, 0.001);
		CGRect start = self.cropPinchStartRect;
		CGPoint center = CGPointMake(CGRectGetMidX(start), CGRectGetMidY(start));
		CGFloat width = MAX(40.0, CGRectGetWidth(start) * scale);
		CGFloat height = MAX(40.0, CGRectGetHeight(start) * scale);
		CGRect frame = CGRectMake(center.x - width / 2.0, center.y - height / 2.0, width, height);
		self.cropOverlay.selectionRect = IMEditorClampRect(frame, self.imageView.frame);
	}
}

- (CGRect)sourceCropRectForSelection {
	CGRect imageFrame = self.imageView.frame;
	CGRect selected = CGRectIntersection(self.cropOverlay.selectionRect, imageFrame);
	if (CGRectIsNull(selected) || CGRectGetWidth(imageFrame) <= 0 || CGRectGetHeight(imageFrame) <= 0) {
		return CGRectMake(0, 0, self.sourceDimensions.width, self.sourceDimensions.height);
	}
	CGSize outputSize = IMEditorPixelSize(self.previewImage);
	CGFloat sx = outputSize.width / CGRectGetWidth(imageFrame);
	CGFloat sy = outputSize.height / CGRectGetHeight(imageFrame);
	CGRect outputRect = CGRectMake((CGRectGetMinX(selected) - CGRectGetMinX(imageFrame)) * sx,
	                               (CGRectGetMinY(selected) - CGRectGetMinY(imageFrame)) * sy,
	                               CGRectGetWidth(selected) * sx,
	                               CGRectGetHeight(selected) * sy);

	IMAssetEdit *existingCrop = nil;
	for (IMAssetEdit *edit in self.edits) {
		if ([edit.action isEqualToString:IMAssetEditActionCrop]) {
			existingCrop = edit;
			break;
		}
	}
	CGSize preAffine = existingCrop ? CGSizeMake([existingCrop.parameters[@"width"] doubleValue],
	                                               [existingCrop.parameters[@"height"] doubleValue])
	                                 : self.sourceDimensions;
	if (preAffine.width <= 0 || preAffine.height <= 0) {
		preAffine = self.sourceDimensions;
	}

	NSArray<NSValue *> *corners = @[
		[NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX(outputRect), CGRectGetMinY(outputRect))],
		[NSValue valueWithCGPoint:CGPointMake(CGRectGetMaxX(outputRect), CGRectGetMinY(outputRect))],
		[NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX(outputRect), CGRectGetMaxY(outputRect))],
		[NSValue valueWithCGPoint:CGPointMake(CGRectGetMaxX(outputRect), CGRectGetMaxY(outputRect))],
	];
	NSMutableArray<NSValue *> *transformed = [NSMutableArray arrayWithCapacity:corners.count];
	for (NSValue *value in corners) {
		CGPoint point = value.CGPointValue;
		CGSize dimensions = preAffine;
		for (IMAssetEdit *edit in self.edits) {
			if (![edit.action isEqualToString:IMAssetEditActionRotate]) continue;
			NSInteger angle = [edit.parameters[@"angle"] integerValue];
			if (angle == 90 || angle == 270) {
				dimensions = CGSizeMake(dimensions.height, dimensions.width);
			}
		}
		for (IMAssetEdit *edit in [self.edits reverseObjectEnumerator]) {
			if ([edit.action isEqualToString:IMAssetEditActionRotate]) {
				NSInteger angle = (([edit.parameters[@"angle"] integerValue] % 360) + 360) % 360;
				CGSize before = (angle == 90 || angle == 270) ? CGSizeMake(dimensions.height, dimensions.width) : dimensions;
				if (angle == 90) {
					point = CGPointMake(point.y, before.width - point.x);
				} else if (angle == 180) {
					point = CGPointMake(before.width - point.x, before.height - point.y);
				} else if (angle == 270) {
					point = CGPointMake(before.height - point.y, point.x);
				}
				dimensions = before;
			} else if ([edit.action isEqualToString:IMAssetEditActionMirror]) {
				NSString *axis = edit.parameters[@"axis"];
				if ([axis isEqualToString:IMAssetEditMirrorAxisHorizontal]) {
					point.x = dimensions.width - point.x;
				} else if ([axis isEqualToString:IMAssetEditMirrorAxisVertical]) {
					point.y = dimensions.height - point.y;
				}
			}
		}
		[transformed addObject:[NSValue valueWithCGPoint:point]];
	}
	CGFloat minX = CGFLOAT_MAX, minY = CGFLOAT_MAX, maxX = 0, maxY = 0;
	for (NSValue *value in transformed) {
		CGPoint point = value.CGPointValue;
		minX = MIN(minX, point.x);
		minY = MIN(minY, point.y);
		maxX = MAX(maxX, point.x);
		maxY = MAX(maxY, point.y);
	}
	CGRect result = CGRectMake(minX, minY, maxX - minX, maxY - minY);
	if (existingCrop) {
		result.origin.x += [existingCrop.parameters[@"x"] doubleValue];
		result.origin.y += [existingCrop.parameters[@"y"] doubleValue];
	}
	CGRect sourceBounds = CGRectMake(0, 0, self.sourceDimensions.width, self.sourceDimensions.height);
	result = IMEditorClampRect(result, sourceBounds);
	result.origin.x = floor(result.origin.x);
	result.origin.y = floor(result.origin.y);
	result.size.width = MAX(1, floor(result.size.width));
	result.size.height = MAX(1, floor(result.size.height));
	if (CGRectGetMaxX(result) > CGRectGetMaxX(sourceBounds)) {
		result.size.width = MAX(1, CGRectGetMaxX(sourceBounds) - CGRectGetMinX(result));
	}
	if (CGRectGetMaxY(result) > CGRectGetMaxY(sourceBounds)) {
		result.size.height = MAX(1, CGRectGetMaxY(sourceBounds) - CGRectGetMinY(result));
	}
	return result;
}

- (void)applyCropSelection {
	if (!self.sourceImage) return;
	CGRect crop = [self sourceCropRectForSelection];
	CGRect full = CGRectMake(0, 0, self.sourceDimensions.width, self.sourceDimensions.height);
	IMAssetEdit *cropEdit = [IMAssetEdit editWithAction:IMAssetEditActionCrop
	                                          parameters:@{
		                                          @"x": @((NSInteger)crop.origin.x),
		                                          @"y": @((NSInteger)crop.origin.y),
		                                          @"width": @((NSInteger)crop.size.width),
		                                          @"height": @((NSInteger)crop.size.height),
	                                          }];
	if (!cropEdit) return;
	for (NSInteger index = self.edits.count - 1; index >= 0; index--) {
		if ([self.edits[index].action isEqualToString:IMAssetEditActionCrop]) {
			[self.edits removeObjectAtIndex:index];
		}
	}
	BOOL isFull = fabs(crop.origin.x - full.origin.x) < 0.5 && fabs(crop.origin.y - full.origin.y) < 0.5 &&
	             fabs(crop.size.width - full.size.width) < 0.5 && fabs(crop.size.height - full.size.height) < 0.5;
	if (!isFull) {
		[self.edits insertObject:cropEdit atIndex:0];
	}
	[self editsChanged];
}

#pragma mark Actions

- (void)rotateTapped {
	if (self.saving || !self.sourceImage) return;
	NSInteger angle = 0;
	NSInteger rotateIndex = NSNotFound;
	for (NSInteger index = 0; index < (NSInteger)self.edits.count; index++) {
		IMAssetEdit *edit = self.edits[index];
		if ([edit.action isEqualToString:IMAssetEditActionRotate]) {
			angle = [edit.parameters[@"angle"] integerValue];
			rotateIndex = index;
			break;
		}
	}
	angle = (angle + 90) % 360;
	if (rotateIndex != NSNotFound) {
		[self.edits removeObjectAtIndex:rotateIndex];
	}
	if (angle != 0) {
		IMAssetEdit *edit = [IMAssetEdit editWithAction:IMAssetEditActionRotate parameters:@{ @"angle": @(angle) }];
		NSUInteger insertion = self.edits.count;
		[self.edits addObject:edit];
		(void)insertion;
	}
	[self editsChanged];
}

- (void)toggleMirrorAxis:(NSString *)axis {
	if (self.saving || !self.sourceImage) return;
	NSInteger existingIndex = NSNotFound;
	for (NSInteger index = 0; index < (NSInteger)self.edits.count; index++) {
		IMAssetEdit *edit = self.edits[index];
		if ([edit.action isEqualToString:IMAssetEditActionMirror] && [edit.parameters[@"axis"] isEqualToString:axis]) {
			existingIndex = index;
			break;
		}
	}
	if (existingIndex != NSNotFound) {
		[self.edits removeObjectAtIndex:existingIndex];
	} else {
		IMAssetEdit *edit = [IMAssetEdit editWithAction:IMAssetEditActionMirror parameters:@{ @"axis": axis }];
		if (edit) [self.edits addObject:edit];
	}
	[self editsChanged];
}

- (void)flipHorizontalTapped {
	[self toggleMirrorAxis:IMAssetEditMirrorAxisHorizontal];
}

- (void)flipVerticalTapped {
	[self toggleMirrorAxis:IMAssetEditMirrorAxisVertical];
}

- (void)resetTapped {
	if (self.saving || !self.sourceImage) return;
	[self.edits removeAllObjects];
	self.cropMode = NO;
	self.showingOriginal = NO;
	[self editsChanged];
}

- (void)previewTapped {
	if (self.saving || !self.sourceImage) return;
	self.showingOriginal = !self.showingOriginal;
	self.imageView.image = self.showingOriginal ? self.sourceImage : self.previewImage;
	NSString *title = self.showingOriginal ? _(@"Edits") : _(@"Preview");
	[self.previewButton setTitle:title forState:UIControlStateNormal];
	self.previewButton.accessibilityLabel = self.showingOriginal ? _(@"Show edits") : _(@"Preview original");
	[self layoutImage];
}

- (void)editsChanged {
	self.hasChanges = YES;
	self.previewImage = IMEditorApplyEdits(self.sourceImage, self.edits, self.sourceDimensions);
	self.showingOriginal = NO;
	self.imageView.image = self.previewImage;
	self.navigationItem.rightBarButtonItem.enabled = YES;
	[self layoutImage];
}

#pragma mark Save / dismissal

- (void)cancelTapped {
	if (self.saving) return;
	if (!self.hasChanges) {
		[self dismissViewControllerAnimated:YES completion:nil];
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Discard edits?")
	                                                                 message:_(@"Your changes have not been saved.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Keep Editing") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Discard") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf dismissViewControllerAnimated:YES completion:nil];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)saveTapped {
	if (self.saving || !self.hasChanges) {
		if (!self.hasChanges) [self dismissViewControllerAnimated:YES completion:nil];
		return;
	}
	self.saving = YES;
	self.toolbar.userInteractionEnabled = NO;
	self.navigationItem.leftBarButtonItem.enabled = NO;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	if (self.edits.count == 0) {
		[IMAssetApi removeAssetEditsForAssetId:self.asset.assetId
	                              completion:^(BOOL success, NSError *_Nullable error) {
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!success) {
				[strongSelf saveFailed:error];
				return;
			}
			[strongSelf saveSucceeded:nil];
		}];
		return;
	}
	[IMAssetApi applyAssetEdits:self.edits
	                 forAssetId:self.asset.assetId
	                 completion:^(NSArray<IMAssetEdit *> *_Nullable edits, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		if (!edits && error) {
			[strongSelf saveFailed:error];
			return;
		}
		if (edits) {
			[strongSelf.edits removeAllObjects];
			[strongSelf.edits addObjectsFromArray:edits];
		}
		[strongSelf saveSucceeded:strongSelf.previewImage];
	}];
}

- (void)saveFailed:(NSError *)error {
	self.saving = NO;
	self.toolbar.userInteractionEnabled = YES;
	self.navigationItem.leftBarButtonItem.enabled = YES;
	self.navigationItem.rightBarButtonItem.enabled = YES;
	[self.spinner stopAnimating];
	[self showErrorAlert:error.localizedDescription ?: _(@"The server could not save these edits.")];
}

- (void)saveSucceeded:(UIImage *)preview {
	self.saving = NO;
	[self.spinner stopAnimating];
	if (self.onSaved) {
		self.onSaved(preview);
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showErrorAlert:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn't save edits")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
