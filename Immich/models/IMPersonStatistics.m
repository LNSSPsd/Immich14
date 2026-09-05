#import "IMPersonStatistics.h"

@interface IMPersonStatistics ()
@property (nonatomic) NSInteger assets;
@end

@implementation IMPersonStatistics

+ (nullable instancetype)statisticsWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id value = dictionary[@"assets"];
	if (![value isKindOfClass:[NSNumber class]]) return nil;
	IMPersonStatistics *statistics = [[self alloc] init];
	statistics.assets = [value integerValue];
	return statistics;
}

@end
