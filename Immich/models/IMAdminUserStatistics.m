#import "IMAdminUserStatistics.h"
#import <math.h>
#include <string.h>

static BOOL IMAdminUserStatisticsInteger(id value, NSInteger *outValue) {
	if (![value isKindOfClass:[NSNumber class]]) {
		return NO;
	}
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) {
		return NO;
	}
	double numeric = [(NSNumber *)value doubleValue];
	if (!isfinite(numeric) || floor(numeric) != numeric || numeric < -9007199254740991.0 ||
	    numeric > 9007199254740991.0 || numeric < (double)NSIntegerMin || numeric > (double)NSIntegerMax) {
		return NO;
	}
	if (outValue) *outValue = [(NSNumber *)value integerValue];
	return YES;
}

@interface IMAdminUserStatistics ()
@property (nonatomic) NSInteger images;
@property (nonatomic) NSInteger videos;
@property (nonatomic) NSInteger total;
@end

@implementation IMAdminUserStatistics

+ (nullable instancetype)statisticsWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSInteger images = 0, videos = 0, total = 0;
	if (!IMAdminUserStatisticsInteger(dictionary[@"images"], &images) ||
	    !IMAdminUserStatisticsInteger(dictionary[@"videos"], &videos) ||
	    !IMAdminUserStatisticsInteger(dictionary[@"total"], &total)) {
		return nil;
	}
	IMAdminUserStatistics *statistics = [[self alloc] init];
	statistics.images = images;
	statistics.videos = videos;
	statistics.total = total;
	return statistics;
}

@end
