#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMBackupQueue : NSObject

+ (instancetype)shared;

- (void)reloadFromPersistence;

- (void)pruneDeviceAssetIdsNotInSet:(nullable NSSet<NSString *> *)deviceAssetIds;

@property (nonatomic, readonly) NSUInteger pendingCount;

@property (nonatomic, readonly, nullable) NSDate *nextAttemptDate;

@property (nonatomic, readonly) NSInteger consecutiveRunFailures;
@property (nonatomic, readonly, nullable) NSDate *nextRunDate;

- (void)enqueueDeviceAssetId:(NSString *)deviceAssetId;
- (void)enqueueDeviceAssetIds:(NSArray<NSString *> *)deviceAssetIds;

- (void)markSucceededDeviceAssetId:(NSString *)deviceAssetId;
- (void)markSucceededDeviceAssetIds:(NSArray<NSString *> *)deviceAssetIds;

- (NSDate *_Nullable)nextAttemptDateForDeviceAssetId:(NSString *)deviceAssetId;

- (void)recordFailureForDeviceAssetId:(NSString *)deviceAssetId
                                error:(nullable NSError *)error;

- (NSArray<NSString *> *)readyDeviceAssetIdsAtDate:(nullable NSDate *)date
                                             limit:(NSUInteger)limit;

- (void)recordRunFailure:(nullable NSError *)error;
- (void)recordRunSuccess;

- (void)setNextRunDate:(nullable NSDate *)date;

- (void)reset;

@end

NS_ASSUME_NONNULL_END
