#import <Foundation/Foundation.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const IMSyncStateDidChangeNotification;

typedef NS_ENUM(NSInteger, IMSyncState) {
	IMSyncStateUnknown = 0,
	IMSyncStateLocalOnly = 1,  
	IMSyncStateUploading = 2,  
	IMSyncStateSynced = 3,     
};

@interface IMDatabase : NSObject

+ (instancetype)shared;

- (void)replaceBucketDates:(NSArray<NSString *> *)dates counts:(NSArray<NSNumber *> *)counts;

- (void)cachedBucketDates:(NSArray<NSString *> *_Nonnull *_Nonnull)outDates
                    counts:(NSArray<NSNumber *> *_Nonnull *_Nonnull)outCounts;

- (void)replaceAssets:(NSArray<IMAsset *> *)assets forTimeBucket:(NSString *)timeBucket;

- (NSArray<IMAsset *> *)cachedAssetsForTimeBucket:(NSString *)timeBucket;

#pragma mark - Sync state (Phase 7)

- (void)setSyncState:(IMSyncState)state
              assetId:(nullable NSString *)assetId
    forDeviceAssetId:(NSString *)deviceAssetId;

- (IMSyncState)syncStateForDeviceAssetId:(NSString *)deviceAssetId;

- (void)syncStateCountsLocalOnly:(NSInteger *)outLocalOnly synced:(NSInteger *)outSynced;

- (NSArray<NSString *> *)deviceAssetIdsWithState:(IMSyncState)state;

- (NSDictionary<NSString *, NSNumber *> *)allDeviceAssetSyncStates;

@end

NS_ASSUME_NONNULL_END
