#import "IMMemory.h"
#import "common.h"

static id IMMemoryValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMMemory ()
@property (nonatomic, copy) NSString *memoryId;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@property (nonatomic, strong) NSDate *memoryAt;
@property (nonatomic, strong, nullable) NSDate *showAt;
@property (nonatomic, strong, nullable) NSDate *hideAt;
@property (nonatomic, strong, nullable) NSDate *seenAt;
@property (nonatomic, getter=isSaved) BOOL saved;
@property (nonatomic) NSInteger sourceYear;
@end

@implementation IMMemory

+ (nullable instancetype)memoryWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id memoryId = IMMemoryValueOrNil(dictionary[@"id"]);
	id memoryAtString = IMMemoryValueOrNil(dictionary[@"memoryAt"]);
	if (![memoryId isKindOfClass:[NSString class]] || [(NSString *)memoryId length] == 0 ||
	    ![memoryAtString isKindOfClass:[NSString class]]) {
		return nil;
	}
	NSDate *memoryAt = IMDateFromServerTimestamp(memoryAtString);
	if (!memoryAt) {
		return nil;
	}
	IMMemory *memory = [[IMMemory alloc] init];
	memory.memoryId = memoryId;
	id type = IMMemoryValueOrNil(dictionary[@"type"]);
	memory.type = [type isKindOfClass:[NSString class]] ? type : @"on_this_day";
	id assets = IMMemoryValueOrNil(dictionary[@"assets"]);
	memory.assets = [assets isKindOfClass:[NSArray class]] ? [IMAsset assetsWithResponseArray:assets] : @[];
	memory.memoryAt = memoryAt;
	memory.showAt = IMDateFromServerTimestamp(IMMemoryValueOrNil(dictionary[@"showAt"]));
	memory.hideAt = IMDateFromServerTimestamp(IMMemoryValueOrNil(dictionary[@"hideAt"]));
	memory.seenAt = IMDateFromServerTimestamp(IMMemoryValueOrNil(dictionary[@"seenAt"]));
	id saved = IMMemoryValueOrNil(dictionary[@"isSaved"]);
	memory.saved = [saved isKindOfClass:[NSNumber class]] && [saved boolValue];
	id data = IMMemoryValueOrNil(dictionary[@"data"]);
	if ([data isKindOfClass:[NSDictionary class]]) {
		id year = IMMemoryValueOrNil(data[@"year"]);
		memory.sourceYear = [year isKindOfClass:[NSNumber class]] ? [year integerValue] : 0;
	}
	return memory;
}

+ (NSArray<IMMemory *> *)memoriesWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMMemory *> *memories = [NSMutableArray arrayWithCapacity:array.count];
	for (NSDictionary *dictionary in array) {
		IMMemory *memory = [IMMemory memoryWithResponseDictionary:dictionary];
		if (memory) {
			[memories addObject:memory];
		}
	}
	return memories;
}

- (NSString *)displayTitle {
	NSCalendar *calendar = NSCalendar.currentCalendar;
	if (self.sourceYear > 0) {
		NSInteger years = [calendar component:NSCalendarUnitYear fromDate:self.memoryAt] - self.sourceYear;
		if (years == 1) {
			return _(@"1 year ago");
		}
		if (years > 1) {
			return [NSString stringWithFormat:_(@"%ld years ago"), (long)years];
		}
	}
	return self.displaySubtitle;
}

- (NSString *)displaySubtitle {
	static NSDateFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterLongStyle;
		formatter.timeStyle = NSDateFormatterNoStyle;
	});
	NSDate *taken = IMDateFromServerTimestamp(self.assets.firstObject.fileCreatedAt);
	return [formatter stringFromDate:taken ?: self.memoryAt] ?: @"";
}

- (BOOL)isActiveToday {
	NSDate *now = [NSDate date];
	if (self.showAt || self.hideAt) {
		return (!self.showAt || [self.showAt compare:now] != NSOrderedDescending) &&
		       (!self.hideAt || [self.hideAt compare:now] == NSOrderedDescending);
	}
	return [NSCalendar.currentCalendar isDateInToday:self.memoryAt];
}

@end
