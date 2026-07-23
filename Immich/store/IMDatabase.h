#import <Foundation/Foundation.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMDatabase : NSObject

+ (instancetype)shared;

- (void)replaceBucketDates:(NSArray<NSString *> *)dates counts:(NSArray<NSNumber *> *)counts;

- (void)cachedBucketDates:(NSArray<NSString *> *_Nonnull *_Nonnull)outDates
                    counts:(NSArray<NSNumber *> *_Nonnull *_Nonnull)outCounts;

- (void)replaceAssets:(NSArray<IMAsset *> *)assets forTimeBucket:(NSString *)timeBucket;

- (NSArray<IMAsset *> *)cachedAssetsForTimeBucket:(NSString *)timeBucket;

@end

NS_ASSUME_NONNULL_END
