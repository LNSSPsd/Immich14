#import "IMServerStorage.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMServerStorage ()
@property (nonatomic, copy) NSString *diskUse;
@property (nonatomic, copy) NSString *diskSize;
@property (nonatomic) double diskUsagePercentage;
@end

@implementation IMServerStorage

+ (nullable instancetype)storageWithDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	IMServerStorage *storage = [[IMServerStorage alloc] init];
	NSString *diskUse = IMValueOrNil(dict[@"diskUse"]);
	storage.diskUse = [diskUse isKindOfClass:[NSString class]] ? diskUse : @"";
	NSString *diskSize = IMValueOrNil(dict[@"diskSize"]);
	storage.diskSize = [diskSize isKindOfClass:[NSString class]] ? diskSize : @"";
	id percentage = IMValueOrNil(dict[@"diskUsagePercentage"]);
	storage.diskUsagePercentage = [percentage isKindOfClass:[NSNumber class]] ? [percentage doubleValue] : 0;
	return storage;
}

@end
