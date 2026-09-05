#import "IMMemoryCell.h"
#import "IMThumbCache.h"
#import "IMPrefs.h"
#import "common.h"

NSString *const IMMemoryCellReuseIdentifier = @"IMMemoryCell";

@interface IMMemoryCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *scrim;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *savedImageView;
@property (nonatomic, strong, nullable) IMThumbCacheTask *thumbTask;
@end

@implementation IMMemoryCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.contentView.layer.cornerRadius = 14.0;
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
		self.scrim.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.42];
		[self.contentView addSubview:self.scrim];

		self.titleLabel = [[UILabel alloc] init];
		self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
		self.titleLabel.textColor = UIColor.whiteColor;
		self.titleLabel.numberOfLines = 1;
		[self.contentView addSubview:self.titleLabel];

		self.subtitleLabel = [[UILabel alloc] init];
		self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.subtitleLabel.font = [UIFont systemFontOfSize:12];
		self.subtitleLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.9];
		self.subtitleLabel.numberOfLines = 1;
		[self.contentView addSubview:self.subtitleLabel];

		self.savedImageView = [[UIImageView alloc] init];
		self.savedImageView.translatesAutoresizingMaskIntoConstraints = NO;
		self.savedImageView.tintColor = UIColor.whiteColor;
		[self.contentView addSubview:self.savedImageView];

		[NSLayoutConstraint activateConstraints:@[
			[self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.imageView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
			[self.scrim.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
			[self.scrim.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
			[self.scrim.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
			[self.scrim.heightAnchor constraintEqualToConstant:62],
			[self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
			[self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.savedImageView.leadingAnchor constant:-8],
			[self.titleLabel.bottomAnchor constraintEqualToAnchor:self.subtitleLabel.topAnchor constant:-1],
			[self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
			[self.subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-10],
			[self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
			[self.savedImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
			[self.savedImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
			[self.savedImageView.widthAnchor constraintEqualToConstant:18],
			[self.savedImageView.heightAnchor constraintEqualToConstant:18],
		]];
	}
	return self;
}

- (void)configureWithMemory:(nullable IMMemory *)memory {
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;
	self.titleLabel.text = nil;
	self.subtitleLabel.text = nil;
	self.savedImageView.image = nil;
	if (!memory) {
		return;
	}
	static NSDateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterLongStyle;
		formatter.timeStyle = NSDateFormatterNoStyle;
	});
	self.titleLabel.text = [formatter stringFromDate:memory.memoryAt];
	NSString *typeName = [memory.type isEqualToString:@"on_this_day"] ? _(@"On this day") : memory.type;
	self.subtitleLabel.text = [NSString stringWithFormat:_(@"%@ · %lu photos"), typeName, (unsigned long)memory.assets.count];
	if (@available(iOS 13.0, *)) {
		self.savedImageView.image = [UIImage systemImageNamed:memory.isSaved ? @"bookmark.fill" : @"bookmark"];
	}
	IMAsset *asset = memory.assets.firstObject;
	if (!asset) {
		return;
	}
	NSString *assetId = asset.assetId;
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
	self.titleLabel.text = nil;
	self.subtitleLabel.text = nil;
	self.savedImageView.image = nil;
}

@end
