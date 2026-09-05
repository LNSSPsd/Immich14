#import "IMAlbumStatistics.h"
#import <math.h>
#include <string.h>

static BOOL IMAlbumStatisticsInteger(id value, NSInteger *outValue) {
	if (![value isKindOfClass:[NSNumber class]]) {
		return NO;
	}
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) {
		return NO;
	}
	double numeric = [(NSNumber *)value doubleValue];
	if (!isfinite(numeric) || floor(numeric) != numeric || numeric < 0.0 ||
	    numeric > 9007199254740991.0 || numeric > (double)NSIntegerMax) {
		return NO;
	}
	if (outValue) {
		*outValue = [(NSNumber *)value integerValue];
	}
	return YES;
}

@interface IMAlbumStatistics ()
@property (nonatomic) NSInteger notShared;
@property (nonatomic) NSInteger owned;
@property (nonatomic) NSInteger shared;
@end

@implementation IMAlbumStatistics

+ (nullable instancetype)statisticsWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSInteger notShared = 0, owned = 0, shared = 0;
	if (!IMAlbumStatisticsInteger(dictionary[@"notShared"], &notShared) ||
	    !IMAlbumStatisticsInteger(dictionary[@"owned"], &owned) ||
	    !IMAlbumStatisticsInteger(dictionary[@"shared"], &shared)) {
		return nil;
	}
	IMAlbumStatistics *statistics = [[self alloc] init];
	statistics.notShared = notShared;
	statistics.owned = owned;
	statistics.shared = shared;
	return statistics;
}

@end
