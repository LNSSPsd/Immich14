#import "IMServerStats.h"

@interface IMServerUsageByUser ()
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *userName;
@property (nonatomic) NSInteger photos;
@property (nonatomic) NSInteger videos;
@property (nonatomic) unsigned long long usage;
@property (nonatomic) unsigned long long usagePhotos;
@property (nonatomic) unsigned long long usageVideos;
@property (nonatomic) unsigned long long quotaSizeInBytes;
@property (nonatomic) BOOL hasQuota;
@end

@implementation IMServerUsageByUser
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		_userId = [dictionary[@"userId"] isKindOfClass:[NSString class]] ? [dictionary[@"userId"] copy] : @"";
		_userName = [dictionary[@"userName"] isKindOfClass:[NSString class]] ? [dictionary[@"userName"] copy] : @"";
		_photos = [dictionary[@"photos"] integerValue];
		_videos = [dictionary[@"videos"] integerValue];
		_usage = [dictionary[@"usage"] unsignedLongLongValue];
		_usagePhotos = [dictionary[@"usagePhotos"] unsignedLongLongValue];
		_usageVideos = [dictionary[@"usageVideos"] unsignedLongLongValue];
		id quota = dictionary[@"quotaSizeInBytes"];
		_hasQuota = [quota isKindOfClass:[NSNumber class]] && [quota unsignedLongLongValue] > 0;
		_quotaSizeInBytes = _hasQuota ? [quota unsignedLongLongValue] : 0;
	}
	return self;
}
@end

@interface IMServerStats ()
@property (nonatomic) NSInteger photos;
@property (nonatomic) NSInteger videos;
@property (nonatomic) unsigned long long usage;
@property (nonatomic) unsigned long long usagePhotos;
@property (nonatomic) unsigned long long usageVideos;
@property (nonatomic, copy) NSArray<IMServerUsageByUser *> *usageByUser;
@end

@implementation IMServerStats
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		_photos = [dictionary[@"photos"] integerValue];
		_videos = [dictionary[@"videos"] integerValue];
		_usage = [dictionary[@"usage"] unsignedLongLongValue];
		_usagePhotos = [dictionary[@"usagePhotos"] unsignedLongLongValue];
		_usageVideos = [dictionary[@"usageVideos"] unsignedLongLongValue];
		NSMutableArray *users = [NSMutableArray array];
		for (id value in [dictionary[@"usageByUser"] isKindOfClass:[NSArray class]] ? dictionary[@"usageByUser"] : @[]) {
			if ([value isKindOfClass:[NSDictionary class]]) [users addObject:[[IMServerUsageByUser alloc] initWithDictionary:value]];
		}
		_usageByUser = users.copy;
	}
	return self;
}
@end
