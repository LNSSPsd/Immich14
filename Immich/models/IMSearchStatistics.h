#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSearchStatistics : NSObject

@property (nonatomic, readonly) NSInteger total;

+ (nullable instancetype)statisticsWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
