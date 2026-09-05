#import "IMSearchExploreItem.h"

static id IMExploreValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMSearchExploreItem ()
@property (nonatomic, copy) NSString *value;
@property (nonatomic, strong) IMAsset *asset;
@end

@implementation IMSearchExploreItem

+ (nullable instancetype)itemWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id value = IMExploreValueOrNil(dictionary[@"value"]);
	id data = IMExploreValueOrNil(dictionary[@"data"]);
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0 ||
	    ![data isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	IMAsset *asset = [IMAsset assetWithResponseDictionary:data];
	if (!asset) return nil;
	IMSearchExploreItem *item = [[self alloc] init];
	item.value = [value copy];
	item.asset = asset;
	return item;
}

@end
