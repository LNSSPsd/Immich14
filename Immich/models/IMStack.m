#import "IMStack.h"

@interface IMStack ()
@property (nonatomic, copy) NSString *stackId;
@property (nonatomic, copy) NSString *primaryAssetId;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@end

@implementation IMStack

+ (nullable instancetype)stackWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id stackId = dictionary[@"id"];
	id primary = dictionary[@"primaryAssetId"];
	if (![stackId isKindOfClass:[NSString class]] || ![primary isKindOfClass:[NSString class]]) return nil;
	id rawAssets = dictionary[@"assets"];
	NSArray *assets = [rawAssets isKindOfClass:[NSArray class]] ? rawAssets : @[];
	IMStack *stack = [[self alloc] init];
	stack.stackId = stackId;
	stack.primaryAssetId = primary;
	stack.assets = [IMAsset assetsWithResponseArray:assets];
	return stack;
}

@end
