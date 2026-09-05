#import <Foundation/Foundation.h>
#import "IMQueue.h"
#import "IMQueueCommandRequest.h"
#import "IMQueueLegacyResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMQueueApi : NSObject
+ (void)allQueuesWithCompletion:(void (^)(NSArray<IMQueue *> *_Nullable queues, NSError *_Nullable error))completion;
+ (void)setQueueNamed:(NSString *)name paused:(BOOL)paused completion:(void (^)(IMQueue *_Nullable queue, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)runQueueCommandLegacyNamed:(NSString *)name
                                                  request:(IMQueueCommandRequest *)request
                                              completion:(void (^)(IMQueueLegacyResponse *_Nullable response,
                                                                   NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)runQueueCommandLegacyNamed:(NSString *)name
                                                  command:(NSString *)command
                                                    force:(nullable NSNumber *)force
                                              completion:(void (^)(IMQueueLegacyResponse *_Nullable response,
                                                                   NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)runQueueCommandLegacyNamed:(NSString *)name
                                                  command:(NSString *)command
                                              completion:(void (^)(IMQueueLegacyResponse *_Nullable response,
                                                                   NSError *_Nullable error))completion;

+ (void)runManualJobNamed:(NSString *)name completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)emptyQueueNamed:(NSString *)name includeFailed:(BOOL)includeFailed completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
