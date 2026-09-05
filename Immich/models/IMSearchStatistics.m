#import "IMSearchStatistics.h"
#import <math.h>

@interface IMSearchStatistics ()
@property (nonatomic) NSInteger total;
@end

@implementation IMSearchStatistics

+ (nullable instancetype)statisticsWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id value = dictionary[@"total"];
	if (![value isKindOfClass:[NSNumber class]]) {
		return nil;
	}
	double total = [value doubleValue];
	if (!isfinite(total) || floor(total) != total || total < 0.0) {
		return nil;
	}
	IMSearchStatistics *statistics = [[self alloc] init];
	statistics.total = [value integerValue];
	return statistics;
}

@end
