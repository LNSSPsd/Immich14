#import <Foundation/Foundation.h>
#import "IMPersonProfile.h"
#import "IMPersonStatistics.h"
#import "IMPersonMutationResult.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMPersonProfileCompletion)(IMPersonProfile *_Nullable person, NSError *_Nullable error);
typedef void (^IMPersonStatisticsCompletion)(IMPersonStatistics *_Nullable statistics, NSError *_Nullable error);
typedef void (^IMPersonMutationResultsCompletion)(NSArray<IMPersonMutationResult *> *_Nullable results,
                                                  NSError *_Nullable error);
typedef void (^IMPeopleProfilesCompletion)(NSArray<IMPersonProfile *> *_Nullable people, NSError *_Nullable error);

@interface IMPeopleApi : NSObject

+ (nullable NSURLSessionTask *)personWithId:(NSString *)personId completion:(IMPersonProfileCompletion)completion;

+ (nullable NSURLSessionTask *)statisticsForPersonId:(NSString *)personId
                                         completion:(IMPersonStatisticsCompletion)completion;

+ (nullable NSURLSessionTask *)updatePersonId:(NSString *)personId
                                          name:(nullable NSString *)name
                                     birthDate:(nullable NSString *)birthDate
                                       hidden:(nullable NSNumber *)hidden
                                     favorite:(nullable NSNumber *)favorite
                                        color:(nullable NSString *)color
                             featureFaceAssetId:(nullable NSString *)featureFaceAssetId
                                    completion:(IMPersonProfileCompletion)completion;

+ (nullable NSURLSessionTask *)mergePersonId:(NSString *)personId
                              withPersonIds:(NSArray<NSString *> *)personIds
                                  completion:(IMPersonMutationResultsCompletion)completion;

+ (nullable NSURLSessionTask *)reassignFacesToPersonId:(NSString *)personId
                                                  data:(NSArray<NSDictionary *> *)data
                                            completion:(IMPeopleProfilesCompletion)completion;

+ (nullable NSURLSessionTask *)deletePersonId:(NSString *)personId
                                    completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)deletePersonIds:(NSArray<NSString *> *)personIds
                                      completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
