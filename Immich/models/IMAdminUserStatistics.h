#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAdminUserStatistics : NSObject

@property (nonatomic, readonly) NSInteger images;
@property (nonatomic, readonly) NSInteger videos;
@property (nonatomic, readonly) NSInteger total;

+ (nullable instancetype)statisticsWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
