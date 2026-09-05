#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMQueueLegacyStatus : NSObject

@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly, getter=isPaused) BOOL paused;

+ (nullable instancetype)statusWithResponseDictionary:(NSDictionary *)dictionary;

@end

@interface IMQueueLegacyJobCounts : NSObject

@property (nonatomic, readonly) NSInteger active;
@property (nonatomic, readonly) NSInteger completed;
@property (nonatomic, readonly) NSInteger delayed;
@property (nonatomic, readonly) NSInteger failed;
@property (nonatomic, readonly) NSInteger waiting;
@property (nonatomic, readonly) NSInteger paused;

+ (nullable instancetype)countsWithResponseDictionary:(NSDictionary *)dictionary;

@end

@interface IMQueueLegacyResponse : NSObject

@property (nonatomic, strong, readonly) IMQueueLegacyStatus *queueStatus;
@property (nonatomic, strong, readonly) IMQueueLegacyJobCounts *jobCounts;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
