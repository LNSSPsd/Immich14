#import "IMAlbumCell.h"
#import "IMThumbCache.h"
#import "IMAssetApi.h"
#import "IMPrefs.h"
#import "common.h"

NSString *const IMAlbumCellReuseIdentifier = @"IMAlbumCell";

@interface IMAlbumCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong, nullable) IMThumbCacheTask *thumbTask;
@end

@implementation IMAlbumCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.imageView = [[UIImageView alloc] init];
		self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
		self.imageView.layer.cornerRadius = 8;
		if (@available(iOS 13.0, *)) {
			self.imageView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
			self.imageView.tintColor = UIColor.tertiaryLabelColor;
		} else {
			self.imageView.backgroundColor = UIColor.groupTableViewBackgroundColor;
		}
		[self.contentView addSubview:self.imageView];

		self.nameLabel = [[UILabel alloc] init];
		self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.nameLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
		self.nameLabel.numberOfLines = 1;
		[self.contentView addSubview:self.nameLabel];

		self.countLabel = [[UILabel alloc] init];
		self.countLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.countLabel.font = [UIFont systemFontOfSize:12];
		if (@available(iOS 13.0, *)) {
			self.countLabel.textColor = UIColor.secondaryLabelColor;
		} else {
			self.countLabel.textColor = UIColor.grayColor;
		}
		[self.contentView addSubview:self.countLabel];

		[NSLayoutConstraint activateConstraints:@[
			[self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.imageView.heightAnchor constraintEqualToAnchor:self.imageView.widthAnchor],

			[self.nameLabel.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:6],
			[self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2],
			[self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2],

			[self.countLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2],
			[self.countLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2],
			[self.countLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2],
		]];
	}
	return self;
}

- (void)configureWithAlbum:(nullable IMAlbum *)album {
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;

	if (!album) {
		self.nameLabel.text = nil;
		self.countLabel.text = nil;
		return;
	}

	self.nameLabel.text = album.name;
	self.countLabel.text = [NSString stringWithFormat:_(@"%ld items"), (long)album.assetCount];

	if (album.thumbnailAssetId.length == 0) {
		if (@available(iOS 13.0, *)) {
			self.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle.angled"];
		}
		return;
	}

	NSString *assetId = album.thumbnailAssetId;
	__weak typeof(self) weakSelf = self;
	self.thumbTask = [[IMThumbCache shared] thumbnailForAssetId:assetId
	                                                         size:[IMPrefs shared].thumbnailQuality
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
	self.countLabel.text = nil;
}

@end
