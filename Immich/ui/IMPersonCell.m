#import "IMPersonCell.h"
#import "IMSearchApi.h"

NSString *const IMPersonCellReuseIdentifier = @"IMPersonCell";

static NSCache<NSString *, UIImage *> *IMPersonThumbCache(void) {
	static NSCache<NSString *, UIImage *> *cache;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		cache = [[NSCache alloc] init];
		cache.countLimit = 200;
	});
	return cache;
}

@interface IMPersonCell ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong, nullable) NSURLSessionTask *thumbTask;
@property (nonatomic, copy, nullable) NSString *personId;
@end

@implementation IMPersonCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.imageView = [[UIImageView alloc] init];
		self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
		self.imageView.contentMode = UIViewContentModeScaleAspectFill;
		self.imageView.clipsToBounds = YES;
		if (@available(iOS 13.0, *)) {
			self.imageView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
		} else {
			self.imageView.backgroundColor = UIColor.groupTableViewBackgroundColor;
		}
		[self.contentView addSubview:self.imageView];

		self.nameLabel = [[UILabel alloc] init];
		self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
		self.nameLabel.font = [UIFont systemFontOfSize:12];
		self.nameLabel.textAlignment = NSTextAlignmentCenter;
		self.nameLabel.numberOfLines = 1;
		[self.contentView addSubview:self.nameLabel];

		[NSLayoutConstraint activateConstraints:@[
			[self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
			[self.imageView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
			[self.imageView.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor constant:-12],
			[self.imageView.heightAnchor constraintEqualToAnchor:self.imageView.widthAnchor],

			[self.nameLabel.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:4],
			[self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:2],
			[self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-2],
		]];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	self.imageView.layer.cornerRadius = self.imageView.bounds.size.width / 2;
}

- (void)configureWithPerson:(nullable IMPerson *)person {
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;
	self.personId = person.personId;
	self.nameLabel.text = person.name;

	if (!person) {
		return;
	}

	UIImage *cached = [IMPersonThumbCache() objectForKey:person.personId];
	if (cached) {
		self.imageView.image = cached;
		return;
	}

	NSString *personId = person.personId;
	__weak typeof(self) weakSelf = self;
	self.thumbTask = [IMSearchApi thumbnailDataForPersonId:personId
	                                              completion:^(NSData *_Nullable data, NSError *_Nullable error) {
		    if (error || data.length == 0) {
			    return;
		    }
		    UIImage *image = [UIImage imageWithData:data];
		    if (!image) {
			    return;
		    }
		    [IMPersonThumbCache() setObject:image forKey:personId];
		    typeof(self) strongSelf = weakSelf;
		    if (strongSelf && [strongSelf.personId isEqualToString:personId]) {
			    strongSelf.imageView.image = image;
		    }
	    }];
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self.thumbTask cancel];
	self.thumbTask = nil;
	self.imageView.image = nil;
	self.nameLabel.text = nil;
	self.personId = nil;
}

@end
