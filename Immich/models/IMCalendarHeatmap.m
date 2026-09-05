#import "IMCalendarHeatmap.h"
#import <math.h>
#include <string.h>

static BOOL IMCalendarHeatmapDateString(id value) {
	if (![value isKindOfClass:[NSString class]]) return NO;
	NSString *date = (NSString *)value;
	if (date.length != 10) return NO;
	static NSRegularExpression *regex;
	static NSDateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$" options:0 error:nil];
		formatter = [[NSDateFormatter alloc] init];
		formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
		formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		formatter.dateFormat = @"yyyy-MM-dd";
		formatter.lenient = NO;
	});
	if ([regex firstMatchInString:date options:0 range:NSMakeRange(0, date.length)] == nil) return NO;
	NSDate *parsed = [formatter dateFromString:date];
	return parsed != nil && [[formatter stringFromDate:parsed] isEqualToString:date];
}

static BOOL IMCalendarHeatmapCount(id value, NSInteger *outValue) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) return NO;
	double numeric = [(NSNumber *)value doubleValue];
	if (!isfinite(numeric) || floor(numeric) != numeric || numeric < 0.0 ||
	    numeric > 9007199254740991.0 || numeric > (double)NSIntegerMax) return NO;
	if (outValue) *outValue = [(NSNumber *)value integerValue];
	return YES;
}

@interface IMCalendarHeatmapEntry ()
@property (nonatomic, copy, readwrite) NSString *date;
@property (nonatomic, readwrite) NSInteger count;
@end

@implementation IMCalendarHeatmapEntry

+ (nullable instancetype)entryWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id date = dictionary[@"date"];
	NSInteger count = 0;
	if (!IMCalendarHeatmapDateString(date) || !IMCalendarHeatmapCount(dictionary[@"count"], &count)) return nil;
	IMCalendarHeatmapEntry *entry = [[self alloc] init];
	entry.date = date;
	entry.count = count;
	return entry;
}

@end

@interface IMCalendarHeatmap ()
@property (nonatomic, copy, readwrite) NSString *fromDate;
@property (nonatomic, copy, readwrite) NSString *toDate;
@property (nonatomic, copy, readwrite) NSArray<IMCalendarHeatmapEntry *> *series;
@property (nonatomic, readwrite) NSInteger totalCount;
@end

@implementation IMCalendarHeatmap

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id from = dictionary[@"from"];
	id to = dictionary[@"to"];
	NSInteger total = 0;
	if (!IMCalendarHeatmapDateString(from) || !IMCalendarHeatmapDateString(to) ||
	    !IMCalendarHeatmapCount(dictionary[@"totalCount"], &total)) return nil;
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	formatter.dateFormat = @"yyyy-MM-dd";
	formatter.lenient = NO;
	NSDate *fromDate = [formatter dateFromString:from];
	NSDate *toDate = [formatter dateFromString:to];
	if (!fromDate || !toDate || [fromDate compare:toDate] == NSOrderedDescending) return nil;
	id rawSeries = dictionary[@"series"];
	if (![rawSeries isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray<IMCalendarHeatmapEntry *> *series = [NSMutableArray arrayWithCapacity:[rawSeries count]];
	for (id rawEntry in (NSArray *)rawSeries) {
		IMCalendarHeatmapEntry *entry = [IMCalendarHeatmapEntry entryWithDictionary:rawEntry];
		if (!entry) return nil;
		[series addObject:entry];
	}
	IMCalendarHeatmap *response = [[self alloc] init];
	response.fromDate = from;
	response.toDate = to;
	response.series = series;
	response.totalCount = total;
	return response;
}

@end
