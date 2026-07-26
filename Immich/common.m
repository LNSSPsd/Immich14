#import "common.h"

NSNotificationName const IMServerAssetsDidChangeNotification = @"IMServerAssetsDidChangeNotification";
NSString *const IMChangedTimeBucketsUserInfoKey = @"changedTimeBuckets";

NSDate *IMDateFromServerTimestamp(NSString *raw) {
	if (raw.length == 0) {
		return nil;
	}

	static NSISO8601DateFormatter *isoWithFraction;
	static NSISO8601DateFormatter *isoPlain;
	static NSDateFormatter *noZoneWithMillis;
	static NSDateFormatter *noZone;
	static NSDateFormatter *spaceWithMillis;
	static NSDateFormatter *space;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		isoWithFraction = [[NSISO8601DateFormatter alloc] init];
		isoWithFraction.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;

		isoPlain = [[NSISO8601DateFormatter alloc] init]; 

		NSLocale *posix = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		NSTimeZone *utc = [NSTimeZone timeZoneForSecondsFromGMT:0];

		noZoneWithMillis = [[NSDateFormatter alloc] init];
		noZoneWithMillis.locale = posix;
		noZoneWithMillis.timeZone = utc;
		noZoneWithMillis.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS";

		noZone = [[NSDateFormatter alloc] init];
		noZone.locale = posix;
		noZone.timeZone = utc;
		noZone.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";

		spaceWithMillis = [[NSDateFormatter alloc] init];
		spaceWithMillis.locale = posix;
		spaceWithMillis.timeZone = utc;
		spaceWithMillis.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";

		space = [[NSDateFormatter alloc] init];
		space.locale = posix;
		space.timeZone = utc;
		space.dateFormat = @"yyyy-MM-dd HH:mm:ss";
	});

	NSDate *date = [isoWithFraction dateFromString:raw];
	if (date) {
		return date;
	}
	date = [isoPlain dateFromString:raw];
	if (date) {
		return date;
	}
	date = [noZoneWithMillis dateFromString:raw];
	if (date) {
		return date;
	}
	date = [noZone dateFromString:raw];
	if (date) {
		return date;
	}
	date = [spaceWithMillis dateFromString:raw];
	if (date) {
		return date;
	}
	return [space dateFromString:raw];
}

NSString *IMTimeBucketKeyForDate(NSDate *date) {
	if (!date) {
		return nil;
	}
	static NSDateFormatter *formatter;
	static NSCalendar *calendar;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
		calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateFormat = @"yyyy-MM-dd";
		formatter.timeZone = calendar.timeZone;
	});
	NSDateComponents *comps = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:date];
	comps.day = 1;
	return [formatter stringFromDate:[calendar dateFromComponents:comps]];
}

NSInteger IMDurationMsFromJSONValue(id value) {
	if ([value isKindOfClass:[NSNumber class]]) {
		return [value integerValue];
	}
	if (![value isKindOfClass:[NSString class]]) {
		return 0;
	}
	NSArray<NSString *> *parts = [(NSString *)value componentsSeparatedByString:@":"];
	if (parts.count != 3) {
		return 0;
	}
	NSInteger hours = [parts[0] integerValue];
	NSInteger minutes = [parts[1] integerValue];
	double seconds = [parts[2] doubleValue];
	if (hours == 0 && minutes == 0 && seconds == 0) {
		return 0;
	}
	return (NSInteger)llround(((hours * 60.0 + minutes) * 60.0 + seconds) * 1000.0);
}
