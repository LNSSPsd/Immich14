#import "IMMemoryCell.h"
#import "IMThumbCache.h"
#import "IMAssetApi.h"
#import "common.h"

NSString *const IMMemoryCellReuseIdentifier = @"IMMemoryCell";

@interface IMMemoryCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) CAGradientLayer *scrim;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *savedImageView;
@property (nonatomic, strong, nullable) IMThumbCacheTask *thumbTask;
@end

@implementation IMMemoryCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.layer.shadowColor = UIColor.blackColor.CGColor;
		self.layer.shadowOpacity = 0.18;
		self.layer.shadowRadius = 10;
		self.layer.shadowOffset = CGSizeMake(0, 4);

		self.card = [[UIView alloc] initWithFrame:self.contentView.bounds];
		self.card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		self.card.layer.cornerRadius = 12;
		if (@available(iOS 13.0, *)) {
			self.card.layer.cornerCurve = kCACornerCurveContinuous;
		}
		self.card.clipsToBounds = YES;
		self.card.backgroundColor = UIColor.secondarySystemBackgroundColor;
		[self.contentView addSubview:self.card];

		self.imageView = [[UIImageView alloc] initWithFrame:self.card.bounds];
		self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
		[self.card addSubview:self.imageView];

		self.scrim = [CAGradientLayer layer];
		self.scrim.colors = @[
			(id)[UIColor colorWithWhite:0 alpha:0].CGColor,
			(id)[UIColor colorWithWhite:0 alpha:0.25].CGColor,
			(id)[UIColor colorWithWhite:0 alpha:0.65].CGColor,
		];
		self.scrim.locations = @[ @0.35, @0.6, @1.0 ];
		[self.card.layer addSublayer:self.scrim];

		self.titleLabel = [[UILabel alloc] init];
		self.titleLabel.textColor = UIColor.whiteColor;
		self.titleLabel.numberOfLines = 2;
		self.titleLabel.adjustsFontSizeToFitWidth = YES;
		self.titleLabel.minimumScaleFactor = 0.7;
		[self.card addSubview:self.titleLabel];

		self.subtitleLabel = [[UILabel alloc] init];
		self.subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
		self.subtitleLabel.numberOfLines = 1;
		[self.card addSubview:self.subtitleLabel];

		self.savedImageView = [[UIImageView alloc] init];
		self.savedImageView.tintColor = UIColor.whiteColor;
		self.savedImageView.contentMode = UIViewContentModeScaleAspectFit;
		self.savedImageView.layer.shadowColor = UIColor.blackColor.CGColor;
		self.savedImageView.layer.shadowOpacity = 0.5;
		self.savedImageView.layer.shadowRadius = 2;
		self.savedImageView.layer.shadowOffset = CGSizeZero;
		[self.card addSubview:self.savedImageView];

		[self applyTypography];
	}
	return self;
}

- (void)setCompact:(BOOL)compact {
	_compact = compact;
	[self applyTypography];
	[self setNeedsLayout];
}

- (void)applyTypography {
	self.titleLabel.font = [UIFont systemFontOfSize:self.compact ? 17 : 26 weight:UIFontWeightBold];
	self.subtitleLabel.font = [UIFont systemFontOfSize:self.compact ? 11 : 13 weight:UIFontWeightSemibold];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGRect bounds = self.card.bounds;
	self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:12].CGPath;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	self.scrim.frame = bounds;
	[CATransaction commit];

	CGFloat inset = self.compact ? 10 : 16;
	CGFloat width = bounds.size.width - inset * 2;
	CGSize subtitleSize = [self.subtitleLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
	CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
	titleSize.height = MIN(titleSize.height, self.titleLabel.font.lineHeight * 2);
	CGFloat y = CGRectGetMaxY(bounds) - inset - subtitleSize.height;
	self.subtitleLabel.frame = CGRectMake(inset, y, width, subtitleSize.height);
	y -= titleSize.height + 1;
	self.titleLabel.frame = CGRectMake(inset, y, width, titleSize.height);
	CGFloat badge = self.compact ? 16 : 20;
	self.savedImageView.frame = CGRectMake(CGRectGetMaxX(bounds) - inset - badge, inset, badge, badge);
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	[UIView animateWithDuration:highlighted ? 0.12 : 0.3
	                      delay:0
	     usingSpringWithDamping:highlighted ? 1 : 0.6
	      initialSpringVelocity:0
	                    options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
	                 animations:^{
		                 self.transform = highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
	                 }
	                 completion:nil];
}

- (void)configureWithMemory:(nullable IMMemory *)memory {
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;
	self.titleLabel.text = memory.displayTitle;
	self.subtitleLabel.text = memory.displaySubtitle.uppercaseString;
	self.savedImageView.hidden = !memory.isSaved;
	if (@available(iOS 13.0, *)) {
		self.savedImageView.image = [UIImage systemImageNamed:@"bookmark.fill"];
	}
	self.isAccessibilityElement = memory != nil;
	self.accessibilityLabel = memory ? [NSString stringWithFormat:@"%@, %@", memory.displayTitle, memory.displaySubtitle] : nil;
	self.accessibilityTraits = UIAccessibilityTraitButton;
	[self setNeedsLayout];
	IMAsset *cover = memory.assets.firstObject;
	if (!cover) {
		return;
	}
	__weak typeof(self) weakSelf = self;
	self.thumbTask = [[IMThumbCache shared] thumbnailForAssetId:cover.assetId
	                                                         size:IMAssetMediaSizePreview
	                                                   completion:^(UIImage *_Nullable image) {
		    weakSelf.imageView.image = image;
	    }];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;
	self.transform = CGAffineTransformIdentity;
}

@end
