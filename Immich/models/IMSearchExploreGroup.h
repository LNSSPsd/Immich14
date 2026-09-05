#import <Foundation/Foundation.h>
#import "IMSearchExploreItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSearchExploreGroup : NSObject

@property (nonatomic, copy, readonly) NSString *fieldName;
@property (nonatomic, copy, readonly) NSArray<IMSearchExploreItem *> *items;

+ (nullable instancetype)groupWithResponseDictionary:(NSDictionary *)dictionary;
+ (nullable NSArray<IMSearchExploreGroup *> *)groupsWithResponseArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
