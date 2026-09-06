#import "IMClusterCell.h"
#import "IMThumbCache.h"
#import "IMAssetApi.h"
#import "common.h"

NSString *const IMClusterCellReuseIdentifier = @"IMClusterCell";

static NSString *const kSkeletonAnimationKey = @"clusterSkeletonPulse";

@interface IMClusterCell ()
@property (nonatomic, strong) UIView *pillView;
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong, nullable) IMThumbCacheTask *thumbTask;
@property (nonatomic) PHImageRequestID localRequestId;
- (void)updateAccessibility;
@end

@implementation IMClusterCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.pillView = [[UIView alloc] init];
		self.pillView.translatesAutoresizingMaskIntoConstraints = NO;
		self.pillView.layer.cornerRadius = 14;
		self.pillView.clipsToBounds = YES;
		if (@available(iOS 13.0, *)) {
			self.pillView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
		} else {
			self.pillView.backgroundColor = UIColor.groupTableViewBackgroundColor;
		}
		[self.contentView addSubview:self.pillView];

		self.coverView = [[UIImageView alloc] init];
		self.coverView.translatesAutoresizingMaskIntoConstraints = NO;
		self.coverView.contentMode = UIViewContentModeScaleAspectFill;
		self.coverView.clipsToBounds = YES;
		self.coverView.layer.cornerRadius = 10;
		if (@available(iOS 13.0, *)) {
			self.coverView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
		} else {
			self.coverView.backgroundColor = UIColor.lightGrayColor;
		}
		[self.pillView addSubview:self.coverView];

		self.titleLabel = [[UILabel alloc] init];
		self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
		[self.pillView addSubview:self.titleLabel];

		self.countLabel = [[UILabel alloc] init];
		self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.countLabel.font = [UIFont systemFontOfSize:13];
		if (@available(iOS 13.0, *)) {
			self.countLabel.textColor = UIColor.secondaryLabelColor;
		} else {
			self.countLabel.textColor = UIColor.grayColor;
		}
		[self.pillView addSubview:self.countLabel];

		self.localRequestId = PHInvalidImageRequestID;

		[NSLayoutConstraint activateConstraints:@[
			[self.pillView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
			[self.pillView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
			[self.pillView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
			[self.pillView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],

			[self.coverView.leadingAnchor constraintEqualToAnchor:self.pillView.leadingAnchor constant:8],
			[self.coverView.centerYAnchor constraintEqualToAnchor:self.pillView.centerYAnchor],
			[self.coverView.widthAnchor constraintEqualToConstant:56],
			[self.coverView.heightAnchor constraintEqualToConstant:56],

			[self.titleLabel.leadingAnchor constraintEqualToAnchor:self.coverView.trailingAnchor constant:12],
			[self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.pillView.trailingAnchor constant:-12],
			[self.titleLabel.bottomAnchor constraintEqualToAnchor:self.pillView.centerYAnchor constant:-1],

			[self.countLabel.leadingAnchor constraintEqualToAnchor:self.coverView.trailingAnchor constant:12],
			[self.countLabel.topAnchor constraintEqualToAnchor:self.pillView.centerYAnchor constant:1],
		]];
	}
	return self;
}

- (void)cancelPendingRequests {
	[self.thumbTask cancel];
	self.thumbTask = nil;
	if (self.localRequestId != PHInvalidImageRequestID) {
		[[PHImageManager defaultManager] cancelImageRequest:self.localRequestId];
		self.localRequestId = PHInvalidImageRequestID;
	}
}

- (void)startSkeletonPulse {
	if ([self.coverView.layer animationForKey:kSkeletonAnimationKey]) {
		return;
	}
	CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
	pulse.fromValue = @(1.0);
	pulse.toValue = @(0.4);
	pulse.duration = 0.8;
	pulse.autoreverses = YES;
	pulse.repeatCount = HUGE_VALF;
	pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
	[self.coverView.layer addAnimation:pulse forKey:kSkeletonAnimationKey];
}

- (void)stopSkeletonPulse {
	[self.coverView.layer removeAnimationForKey:kSkeletonAnimationKey];
}

- (void)updateAccessibility {
	self.isAccessibilityElement = self.titleLabel.text.length > 0;
	self.accessibilityLabel = self.titleLabel.text.length > 0 ? self.titleLabel.text : nil;
	self.accessibilityValue = self.countLabel.text.length > 0 ? self.countLabel.text : nil;
	self.accessibilityHint = self.isAccessibilityElement ? _(@"Double-tap to browse this month.") : nil;
	self.accessibilityTraits = self.isAccessibilityElement ? UIAccessibilityTraitButton : UIAccessibilityTraitNone;
}

- (void)configureWithTitle:(NSString *)title count:(NSInteger)count coverAssetId:(nullable NSString *)assetId {
	[self cancelPendingRequests];
	self.coverView.image = nil;
	self.titleLabel.text = title;
	self.countLabel.text = [NSString stringWithFormat:_(@"%ld items"), (long)count];
	[self updateAccessibility];

	if (!assetId) {
		[self startSkeletonPulse];
		return;
	}
	[self stopSkeletonPulse];

	__weak typeof(self) weakSelf = self;
	self.thumbTask = [[IMThumbCache shared] thumbnailForAssetId:assetId
	                                                         size:IMAssetMediaSizeThumbnail
	                                                   completion:^(UIImage *_Nullable image) {
		    weakSelf.coverView.image = image;
	    }];
}

- (void)configureWithTitle:(NSString *)title count:(NSInteger)count coverLocalAsset:(nullable PHAsset *)asset {
	[self cancelPendingRequests];
	self.coverView.image = nil;
	self.titleLabel.text = title;
	self.countLabel.text = [NSString stringWithFormat:_(@"%ld items"), (long)count];
	[self updateAccessibility];

	if (!asset) {
		[self startSkeletonPulse];
		return;
	}
	[self stopSkeletonPulse];

	PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
	options.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
	options.resizeMode = PHImageRequestOptionsResizeModeFast;
	options.networkAccessAllowed = YES;

	CGFloat scale = UIScreen.mainScreen.scale;
	CGSize targetSize = CGSizeMake(56 * scale, 56 * scale);
	__weak typeof(self) weakSelf = self;
	self.localRequestId = [[PHImageManager defaultManager]
	    requestImageForAsset:asset
	              targetSize:targetSize
	             contentMode:PHImageContentModeAspectFill
	                 options:options
	           resultHandler:^(UIImage *_Nullable result, NSDictionary *_Nullable info) {
		    weakSelf.coverView.image = result;
	    }];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self cancelPendingRequests];
	[self stopSkeletonPulse];
	self.coverView.image = nil;
	self.titleLabel.text = nil;
	self.countLabel.text = nil;
	[self updateAccessibility];
}

@end
