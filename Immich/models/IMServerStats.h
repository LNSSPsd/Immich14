#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMServerUsageByUser : NSObject
@property (nonatomic, copy, readonly) NSString *userId;
@property (nonatomic, copy, readonly) NSString *userName;
@property (nonatomic, readonly) NSInteger photos;
@property (nonatomic, readonly) NSInteger videos;
@property (nonatomic, readonly) unsigned long long usage;
@property (nonatomic, readonly) unsigned long long usagePhotos;
@property (nonatomic, readonly) unsigned long long usageVideos;
@property (nonatomic, readonly) unsigned long long quotaSizeInBytes;
@property (nonatomic, readonly) BOOL hasQuota;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMServerStats : NSObject
@property (nonatomic, readonly) NSInteger photos;
@property (nonatomic, readonly) NSInteger videos;
@property (nonatomic, readonly) unsigned long long usage;
@property (nonatomic, readonly) unsigned long long usagePhotos;
@property (nonatomic, readonly) unsigned long long usageVideos;
@property (nonatomic, copy, readonly) NSArray<IMServerUsageByUser *> *usageByUser;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
