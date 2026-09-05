#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPersonStatistics : NSObject
@property (nonatomic, readonly) NSInteger assets;
+ (nullable instancetype)statisticsWithResponseDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
