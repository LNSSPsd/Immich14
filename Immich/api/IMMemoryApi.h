#import <Foundation/Foundation.h>
#import "IMMemory.h"
#import "IMMemoryStatistics.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMMemoryApi : NSObject

+ (void)allMemoriesWithCompletion:(void (^)(NSArray<IMMemory *> *_Nullable memories,
                                             NSError *_Nullable error))completion;

+ (void)statisticsWithCompletion:(void (^)(IMMemoryStatistics *_Nullable statistics,
                                            NSError *_Nullable error))completion;

+ (void)memoryWithId:(NSString *)memoryId
          completion:(void (^)(IMMemory *_Nullable memory, NSError *_Nullable error))completion;

+ (void)createMemoryWithType:(NSString *)type
                     dataYear:(NSInteger)dataYear
                    memoryAt:(NSString *)memoryAt
                    assetIds:(nullable NSArray<NSString *> *)assetIds
                    isSaved:(nullable NSNumber *)isSaved
                     seenAt:(nullable NSString *)seenAt
                      showAt:(nullable NSString *)showAt
                      hideAt:(nullable NSString *)hideAt
                  completion:(void (^)(IMMemory *_Nullable memory, NSError *_Nullable error))completion;

+ (void)updateMemoryId:(NSString *)memoryId
               isSaved:(BOOL)isSaved
            completion:(void (^)(IMMemory *_Nullable memory, NSError *_Nullable error))completion;

+ (void)updateMemoryId:(NSString *)memoryId
                fields:(NSDictionary<NSString *, id> *)fields
            completion:(void (^)(IMMemory *_Nullable memory, NSError *_Nullable error))completion;

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
        toMemoryId:(NSString *)memoryId
         completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)removeAssetIds:(NSArray<NSString *> *)assetIds
           fromMemoryId:(NSString *)memoryId
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)deleteMemoryId:(NSString *)memoryId
            completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
