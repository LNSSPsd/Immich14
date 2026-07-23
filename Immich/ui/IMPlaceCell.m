#import "IMPlaceCell.h"
#import "IMThumbCache.h"
#import "IMAssetApi.h"

NSString *const IMPlaceCellReuseIdentifier = @"IMPlaceCell";

@interface IMPlaceCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *scrim;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong, nullable) IMThumbCacheTask *thumbTask;
@end

@implementation IMPlaceCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.contentView.layer.cornerRadius = 8;
		self.contentView.layer.masksToBounds = YES;
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

		self.scrim = [[UIView alloc] init];
		self.scrim.translatesAutoresizingMaskIntoConstraints = NO;
		self.scrim.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.45];
		[self.contentView addSubview:self.scrim];

		self.nameLabel = [[UILabel alloc] init];
		self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.nameLabel.font = [UIFont boldSystemFontOfSize:13];
		self.nameLabel.textColor = UIColor.whiteColor;
		self.nameLabel.numberOfLines = 1;
		[self.contentView addSubview:self.nameLabel];

		[NSLayoutConstraint activateConstraints:@[
			[self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],

			[self.scrim.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.scrim.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.scrim.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
			[self.scrim.heightAnchor constraintEqualToConstant:26],

			[self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:6],
			[self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-6],
			[self.nameLabel.centerYAnchor constraintEqualToAnchor:self.scrim.centerYAnchor],
		]];
	}
	return self;
}

- (void)configureWithAsset:(nullable IMAsset *)asset cityName:(nullable NSString *)cityName {
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;
	self.nameLabel.text = cityName;

	if (!asset) {
		return;
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
	self.nameLabel.text = nil;
}

@end
