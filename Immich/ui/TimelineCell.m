#import "TimelineCell.h"
#import "IMThumbCache.h"
#import "IMAssetApi.h"
#import "common.h"

NSString *const TimelineCellReuseIdentifier = @"TimelineCell";

@interface TimelineCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong, nullable) IMThumbCacheTask *thumbTask;
@end

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
		self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
		[self.contentView addSubview:self.imageView];

		self.durationLabel = [[UILabel alloc] init];
		self.durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.durationLabel.font = [UIFont boldSystemFontOfSize:11];
		self.durationLabel.textColor = UIColor.whiteColor;
		self.durationLabel.hidden = YES;

		[self.contentView addSubview:self.durationLabel];

		[NSLayoutConstraint activateConstraints:@[
			[self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

			[self.durationLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
			[self.durationLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
		]];
	}
	return self;
}

- (void)configureWithAsset:(nullable IMAsset *)asset {
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;

	if (!asset) {
		self.durationLabel.hidden = YES;
		return;
	}

	if (asset.isImage || asset.durationMs <= 0) {
		self.durationLabel.hidden = YES;
	} else {
		NSInteger totalSeconds = asset.durationMs / 1000;
		self.durationLabel.text = [NSString stringWithFormat:@"%ld:%02ld", (long)(totalSeconds / 60), (long)(totalSeconds % 60)];
		self.durationLabel.hidden = NO;
	}

	NSString *assetId = asset.assetId;
	__weak typeof(self) weakSelf = self;
	self.thumbTask = [[IMThumbCache shared] thumbnailForAssetId:assetId
	                                                         size:IMAssetMediaSizeThumbnail
	                                                   completion:^(UIImage *_Nullable image) {
		    weakSelf.imageView.image = image;
	    }];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;
	self.durationLabel.hidden = YES;
}

@end
