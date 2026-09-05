#import <Foundation/Foundation.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMDuplicate : NSObject

@property (nonatomic, copy, readonly) NSString *duplicateId;
@property (nonatomic, copy, readonly) NSArray<IMAsset *> *assets;
@property (nonatomic, copy, readonly) NSArray<NSString *> *suggestedKeepAssetIds;

+ (nullable instancetype)duplicateWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMDuplicate *> *)duplicatesWithResponseArray:(NSArray *)array;

- (NSArray<NSString *> *)assetIdsToKeep;
- (NSArray<NSString *> *)assetIdsToTrash;

@end

NS_ASSUME_NONNULL_END
