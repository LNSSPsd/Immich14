#import "IMSystemConfigStorageTemplateOptions.h"

static NSArray<NSString *> *IMSystemConfigStringArray(id value) {
	if (![value isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
	for (id item in (NSArray *)value) {
		if (![item isKindOfClass:[NSString class]]) return nil;
		[result addObject:[item copy]];
	}
	return [result copy];
}

@interface IMSystemConfigStorageTemplateOptions ()
@property (nonatomic, copy) NSArray<NSString *> *dayOptions;
@property (nonatomic, copy) NSArray<NSString *> *hourOptions;
@property (nonatomic, copy) NSArray<NSString *> *minuteOptions;
@property (nonatomic, copy) NSArray<NSString *> *monthOptions;
@property (nonatomic, copy) NSArray<NSString *> *presetOptions;
@property (nonatomic, copy) NSArray<NSString *> *secondOptions;
@property (nonatomic, copy) NSArray<NSString *> *weekOptions;
@property (nonatomic, copy) NSArray<NSString *> *yearOptions;
@end

@implementation IMSystemConfigStorageTemplateOptions

+ (nullable instancetype)optionsWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    ![NSJSONSerialization isValidJSONObject:dictionary]) return nil;
	NSArray<NSString *> *day = IMSystemConfigStringArray(dictionary[@"dayOptions"]);
	NSArray<NSString *> *hour = IMSystemConfigStringArray(dictionary[@"hourOptions"]);
	NSArray<NSString *> *minute = IMSystemConfigStringArray(dictionary[@"minuteOptions"]);
	NSArray<NSString *> *month = IMSystemConfigStringArray(dictionary[@"monthOptions"]);
	NSArray<NSString *> *preset = IMSystemConfigStringArray(dictionary[@"presetOptions"]);
	NSArray<NSString *> *second = IMSystemConfigStringArray(dictionary[@"secondOptions"]);
	NSArray<NSString *> *week = IMSystemConfigStringArray(dictionary[@"weekOptions"]);
	NSArray<NSString *> *year = IMSystemConfigStringArray(dictionary[@"yearOptions"]);
	if (!day || !hour || !minute || !month || !preset || !second || !week || !year) return nil;
	IMSystemConfigStorageTemplateOptions *result = [[self alloc] init];
	result.dayOptions = day;
	result.hourOptions = hour;
	result.minuteOptions = minute;
	result.monthOptions = month;
	result.presetOptions = preset;
	result.secondOptions = second;
	result.weekOptions = week;
	result.yearOptions = year;
	return result;
}

@end
