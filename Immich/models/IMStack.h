#import <Foundation/Foundation.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMStack : NSObject
@property (nonatomic, copy, readonly) NSString *stackId;
@property (nonatomic, copy, readonly) NSString *primaryAssetId;
@property (nonatomic, copy, readonly) NSArray<IMAsset *> *assets;

+ (nullable instancetype)stackWithResponseDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
