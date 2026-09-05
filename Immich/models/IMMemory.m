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

@end
