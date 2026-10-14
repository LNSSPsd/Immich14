#import "IMMemoryPlayerViewController.h"
#import "AssetGridViewController.h"
#import "IMAssetApi.h"
#import "IMMemoryApi.h"
#import "IMPrefs.h"
#import "IMThumbCache.h"
#import "MemoryEditorViewController.h"
#import "common.h"
#import <QuartzCore/QuartzCore.h>

static const CFTimeInterval kMemoryPhotoDuration = 5.0;
static const CGFloat kKenBurnsScale = 1.08;

#pragma mark - Progress bars

@interface IMMemoryProgressView : UIView
@property (nonatomic) NSInteger count;
@property (nonatomic) NSInteger index;
@property (nonatomic) CGFloat progress;
@end

@implementation IMMemoryProgressView {
	NSMutableArray<CALayer *> *_tracks;
	NSMutableArray<CALayer *> *_fills;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_tracks = [NSMutableArray array];
		_fills = [NSMutableArray array];
		self.userInteractionEnabled = NO;
	}
	return self;
}

- (void)setCount:(NSInteger)count {
	_count = MAX(0, count);
	for (CALayer *layer in _tracks) [layer removeFromSuperlayer];
	for (CALayer *layer in _fills) [layer removeFromSuperlayer];
	[_tracks removeAllObjects];
	[_fills removeAllObjects];
	for (NSInteger i = 0; i < _count; i++) {
		CALayer *track = [CALayer layer];
		track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
		CALayer *fill = [CALayer layer];
		fill.backgroundColor = UIColor.whiteColor.CGColor;
		[self.layer addSublayer:track];
		[track addSublayer:fill];
		[_tracks addObject:track];
		[_fills addObject:fill];
	}
	[self setNeedsLayout];
}

- (void)setIndex:(NSInteger)index {
	_index = index;
	[self setNeedsLayout];
}

- (void)setProgress:(CGFloat)progress {
	_progress = MAX(0, MIN(1, progress));
	[self layoutFills];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_count == 0) {
		return;
	}
	CGFloat spacing = _count > 40 ? 1 : 3;
	CGFloat width = (self.bounds.size.width - spacing * (_count - 1)) / _count;
	CGFloat height = self.bounds.size.height;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for (NSInteger i = 0; i < _count; i++) {
		_tracks[i].frame = CGRectMake(i * (width + spacing), 0, width, height);
		_tracks[i].cornerRadius = height / 2;
		_fills[i].cornerRadius = height / 2;
	}
	[CATransaction commit];
	[self layoutFills];
}

- (void)layoutFills {
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for (NSInteger i = 0; i < _count; i++) {
		CGRect track = _tracks[i].bounds;
		CGFloat fraction = i < _index ? 1 : (i == _index ? _progress : 0);
		_fills[i].frame = CGRectMake(0, 0, track.size.width * fraction, track.size.height);
	}
	[CATransaction commit];
}

@end

#pragma mark - Open/close transition

@interface IMMemoryPlayerTransition : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic) BOOL presenting;
@end

@interface IMMemoryPlayerViewController () <UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMutableArray<IMMemory *> *memories;
@property (nonatomic) NSInteger memoryIndex;
@property (nonatomic) NSInteger assetIndex;
@property (nonatomic) CFTimeInterval elapsed;
@property (nonatomic) CFTimeInterval lastTick;
@property (nonatomic) BOOL holding;       
@property (nonatomic) BOOL wasPaused;
@property (nonatomic) BOOL dragging;      
@property (nonatomic) BOOL photoReady;    
@property (nonatomic) NSUInteger photoGeneration;
@property (nonatomic, strong, nullable) CADisplayLink *link;
@property (nonatomic, strong, nullable) IMThumbCacheTask *photoTask;
@property (nonatomic, strong, nullable) IMThumbCacheTask *fallbackTask;

@property (nonatomic, strong) UIView *content;       
@property (nonatomic, strong) UIImageView *backdropView;
@property (nonatomic, strong) UIView *stage;          
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UIView *chrome;
@property (nonatomic, strong) IMMemoryProgressView *progressView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *moreButton;
@property (nonatomic) BOOL kenBurnsFlip;
@end

@implementation IMMemoryPlayerViewController

+ (instancetype)playerWithMemories:(NSArray<IMMemory *> *)memories startIndex:(NSInteger)startIndex {
	IMMemoryPlayerViewController *player = [[self alloc] init];
	player.memories = [memories mutableCopy];
	player.memoryIndex = MAX(0, MIN(startIndex, (NSInteger)memories.count - 1));
	player.modalPresentationStyle = UIModalPresentationOverFullScreen;
	player.modalPresentationCapturesStatusBarAppearance = YES;
	player.transitioningDelegate = player;
	return player;
}

- (void)dealloc {
	[_link invalidate];
	[_photoTask cancel];
	[_fallbackTask cancel];
}

- (BOOL)prefersStatusBarHidden {
	return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
	return YES;
}

- (IMMemory *)currentMemory {
	return self.memories[self.memoryIndex];
}

#pragma mark Views

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.blackColor;

	self.content = [[UIView alloc] initWithFrame:self.view.bounds];
	self.content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.content.backgroundColor = UIColor.blackColor;
	self.content.clipsToBounds = YES;
	[self.view addSubview:self.content];

	self.backdropView = [[UIImageView alloc] initWithFrame:self.content.bounds];
	self.backdropView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.backdropView.contentMode = UIViewContentModeScaleAspectFill;
	self.backdropView.clipsToBounds = YES;
	[self.content addSubview:self.backdropView];
	UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
	blur.frame = self.content.bounds;
	blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.content addSubview:blur];

	self.stage = [[UIView alloc] initWithFrame:self.content.bounds];
	self.stage.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.content addSubview:self.stage];
	self.photoView = [[UIImageView alloc] initWithFrame:self.stage.bounds];
	self.photoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.photoView.contentMode = UIViewContentModeScaleAspectFit;
	[self.stage addSubview:self.photoView];

	[self setUpChrome];
	[self setUpGestures];
	[self showMemoryAtIndex:self.memoryIndex assetIndex:0 animated:NO];
}

- (CAGradientLayer *)scrimFromTop:(BOOL)fromTop {
	CAGradientLayer *scrim = [CAGradientLayer layer];
	scrim.colors = @[ (id)[UIColor colorWithWhite:0 alpha:0.5].CGColor, (id)[UIColor colorWithWhite:0 alpha:0].CGColor ];
	scrim.startPoint = CGPointMake(0.5, fromTop ? 0 : 1);
	scrim.endPoint = CGPointMake(0.5, fromTop ? 1 : 0);
	return scrim;
}

- (UIButton *)chromeButtonWithSymbol:(NSString *)symbol {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.translatesAutoresizingMaskIntoConstraints = NO;
	button.tintColor = UIColor.whiteColor;
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
		[button setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
	}
	button.layer.shadowColor = UIColor.blackColor.CGColor;
	button.layer.shadowOpacity = 0.35;
	button.layer.shadowRadius = 3;
	button.layer.shadowOffset = CGSizeZero;
	[button.widthAnchor constraintEqualToConstant:44].active = YES;
	[button.heightAnchor constraintEqualToConstant:44].active = YES;
	return button;
}

- (void)setUpChrome {
	self.chrome = [[UIView alloc] initWithFrame:self.content.bounds];
	self.chrome.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.content addSubview:self.chrome];

	UIView *topScrim = [[UIView alloc] init];
	topScrim.translatesAutoresizingMaskIntoConstraints = NO;
	topScrim.userInteractionEnabled = NO;
	[topScrim.layer addSublayer:[self scrimFromTop:YES]];
	[self.chrome addSubview:topScrim];
	UIView *bottomScrim = [[UIView alloc] init];
	bottomScrim.translatesAutoresizingMaskIntoConstraints = NO;
	bottomScrim.userInteractionEnabled = NO;
	[bottomScrim.layer addSublayer:[self scrimFromTop:NO]];
	[self.chrome addSubview:bottomScrim];

	self.progressView = [[IMMemoryProgressView alloc] init];
	self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.chrome addSubview:self.progressView];

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
	self.titleLabel.textColor = UIColor.whiteColor;
	[self.chrome addSubview:self.titleLabel];

	self.subtitleLabel = [[UILabel alloc] init];
	self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
	self.subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
	[self.chrome addSubview:self.subtitleLabel];

	UIButton *close = [self chromeButtonWithSymbol:@"xmark"];
	close.accessibilityLabel = _(@"Close");
	[close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.chrome addSubview:close];

	self.captionLabel = [[UILabel alloc] init];
	self.captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.captionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
	self.captionLabel.textColor = [UIColor colorWithWhite:1 alpha:0.9];
	[self.chrome addSubview:self.captionLabel];

	self.saveButton = [self chromeButtonWithSymbol:@"bookmark"];
	[self.saveButton addTarget:self action:@selector(toggleSaved) forControlEvents:UIControlEventTouchUpInside];
	[self.chrome addSubview:self.saveButton];

	self.moreButton = [self chromeButtonWithSymbol:@"ellipsis.circle"];
	self.moreButton.accessibilityLabel = _(@"More");
	[self.chrome addSubview:self.moreButton];
	if (@available(iOS 14.0, *)) {
		self.moreButton.showsMenuAsPrimaryAction = YES;
		[self updateMoreMenu];
	} else {
		[self.moreButton addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
	}

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[topScrim.topAnchor constraintEqualToAnchor:self.chrome.topAnchor],
		[topScrim.leadingAnchor constraintEqualToAnchor:self.chrome.leadingAnchor],
		[topScrim.trailingAnchor constraintEqualToAnchor:self.chrome.trailingAnchor],
		[topScrim.bottomAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:40],
		[bottomScrim.bottomAnchor constraintEqualToAnchor:self.chrome.bottomAnchor],
		[bottomScrim.leadingAnchor constraintEqualToAnchor:self.chrome.leadingAnchor],
		[bottomScrim.trailingAnchor constraintEqualToAnchor:self.chrome.trailingAnchor],
		[bottomScrim.topAnchor constraintEqualToAnchor:self.saveButton.topAnchor constant:-40],

		[self.progressView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
		[self.progressView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
		[self.progressView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
		[self.progressView.heightAnchor constraintEqualToConstant:2.5],

		[self.titleLabel.topAnchor constraintEqualToAnchor:self.progressView.bottomAnchor constant:14],
		[self.titleLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
		[self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-8],
		[self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
		[self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
		[self.subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:close.leadingAnchor constant:-8],
		[close.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-6],
		[close.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],

		[self.moreButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-6],
		[self.moreButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-6],
		[self.saveButton.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-4],
		[self.saveButton.centerYAnchor constraintEqualToAnchor:self.moreButton.centerYAnchor],
		[self.captionLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
		[self.captionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.saveButton.leadingAnchor constant:-8],
		[self.captionLabel.centerYAnchor constraintEqualToAnchor:self.moreButton.centerYAnchor],
	]];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for (UIView *view in self.chrome.subviews) {
		for (CALayer *layer in view.layer.sublayers) {
			if ([layer isKindOfClass:[CAGradientLayer class]]) layer.frame = view.bounds;
		}
	}
	[CATransaction commit];
}

#pragma mark Gestures

- (void)setUpGestures {
	UIPanGestureRecognizer *dismissPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDismissPan:)];
	dismissPan.delegate = self;
	[self.content addGestureRecognizer:dismissPan];

	UISwipeGestureRecognizer *nextMemory = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedToNextMemory)];
	nextMemory.direction = UISwipeGestureRecognizerDirectionLeft;
	[nextMemory requireGestureRecognizerToFail:dismissPan];
	[self.content addGestureRecognizer:nextMemory];
	UISwipeGestureRecognizer *previousMemory = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedToPreviousMemory)];
	previousMemory.direction = UISwipeGestureRecognizerDirectionRight;
	[previousMemory requireGestureRecognizerToFail:dismissPan];
	[self.content addGestureRecognizer:previousMemory];

	UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHold:)];
	hold.minimumPressDuration = 0.2;
	hold.delegate = self;
	[self.content addGestureRecognizer:hold];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
	tap.delegate = self;
	[tap requireGestureRecognizerToFail:hold];
	[self.content addGestureRecognizer:tap];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
	for (UIView *view = touch.view; view && view != self.content; view = view.superview) {
		if ([view isKindOfClass:[UIControl class]]) {
			return NO; 
		}
	}
	return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
	if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
		CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
		return velocity.y > 0 && velocity.y > fabs(velocity.x);
	}
	return YES;
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
	CGFloat x = [tap locationInView:self.content].x;
	if (x < self.content.bounds.size.width / 3) {
		[self stepBackward];
	} else {
		[self stepForward];
	}
}

- (void)handleHold:(UILongPressGestureRecognizer *)hold {
	if (hold.state == UIGestureRecognizerStateBegan) {
		self.holding = YES;
		[self updatePauseState];
		[UIView animateWithDuration:0.2 animations:^{ self.chrome.alpha = 0; }];
	} else if (hold.state == UIGestureRecognizerStateEnded || hold.state == UIGestureRecognizerStateCancelled ||
	           hold.state == UIGestureRecognizerStateFailed) {
		self.holding = NO;
		[self updatePauseState];
		[UIView animateWithDuration:0.2 animations:^{ self.chrome.alpha = 1; }];
	}
}

- (void)swipedToNextMemory {
	if (self.memoryIndex + 1 < (NSInteger)self.memories.count) {
		[self showMemoryAtIndex:self.memoryIndex + 1 assetIndex:0 animated:YES];
	}
}

- (void)swipedToPreviousMemory {
	if (self.memoryIndex > 0) {
		[self showMemoryAtIndex:self.memoryIndex - 1 assetIndex:0 animated:YES];
	}
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)pan {
	CGPoint translation = [pan translationInView:self.view];
	switch (pan.state) {
		case UIGestureRecognizerStateBegan:
			self.dragging = YES;
			[self updatePauseState];
			break;
		case UIGestureRecognizerStateChanged: {
			CGFloat down = MAX(0, translation.y);
			CGFloat progress = MIN(1, down / self.view.bounds.size.height);
			CGFloat scale = 1 - 0.25 * progress;
			self.content.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(translation.x * 0.5, down), scale, scale);
			self.content.layer.cornerRadius = 24 * MIN(1, progress * 4);
			self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:MAX(0, 1 - progress * 1.5)];
			break;
		}
		case UIGestureRecognizerStateEnded:
		case UIGestureRecognizerStateCancelled: {
			CGFloat velocity = [pan velocityInView:self.view].y;
			if (pan.state == UIGestureRecognizerStateEnded && (translation.y > 120 || velocity > 800)) {
				[self dismiss];
				return;
			}
			[UIView animateWithDuration:0.4
			                      delay:0
			     usingSpringWithDamping:0.82
			      initialSpringVelocity:0
			                    options:UIViewAnimationOptionBeginFromCurrentState
			                 animations:^{
				                 self.content.transform = CGAffineTransformIdentity;
				                 self.content.layer.cornerRadius = 0;
				                 self.view.backgroundColor = UIColor.blackColor;
			                 }
			                 completion:nil];
			self.dragging = NO;
			[self updatePauseState];
			break;
		}
		default:
			break;
	}
}

#pragma mark Playback

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (!self.link) {
		self.lastTick = CACurrentMediaTime();
		self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
		[self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	}
	[self updatePauseState];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (self.isBeingDismissed) {
		[self.link invalidate];
		self.link = nil;
	}
}

- (BOOL)isPaused {
	return self.holding || self.dragging || (self.presentedViewController && !self.presentedViewController.isBeingDismissed);
}

- (void)updatePauseState {
	CALayer *layer = self.stage.layer;
	BOOL paused = [self isPaused];
	self.wasPaused = paused;
	if (paused && layer.speed != 0) {
		CFTimeInterval pausedTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
		layer.speed = 0;
		layer.timeOffset = pausedTime;
	} else if (!paused && layer.speed == 0) {
		CFTimeInterval pausedTime = layer.timeOffset;
		layer.speed = 1;
		layer.timeOffset = 0;
		layer.beginTime = 0;
		layer.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - pausedTime;
	}
	self.lastTick = CACurrentMediaTime();
}

- (void)tick:(CADisplayLink *)link {
	CFTimeInterval now = CACurrentMediaTime();
	CFTimeInterval dt = MIN(0.1, now - self.lastTick);
	self.lastTick = now;
	if ([self isPaused] != self.wasPaused) {
		[self updatePauseState];
	}
	if ([self isPaused] || !self.photoReady) {
		return;
	}
	self.elapsed += dt;
	self.progressView.progress = (CGFloat)(self.elapsed / kMemoryPhotoDuration);
	if (self.elapsed >= kMemoryPhotoDuration) {
		[self stepForward];
	}
}

- (void)stepForward {
	if (self.assetIndex + 1 < (NSInteger)self.currentMemory.assets.count) {
		[self showAssetAtIndex:self.assetIndex + 1];
	} else if (self.memoryIndex + 1 < (NSInteger)self.memories.count) {
		[self showMemoryAtIndex:self.memoryIndex + 1 assetIndex:0 animated:YES];
	} else {
		[self dismiss];
	}
}

- (void)stepBackward {
	if (self.assetIndex > 0) {
		[self showAssetAtIndex:self.assetIndex - 1];
	} else if (self.memoryIndex > 0) {
		NSInteger previous = self.memoryIndex - 1;
		[self showMemoryAtIndex:previous assetIndex:MAX(0, (NSInteger)self.memories[previous].assets.count - 1) animated:YES];
	} else {
		[self showAssetAtIndex:0]; 
	}
}

- (void)showMemoryAtIndex:(NSInteger)memoryIndex assetIndex:(NSInteger)assetIndex animated:(BOOL)animated {
	if (self.memories.count == 0) {
		[self dismiss];
		return;
	}
	self.memoryIndex = MAX(0, MIN(memoryIndex, (NSInteger)self.memories.count - 1));
	IMMemory *memory = self.currentMemory;
	void (^apply)(void) = ^{
		self.titleLabel.text = memory.displayTitle;
		self.subtitleLabel.text = memory.displaySubtitle.uppercaseString;
	};
	if (animated) {
		[UIView transitionWithView:self.chrome duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:apply completion:nil];
	} else {
		apply();
	}
	self.progressView.count = (NSInteger)memory.assets.count;
	[self updateSaveButton];
	if (@available(iOS 14.0, *)) {
		[self updateMoreMenu];
	}
	[self showAssetAtIndex:MAX(0, MIN(assetIndex, (NSInteger)memory.assets.count - 1))];
}

- (void)showAssetAtIndex:(NSInteger)index {
	IMMemory *memory = self.currentMemory;
	if (memory.assets.count == 0) {
		self.photoView.image = nil;
		self.backdropView.image = nil;
		self.photoReady = YES; 
		self.elapsed = 0;
		return;
	}
	self.assetIndex = index;
	self.elapsed = 0;
	self.photoReady = NO;
	self.progressView.index = index;
	self.progressView.progress = 0;
	IMAsset *asset = memory.assets[index];
	self.captionLabel.text = [self captionForAsset:asset];

	[self.photoTask cancel];
	[self.fallbackTask cancel];
	NSUInteger generation = ++self.photoGeneration;
	__weak typeof(self) weakSelf = self;
	self.fallbackTask = [[IMThumbCache shared] thumbnailForAssetId:asset.assetId
	                                                            size:[IMPrefs shared].thumbnailQuality
	                                                      completion:^(UIImage *_Nullable image) {
		    typeof(self) strongSelf = weakSelf;
		    if (strongSelf && strongSelf.photoGeneration == generation && !strongSelf.photoReady && image) {
			    [strongSelf displayPhoto:image fresh:YES];
		    }
	    }];
	self.photoTask = [[IMThumbCache shared] thumbnailForAssetId:asset.assetId
	                                                         size:IMAssetMediaSizePreview
	                                                   completion:^(UIImage *_Nullable image) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || strongSelf.photoGeneration != generation) return;
		    if (image) {
			    [strongSelf displayPhoto:image fresh:!strongSelf.photoReady];
		    }
		    strongSelf.photoReady = YES;
	    }];
	[self prefetchAfterIndex:index];
}

- (void)displayPhoto:(UIImage *)image fresh:(BOOL)fresh {
	if (!fresh) {
		self.photoView.image = image;
		return;
	}
	[UIView transitionWithView:self.photoView duration:0.45 options:UIViewAnimationOptionTransitionCrossDissolve
	                animations:^{ self.photoView.image = image; } completion:nil];
	[UIView transitionWithView:self.backdropView duration:0.45 options:UIViewAnimationOptionTransitionCrossDissolve
	                animations:^{ self.backdropView.image = image; } completion:nil];
	self.photoReady = YES;
	[self startKenBurns];
}

- (void)startKenBurns {
	CALayer *layer = self.stage.layer;
	[layer removeAllAnimations];
	self.stage.transform = CGAffineTransformIdentity;
	if (UIAccessibilityIsReduceMotionEnabled()) {
		return;
	}
	self.kenBurnsFlip = !self.kenBurnsFlip;
	CGFloat drift = self.view.bounds.size.width * 0.02 * (self.kenBurnsFlip ? 1 : -1);
	BOOL wasPaused = layer.speed == 0;
	if (wasPaused) {
		layer.speed = 1;
		layer.timeOffset = 0;
		layer.beginTime = 0;
	}
	[UIView animateWithDuration:kMemoryPhotoDuration + 0.6
	                      delay:0
	                    options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionAllowUserInteraction
	                 animations:^{
		                 self.stage.transform = CGAffineTransformTranslate(CGAffineTransformMakeScale(kKenBurnsScale, kKenBurnsScale), drift, 0);
	                 }
	                 completion:nil];
	if (wasPaused) {
		[self updatePauseState];
	}
}

- (void)prefetchAfterIndex:(NSInteger)index {
	NSArray<IMAsset *> *assets = self.currentMemory.assets;
	for (NSInteger i = index + 1; i <= index + 2 && i < (NSInteger)assets.count; i++) {
		[[IMThumbCache shared] thumbnailForAssetId:assets[i].assetId size:IMAssetMediaSizePreview completion:^(UIImage *_Nullable image) {}];
	}
}

- (NSString *)captionForAsset:(IMAsset *)asset {
	static NSDateFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [[NSDateFormatter alloc] init];
		[formatter setLocalizedDateFormatFromTemplate:@"MMMd jmm"];
	});
	NSDate *date = IMDateFromServerTimestamp(asset.fileCreatedAt);
	NSString *when = date ? [formatter stringFromDate:date] : @"";
	NSString *where = asset.city.length ? asset.city : asset.country;
	if (where.length && when.length) {
		return [NSString stringWithFormat:@"%@ · %@", when, where];
	}
	return where.length ? where : when;
}

#pragma mark Actions

- (void)closeTapped {
	[self dismiss];
}

- (void)dismiss {
	if (self.isBeingDismissed || self.presentingViewController == nil) {
		return;
	}
	[self.link invalidate];
	self.link = nil;
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateSaveButton {
	BOOL saved = self.currentMemory.isSaved;
	if (@available(iOS 13.0, *)) {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
		[self.saveButton setImage:[UIImage systemImageNamed:saved ? @"bookmark.fill" : @"bookmark" withConfiguration:config]
		                 forState:UIControlStateNormal];
	}
	self.saveButton.accessibilityLabel = saved ? _(@"Unsave memory") : _(@"Save memory");
}

- (void)replaceCurrentMemory:(IMMemory *)memory {
	NSInteger index = self.memoryIndex;
	if (index >= 0 && index < (NSInteger)self.memories.count) {
		self.memories[index] = memory;
	}
	if (self.onChange) self.onChange();
}

- (void)toggleSaved {
	IMMemory *memory = self.currentMemory;
	self.saveButton.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMMemoryApi updateMemoryId:memory.memoryId isSaved:!memory.isSaved completion:^(IMMemory *_Nullable updated, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.saveButton.enabled = YES;
		if (!updated) {
			[strongSelf presentError:error title:_(@"Couldn't update memory")];
			return;
		}
		if ([strongSelf.currentMemory.memoryId isEqualToString:updated.memoryId]) {
			[strongSelf replaceCurrentMemory:updated];
			[strongSelf updateSaveButton];
		}
	}];
}

- (void)updateMoreMenu API_AVAILABLE(ios(14.0)) {
	__weak typeof(self) weakSelf = self;
	UIAction *all = [UIAction actionWithTitle:_(@"Show All Photos") image:[UIImage systemImageNamed:@"square.grid.3x3"] identifier:nil handler:^(UIAction *action) {
		[weakSelf showAllPhotos];
	}];
	UIAction *edit = [UIAction actionWithTitle:_(@"Edit Memory") image:[UIImage systemImageNamed:@"pencil"] identifier:nil handler:^(UIAction *action) {
		[weakSelf editMemory];
	}];
	UIAction *delete = [UIAction actionWithTitle:_(@"Delete Memory") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
		[weakSelf confirmDelete];
	}];
	delete.attributes = UIMenuElementAttributesDestructive;
	self.moreButton.menu = [UIMenu menuWithTitle:@"" children:@[ all, edit, delete ]];
}

- (void)moreTapped {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Show All Photos") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf showAllPhotos]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Edit Memory") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [weakSelf editMemory]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Delete Memory") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [weakSelf confirmDelete]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.moreButton;
	sheet.popoverPresentationController.sourceRect = self.moreButton.bounds;
	[self presentPausing:sheet];
}

- (void)presentPausing:(UIViewController *)controller {
	[self presentViewController:controller animated:YES completion:nil];
	[self updatePauseState];
}

- (void)doneWithSheet {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showAllPhotos {
	IMMemory *memory = self.currentMemory;
	AssetGridViewController *grid = [AssetGridViewController gridWithTitle:memory.displayTitle assets:memory.assets];
	grid.title = memory.displayTitle;
	grid.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                                                                                        target:self
	                                                                                        action:@selector(doneWithSheet)];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:grid];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	[self presentPausing:nav];
}

- (void)editMemory {
	MemoryEditorViewController *editor = [[MemoryEditorViewController alloc] initWithMemory:self.currentMemory];
	__weak typeof(self) weakSelf = self;
	editor.onSaved = ^(IMMemory *memory) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf replaceCurrentMemory:memory];
		[strongSelf showMemoryAtIndex:strongSelf.memoryIndex assetIndex:strongSelf.assetIndex animated:NO];
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	[self presentPausing:nav];
}

- (void)confirmDelete {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete memory?")
	                                                               message:_(@"The photos will stay in your library.")
	                                                        preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *memoryId = strongSelf.currentMemory.memoryId;
		[IMMemoryApi deleteMemoryId:memoryId completion:^(BOOL success, NSError *_Nullable error) {
			typeof(self) inner = weakSelf;
			if (!inner) return;
			if (!success) {
				[inner presentError:error title:_(@"Couldn't delete memory")];
				return;
			}
			NSUInteger index = [inner.memories indexOfObjectPassingTest:^BOOL(IMMemory *m, NSUInteger i, BOOL *stop) {
				return [m.memoryId isEqualToString:memoryId];
			}];
			if (index != NSNotFound) [inner.memories removeObjectAtIndex:index];
			if (inner.onChange) inner.onChange();
			if (inner.memories.count == 0) {
				[inner dismiss];
				return;
			}
			[inner showMemoryAtIndex:MIN(inner.memoryIndex, (NSInteger)inner.memories.count - 1) assetIndex:0 animated:YES];
		}];
	}]];
	[self presentPausing:alert];
}

- (void)presentError:(nullable NSError *)error title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
	                                                               message:error.localizedDescription
	                                                        preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentPausing:alert];
}

#pragma mark Transitions

- (nullable id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                            presentingController:(UIViewController *)presenting
                                                                                sourceController:(UIViewController *)source {
	IMMemoryPlayerTransition *transition = [[IMMemoryPlayerTransition alloc] init];
	transition.presenting = YES;
	return transition;
}

- (nullable id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
	return [[IMMemoryPlayerTransition alloc] init];
}

@end

@implementation IMMemoryPlayerTransition

- (NSTimeInterval)transitionDuration:(nullable id<UIViewControllerContextTransitioning>)context {
	return self.presenting ? 0.42 : 0.3;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
	UIView *container = context.containerView;
	if (self.presenting) {
		IMMemoryPlayerViewController *player =
		    (IMMemoryPlayerViewController *)[context viewControllerForKey:UITransitionContextToViewControllerKey];
		UIView *toView = [context viewForKey:UITransitionContextToViewKey];
		toView.frame = [context finalFrameForViewController:player];
		[container addSubview:toView];
		UIImageView *source = player.sourceImageView;
		if (!source.image || !source.window) {
			toView.alpha = 0;
			toView.transform = CGAffineTransformMakeScale(0.94, 0.94);
			[UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
				toView.alpha = 1;
				toView.transform = CGAffineTransformIdentity;
			} completion:^(BOOL finished) { [context completeTransition:YES]; }];
			return;
		}
		UIImageView *moving = [[UIImageView alloc] initWithImage:source.image];
		moving.contentMode = UIViewContentModeScaleAspectFill;
		moving.clipsToBounds = YES;
		moving.layer.cornerRadius = 12;
		moving.frame = [source convertRect:source.bounds toView:container];
		[container addSubview:moving];
		toView.alpha = 0;
		[UIView animateWithDuration:[self transitionDuration:context]
		                      delay:0
		     usingSpringWithDamping:0.88
		      initialSpringVelocity:0
		                    options:0
		                 animations:^{
			                 moving.frame = container.bounds;
			                 moving.layer.cornerRadius = 0;
		                 }
		                 completion:nil];
		[UIView animateWithDuration:0.3 delay:0.15 options:0 animations:^{
			toView.alpha = 1;
		} completion:^(BOOL finished) {
			[moving removeFromSuperview];
			[context completeTransition:YES];
		}];
		return;
	}
	UIView *fromView = [context viewForKey:UITransitionContextFromViewKey];
	[UIView animateWithDuration:[self transitionDuration:context]
	                      delay:0
	                    options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
	                 animations:^{
		                 fromView.alpha = 0;
		                 fromView.transform = CGAffineTransformScale(fromView.transform, 0.92, 0.92);
	                 }
	                 completion:^(BOOL finished) { [context completeTransition:YES]; }];
}

@end
