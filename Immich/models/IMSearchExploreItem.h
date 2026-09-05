#import <Foundation/Foundation.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSearchExploreItem : NSObject

@property (nonatomic, copy, readonly) NSString *value;
@property (nonatomic, strong, readonly) IMAsset *asset;

+ (nullable instancetype)itemWithResponseDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
