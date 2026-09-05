#import <Foundation/Foundation.h>
#import "IMDuplicate.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMDuplicatesCompletion)(NSArray<IMDuplicate *> *_Nullable duplicates, NSError *_Nullable error);
typedef void (^IMDuplicateMutationCompletion)(BOOL success, NSError *_Nullable error);

@interface IMDuplicateApi : NSObject

+ (nullable NSURLSessionTask *)duplicatesWithCompletion:(IMDuplicatesCompletion)completion;
+ (nullable NSURLSessionTask *)getAssetDuplicatesWithCompletion:(IMDuplicatesCompletion)completion;

+ (nullable NSURLSessionTask *)dismissDuplicateId:(NSString *)duplicateId
                                       completion:(IMDuplicateMutationCompletion)completion;
+ (nullable NSURLSessionTask *)deleteDuplicateId:(NSString *)duplicateId
                                      completion:(IMDuplicateMutationCompletion)completion;

+ (nullable NSURLSessionTask *)dismissDuplicateIds:(NSArray<NSString *> *)duplicateIds
                                        completion:(IMDuplicateMutationCompletion)completion;
+ (nullable NSURLSessionTask *)deleteDuplicates:(NSArray<NSString *> *)duplicateIds
                                       completion:(IMDuplicateMutationCompletion)completion;

+ (nullable NSURLSessionTask *)resolveDuplicateId:(NSString *)duplicateId
                                      keepAssetIds:(NSArray<NSString *> *)keepAssetIds
                                     trashAssetIds:(NSArray<NSString *> *)trashAssetIds
                                        completion:(IMDuplicateMutationCompletion)completion;

+ (nullable NSURLSessionTask *)resolveDuplicateGroups:(NSArray<NSDictionary *> *)groups
                                            completion:(IMDuplicateMutationCompletion)completion;
+ (nullable NSURLSessionTask *)resolveDuplicates:(NSArray<NSDictionary *> *)groups
                                      completion:(IMDuplicateMutationCompletion)completion;

@end

NS_ASSUME_NONNULL_END
