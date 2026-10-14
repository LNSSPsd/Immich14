#import "TimelineCell.h"
#import "IMThumbCache.h"
#import "IMAssetApi.h"
#import "IMPrefs.h"
#import "common.h"
#import <math.h>

NSString *const TimelineCellReuseIdentifier = @"TimelineCell";

@interface TimelineCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *stackLabel;
@property (nonatomic, strong) UIImageView *syncBadgeView;
@property (nonatomic, strong) UIImageView *selectionCircleView;
@property (nonatomic, strong, nullable) IMThumbCacheTask *thumbTask;
@property (nonatomic) PHImageRequestID localRequestId;
@property (nonatomic, strong, nullable) IMThumbCacheTask *highResTask;
@property (nonatomic, copy, nullable) NSString *assetId;      
@property (nonatomic, copy, nullable) NSString *loadedSize;   
@end

static NSString *IMTimelineAccessibilityDate(NSDate *date, NSString *fallback) {
	if (!date) return fallback ?: @"";
	static NSDateFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterMediumStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
	});
	return [formatter stringFromDate:date] ?: fallback ?: @"";
}

@implementation TimelineCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		if (@available(iOS 13.0, *)) {
			self.contentView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
		} else {
			self.contentView.backgroundColor = UIColor.groupTableViewBackgroundColor;
		}

		self.imageView = [[UIImageView alloc] init];
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
		self.imageView.frame = self.contentView.bounds;
		self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self.contentView addSubview:self.imageView];

		self.durationLabel = [[UILabel alloc] init];
		self.durationLabel.font = [UIFont boldSystemFontOfSize:11];
		self.durationLabel.textColor = UIColor.whiteColor;
		self.durationLabel.hidden = YES;
		[self.contentView addSubview:self.durationLabel];

		self.stackLabel = [[UILabel alloc] init];
		self.stackLabel.font = [UIFont boldSystemFontOfSize:11];
		self.stackLabel.textColor = UIColor.whiteColor;
		self.stackLabel.hidden = YES;
		[self.contentView addSubview:self.stackLabel];

		self.syncBadgeView = [[UIImageView alloc] init];
		self.syncBadgeView.tintColor = UIColor.whiteColor;
		self.syncBadgeView.hidden = YES;
		self.syncBadgeView.layer.shadowColor = UIColor.blackColor.CGColor;
		self.syncBadgeView.layer.shadowOpacity = 0.6;
		self.syncBadgeView.layer.shadowRadius = 1.5;
		self.syncBadgeView.layer.shadowOffset = CGSizeZero;
		[self.contentView addSubview:self.syncBadgeView];

		self.selectionCircleView = [[UIImageView alloc] init];
		self.selectionCircleView.tintColor = UIColor.whiteColor;
		self.selectionCircleView.hidden = YES;
		self.selectionCircleView.layer.shadowColor = UIColor.blackColor.CGColor;
		self.selectionCircleView.layer.shadowOpacity = 0.6;
		self.selectionCircleView.layer.shadowRadius = 1.5;
		self.selectionCircleView.layer.shadowOffset = CGSizeZero;
		[self.contentView addSubview:self.selectionCircleView];

		self.localRequestId = PHInvalidImageRequestID;

	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.contentView.bounds;
	CGFloat inset = 4;
	if (!self.durationLabel.hidden) {
		[self.durationLabel sizeToFit];
		CGSize size = self.durationLabel.bounds.size;
		self.durationLabel.frame = CGRectMake(CGRectGetMaxX(bounds) - inset - size.width,
		                                      CGRectGetMaxY(bounds) - inset - size.height,
		                                      size.width, size.height);
	}
	if (!self.stackLabel.hidden) {
		[self.stackLabel sizeToFit];
		CGSize size = self.stackLabel.bounds.size;
		self.stackLabel.frame = CGRectMake(inset, CGRectGetMaxY(bounds) - inset - size.height, size.width, size.height);
	}
	self.syncBadgeView.frame = CGRectMake(inset, CGRectGetMaxY(bounds) - inset - 15, 15, 15);
	self.selectionCircleView.frame = CGRectMake(CGRectGetMaxX(bounds) - inset - 20, inset, 20, 20);
}

- (void)setSelectionModeEnabled:(BOOL)selectionModeEnabled {
	_selectionModeEnabled = selectionModeEnabled;
	self.selectionCircleView.hidden = !selectionModeEnabled;
	[self updateSelectionCircleImage];
	[self updateAccessibilityTraits];
}

- (void)setSelected:(BOOL)selected {
	[super setSelected:selected];
	[self updateSelectionCircleImage];
	[self updateAccessibilityTraits];
}

- (void)updateAccessibilityTraits {
	if (!self.isAccessibilityElement) return;
	UIAccessibilityTraits traits = UIAccessibilityTraitImage;
	if (self.selectionModeEnabled) traits |= UIAccessibilityTraitButton;
	if (self.selectionModeEnabled && self.selected) traits |= UIAccessibilityTraitSelected;
	self.accessibilityTraits = traits;
}

- (void)setAccessibilityForAsset:(IMAsset *)asset {
	self.isAccessibilityElement = asset != nil;
	if (!asset) {
		self.accessibilityLabel = nil;
		self.accessibilityValue = nil;
		return;
	}
	NSString *kind = asset.isImage ? _(@"Photo") : _(@"Video");
	NSString *date = IMTimelineAccessibilityDate(IMDateFromServerTimestamp(asset.fileCreatedAt), asset.fileCreatedAt);
	self.accessibilityLabel = date.length ? [NSString stringWithFormat:_(@"%@, %@"), kind, date] : kind;
	NSMutableArray<NSString *> *details = [NSMutableArray array];
	if (!asset.isImage && asset.durationMs > 0) {
		NSInteger totalSeconds = asset.durationMs / 1000;
		[details addObject:[NSString stringWithFormat:_(@"Duration %ld minutes %ld seconds"), (long)(totalSeconds / 60), (long)(totalSeconds % 60)]];
	}
	if (asset.isFavorite) [details addObject:_(@"Favorite")];
	if (asset.stackAssetCount > 1) [details addObject:[NSString stringWithFormat:_(@"%ld items in stack"), (long)asset.stackAssetCount]];
	self.accessibilityValue = [details componentsJoinedByString:@", "];
	[self updateAccessibilityTraits];
}

- (void)setAccessibilityForLocalAsset:(PHAsset *)asset syncState:(IMSyncState)state {
	self.isAccessibilityElement = asset != nil;
	if (!asset) {
		self.accessibilityLabel = nil;
		self.accessibilityValue = nil;
		return;
	}
	NSString *kind = asset.mediaType == PHAssetMediaTypeVideo ? _(@"Video") : _(@"Photo");
	NSString *date = IMTimelineAccessibilityDate(asset.creationDate, nil);
	self.accessibilityLabel = date.length ? [NSString stringWithFormat:_(@"%@, %@"), kind, date] : kind;
	NSMutableArray<NSString *> *details = [NSMutableArray array];
	if (asset.mediaType == PHAssetMediaTypeVideo && asset.duration > 0) {
		NSInteger totalSeconds = (NSInteger)llround(asset.duration);
		[details addObject:[NSString stringWithFormat:_(@"Duration %ld minutes %ld seconds"), (long)(totalSeconds / 60), (long)(totalSeconds % 60)]];
	}
	if (asset.favorite) [details addObject:_(@"Favorite")];
	if (state == IMSyncStateUploading) [details addObject:_(@"Uploading")];
	else if (state == IMSyncStateLocalOnly) [details addObject:_(@"Waiting to upload")];
	self.accessibilityValue = [details componentsJoinedByString:@", "];
	[self updateAccessibilityTraits];
}

- (void)updateSelectionCircleImage {
	if (!self.selectionModeEnabled) {
		return;
	}
	if (@available(iOS 13.0, *)) {
		self.selectionCircleView.image = [UIImage systemImageNamed:self.selected ? @"checkmark.circle.fill" : @"circle"];
	}
	self.selectionCircleView.tintColor = self.selected ? UIColor.systemBlueColor : UIColor.whiteColor;
}

- (void)cancelPendingRequests {
	[self.thumbTask cancel];
	self.thumbTask = nil;
	[self.highResTask cancel];
	self.highResTask = nil;
	if (self.localRequestId != PHInvalidImageRequestID) {
		[[PHImageManager defaultManager] cancelImageRequest:self.localRequestId];
		self.localRequestId = PHInvalidImageRequestID;
	}
}

static NSString *const kSkeletonAnimationKey = @"skeletonPulse";

- (void)startSkeletonPulse {
	if ([self.contentView.layer animationForKey:kSkeletonAnimationKey]) {
		return;
	}
	CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
	pulse.fromValue = @(1.0);
	pulse.toValue = @(0.4);
	pulse.duration = 0.8;
	pulse.autoreverses = YES;
	pulse.repeatCount = HUGE_VALF;
	pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	[self.contentView.layer addAnimation:pulse forKey:kSkeletonAnimationKey];
}

- (void)stopSkeletonPulse {
	[self.contentView.layer removeAnimationForKey:kSkeletonAnimationKey];
}

- (void)configureWithAsset:(nullable IMAsset *)asset {
	[self cancelPendingRequests];
	self.imageView.image = nil;
	self.assetId = asset.assetId;
	self.loadedSize = nil;
	self.syncBadgeView.hidden = YES;
	self.stackLabel.hidden = YES;

	if (!asset) {
		self.durationLabel.hidden = YES;
		self.stackLabel.hidden = YES;
		[self setAccessibilityForAsset:nil];
		[self startSkeletonPulse];
		return;
	}
	[self stopSkeletonPulse];
	[self setAccessibilityForAsset:asset];

	if (asset.isImage || asset.durationMs <= 0) {
		self.durationLabel.hidden = YES;
	} else {
		NSInteger totalSeconds = asset.durationMs / 1000;
		self.durationLabel.text = [NSString stringWithFormat:@"%ld:%02ld", (long)(totalSeconds / 60), (long)(totalSeconds % 60)];
		self.durationLabel.hidden = NO;
		[self setNeedsLayout];
	}
	if (asset.stackId.length > 0 && asset.stackAssetCount > 1) {
		self.stackLabel.text = [NSString stringWithFormat:@"▦ %ld", (long)asset.stackAssetCount];
		self.stackLabel.hidden = NO;
		[self setNeedsLayout];
	} else {
		self.stackLabel.hidden = YES;
	}

	NSString *assetId = asset.assetId;
	NSString *size = [IMPrefs shared].thumbnailQuality;
	__weak typeof(self) weakSelf = self;
	self.thumbTask = [[IMThumbCache shared] thumbnailForAssetId:assetId
	                                                         size:size
	                                                   completion:^(UIImage *_Nullable image) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || !image || [strongSelf.loadedSize isEqualToString:IMAssetMediaSizePreview]) {
			    return; 
		    }
		    strongSelf.imageView.image = image;
		    strongSelf.loadedSize = size;
	    }];
	if (self.prefersHighResolution) {
		[self requestHighResolution];
	}
}

- (void)setPrefersHighResolution:(BOOL)prefersHighResolution {
	_prefersHighResolution = prefersHighResolution;
	if (prefersHighResolution) {
		[self requestHighResolution];
	}
}

- (void)requestHighResolution {
	if (!self.assetId || self.highResTask || [self.loadedSize isEqualToString:IMAssetMediaSizePreview] ||
	    [[IMPrefs shared].thumbnailQuality isEqualToString:IMAssetMediaSizePreview]) {
		return;
	}
	__weak typeof(self) weakSelf = self;
	self.highResTask = [[IMThumbCache shared] thumbnailForAssetId:self.assetId
	                                                          size:IMAssetMediaSizePreview
	                                                    completion:^(UIImage *_Nullable image) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf || !image) {
			    return;
		    }
		    strongSelf.imageView.image = image;
		    strongSelf.loadedSize = IMAssetMediaSizePreview;
	    }];
}

- (void)configureWithLocalAsset:(nullable PHAsset *)asset syncState:(IMSyncState)state {
	[self cancelPendingRequests];
	self.imageView.image = nil;
	self.assetId = nil;
	self.loadedSize = nil;
	self.durationLabel.hidden = YES;
	self.stackLabel.hidden = YES;

	if (!asset) {
		self.syncBadgeView.hidden = YES;
		[self setAccessibilityForLocalAsset:nil syncState:state];
		[self startSkeletonPulse];
		return;
	}
	[self stopSkeletonPulse];
	[self setAccessibilityForLocalAsset:asset syncState:state];

	if (@available(iOS 13.0, *)) {
		self.syncBadgeView.image = [UIImage systemImageNamed:state == IMSyncStateUploading ? @"icloud.and.arrow.up.fill" : @"icloud.slash.fill"];
	}
	self.syncBadgeView.hidden = NO;

	PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
	options.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
	options.resizeMode = PHImageRequestOptionsResizeModeFast;
	options.networkAccessAllowed = YES;

	CGFloat scale = UIScreen.mainScreen.scale;
	CGSize targetSize = CGSizeMake(120 * scale, 120 * scale);
	__weak typeof(self) weakSelf = self;
	self.localRequestId = [[PHImageManager defaultManager]
	    requestImageForAsset:asset
	              targetSize:targetSize
	             contentMode:PHImageContentModeAspectFill
	                 options:options
	           resultHandler:^(UIImage *_Nullable result, NSDictionary *_Nullable info) {
		    weakSelf.imageView.image = result;
	    }];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self cancelPendingRequests];
	[self stopSkeletonPulse];
	self.imageView.image = nil;
	self.assetId = nil;
	self.loadedSize = nil;
	self.durationLabel.hidden = YES;
	self.syncBadgeView.hidden = YES;
	self.stackLabel.hidden = YES;
	[self setAccessibilityForAsset:nil];
}

@end
