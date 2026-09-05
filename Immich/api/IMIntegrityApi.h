#import <Foundation/Foundation.h>
#import "IMIntegrityReportPage.h"
#import "IMIntegrityReportSummary.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMIntegritySummaryCompletion)(IMIntegrityReportSummary *_Nullable summary,
                                           NSError *_Nullable error);
typedef void (^IMIntegrityReportCompletion)(IMIntegrityReportPage *_Nullable page,
                                         NSError *_Nullable error);
typedef void (^IMIntegrityMutationCompletion)(BOOL success, NSError *_Nullable error);
typedef void (^IMIntegrityFileCompletion)(NSURL *_Nullable fileURL, NSError *_Nullable error);

@interface IMIntegrityApi : NSObject

+ (nullable NSURLSessionTask *)summaryWithCompletion:(IMIntegritySummaryCompletion)completion;
+ (nullable NSURLSessionTask *)integrityReportSummaryWithCompletion:(IMIntegritySummaryCompletion)completion;
+ (nullable NSURLSessionTask *)getIntegrityReportSummaryWithCompletion:(IMIntegritySummaryCompletion)completion;

+ (nullable NSURLSessionTask *)reportForType:(NSString *)type
                                  cursor:(nullable NSString *)cursor
                                   limit:(NSInteger)limit
                              completion:(IMIntegrityReportCompletion)completion;
+ (nullable NSURLSessionTask *)integrityReportForType:(NSString *)type
                                               cursor:(nullable NSString *)cursor
                                                limit:(NSInteger)limit
                                           completion:(IMIntegrityReportCompletion)completion;
+ (nullable NSURLSessionTask *)getIntegrityReportForType:(NSString *)type
                                                  cursor:(nullable NSString *)cursor
                                                   limit:(NSInteger)limit
                                              completion:(IMIntegrityReportCompletion)completion;

+ (nullable NSURLSessionTask *)reportForType:(NSString *)type
                              completion:(IMIntegrityReportCompletion)completion;

+ (nullable NSURLSessionTask *)deleteReportId:(NSString *)reportId
                                    completion:(IMIntegrityMutationCompletion)completion;
+ (nullable NSURLSessionTask *)deleteIntegrityReportId:(NSString *)reportId
                                            completion:(IMIntegrityMutationCompletion)completion;

+ (nullable NSURLSessionTask *)reportCSVForType:(NSString *)type
                                 destinationURL:(NSURL *)destinationURL
                                      completion:(IMIntegrityFileCompletion)completion;
+ (nullable NSURLSessionTask *)integrityReportCSVForType:(NSString *)type
                                          destinationURL:(NSURL *)destinationURL
                                               completion:(IMIntegrityFileCompletion)completion;
+ (nullable NSURLSessionTask *)getIntegrityReportCsvForType:(NSString *)type
                                             destinationURL:(NSURL *)destinationURL
                                                  completion:(IMIntegrityFileCompletion)completion;

+ (nullable NSURLSessionTask *)reportFileForId:(NSString *)reportId
                                 destinationURL:(NSURL *)destinationURL
                                      completion:(IMIntegrityFileCompletion)completion;
+ (nullable NSURLSessionTask *)getIntegrityReportFileId:(NSString *)reportId
                                         destinationURL:(NSURL *)destinationURL
                                              completion:(IMIntegrityFileCompletion)completion;
+ (nullable NSURLSessionTask *)getIntegrityReportFile:(NSString *)reportId
                                        destinationURL:(NSURL *)destinationURL
                                             completion:(IMIntegrityFileCompletion)completion;

@end

NS_ASSUME_NONNULL_END
