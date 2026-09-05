#import "IMMemoryStatistics.h"
#import <math.h>
#include <string.h>

@interface IMMemoryStatistics ()
@property (nonatomic) NSInteger total;
@end

@implementation IMMemoryStatistics

+ (nullable instancetype)statisticsWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id value = dictionary[@"total"];
	if (![value isKindOfClass:[NSNumber class]]) {
		return nil;
	}
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) {
		return nil;
	}
	double numeric = [(NSNumber *)value doubleValue];
	if (!isfinite(numeric) || floor(numeric) != numeric || numeric < -9007199254740991.0 ||
	    numeric > 9007199254740991.0 || numeric < (double)NSIntegerMin || numeric > (double)NSIntegerMax) {
		return nil;
	}
	IMMemoryStatistics *statistics = [[self alloc] init];
	statistics.total = [(NSNumber *)value integerValue];
	return statistics;
}

@end
