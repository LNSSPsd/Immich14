#import "IMIntegrityApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMIntegrityError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:0
	                        userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSError *IMIntegrityInputError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The integrity request is invalid.") }];
}

static NSError *IMIntegrityMalformedSummary(void) {
	return IMIntegrityError(_(@"The server returned an invalid integrity summary."));
}

static NSError *IMIntegrityMalformedReport(void) {
	return IMIntegrityError(_(@"The server returned an invalid integrity report."));
}

static NSError *IMIntegrityMalformedMutation(void) {
	return IMIntegrityError(_(@"The server returned an invalid integrity mutation response."));
}

static NSError *IMIntegrityMalformedFile(void) {
	return IMIntegrityError(_(@"The server returned an invalid integrity file."));
}

static void IMIntegrityAsyncReportFailure(IMIntegrityReportCompletion completion, NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(nil, error);
	});
}

static void IMIntegrityAsyncMutationFailure(IMIntegrityMutationCompletion completion, NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(NO, error);
	});
}

static void IMIntegrityAsyncFileFailure(IMIntegrityFileCompletion completion, NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(nil, error);
	});
}

static BOOL IMIntegrityUUIDv7IsValid(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) {
		return NO;
	}
	NSString *raw = (NSString *)value;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:raw];
	if (!uuid || ![raw.lowercaseString isEqualToString:uuid.UUIDString.lowercaseString]) {
		return NO;
	}
	NSString *canonical = raw.lowercaseString;
	unichar version = [canonical characterAtIndex:14];
	unichar variant = [canonical characterAtIndex:19];
	BOOL validVariant = variant == '8' || variant == '9' || variant == 'a' || variant == 'b';
	return version == '7' && validVariant;
}

static NSString *IMIntegrityPathComponent(NSString *value) {
	NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
	[allowed addCharactersInString:@"-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

@implementation IMIntegrityApi

+ (nullable NSURLSessionTask *)summaryWithCompletion:(IMIntegritySummaryCompletion)completion {
	return [[IMApiClient shared] GET:@"/admin/integrity/summary"
                             query:nil
                        completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMIntegrityReportSummary *summary = [IMIntegrityReportSummary summaryWithResponseDictionary:json];
		completion(summary, summary ? nil : IMIntegrityMalformedSummary());
	}];
}

+ (nullable NSURLSessionTask *)integrityReportSummaryWithCompletion:(IMIntegritySummaryCompletion)completion {
	return [self summaryWithCompletion:completion];
}

+ (nullable NSURLSessionTask *)getIntegrityReportSummaryWithCompletion:(IMIntegritySummaryCompletion)completion {
	return [self summaryWithCompletion:completion];
}

+ (nullable NSURLSessionTask *)reportForType:(NSString *)type
                                  cursor:(nullable NSString *)cursor
                                   limit:(NSInteger)limit
                              completion:(IMIntegrityReportCompletion)completion {
	if (!IMIntegrityReportTypeIsKnown(type)) {
		IMIntegrityAsyncReportFailure(completion, IMIntegrityError(_(@"Choose a valid integrity report type.")));
		return nil;
	}
	NSInteger pageLimit = limit > 0 ? MIN(limit, (NSInteger)500) : 100;
	NSMutableDictionary<NSString *, NSString *> *query = [@{
		@"type": type,
		@"limit": [NSString stringWithFormat:@"%ld", (long)pageLimit],
	} mutableCopy];
	if ([cursor isKindOfClass:[NSString class]] && cursor.length > 0) {
		query[@"cursor"] = cursor;
	}
	return [[IMApiClient shared] GET:@"/admin/integrity/report"
                             query:query
                        completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMIntegrityReportPage *page = [IMIntegrityReportPage pageWithResponseDictionary:json];
		completion(page, page ? nil : IMIntegrityMalformedReport());
	}];
}

+ (nullable NSURLSessionTask *)integrityReportForType:(NSString *)type
                                               cursor:(nullable NSString *)cursor
                                                limit:(NSInteger)limit
                                           completion:(IMIntegrityReportCompletion)completion {
	return [self reportForType:type cursor:cursor limit:limit completion:completion];
}

+ (nullable NSURLSessionTask *)getIntegrityReportForType:(NSString *)type
                                                  cursor:(nullable NSString *)cursor
                                                   limit:(NSInteger)limit
                                              completion:(IMIntegrityReportCompletion)completion {
	return [self reportForType:type cursor:cursor limit:limit completion:completion];
}

+ (nullable NSURLSessionTask *)reportForType:(NSString *)type
                              completion:(IMIntegrityReportCompletion)completion {
	return [self reportForType:type cursor:nil limit:100 completion:completion];
}

+ (nullable NSURLSessionTask *)reportFileForId:(NSString *)reportId
                                 destinationURL:(NSURL *)destinationURL
                                      completion:(IMIntegrityFileCompletion)completion {
	if (!IMIntegrityUUIDv7IsValid(reportId)) {
		IMIntegrityAsyncFileFailure(completion, IMIntegrityInputError(_(@"A valid integrity report ID is required.")));
		return nil;
	}
	if (![destinationURL isKindOfClass:[NSURL class]] || !destinationURL.isFileURL || destinationURL.path.length == 0) {
		IMIntegrityAsyncFileFailure(completion, IMIntegrityInputError(_(@"A local destination file is required for the integrity download.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/integrity/report/%@/file", IMIntegrityPathComponent(reportId)];
	return [[IMApiClient shared] downloadFile:path
	                                      query:nil
	                             destinationURL:destinationURL
	                                  completion:^(NSURL *fileURL, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![fileURL isKindOfClass:[NSURL class]] || !fileURL.isFileURL || fileURL.path.length == 0) {
			completion(nil, IMIntegrityMalformedFile());
			return;
		}
		NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:NULL];
		if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) {
			completion(nil, IMIntegrityMalformedFile());
			return;
		}
		completion(fileURL, nil);
	}];
}

+ (nullable NSURLSessionTask *)getIntegrityReportFileId:(NSString *)reportId
                                         destinationURL:(NSURL *)destinationURL
                                              completion:(IMIntegrityFileCompletion)completion {
	return [self reportFileForId:reportId destinationURL:destinationURL completion:completion];
}

+ (nullable NSURLSessionTask *)getIntegrityReportFile:(NSString *)reportId
                                        destinationURL:(NSURL *)destinationURL
                                             completion:(IMIntegrityFileCompletion)completion {
	return [self reportFileForId:reportId destinationURL:destinationURL completion:completion];
}

+ (nullable NSURLSessionTask *)deleteReportId:(NSString *)reportId
                                    completion:(IMIntegrityMutationCompletion)completion {
	if (!IMIntegrityUUIDv7IsValid(reportId)) {
		IMIntegrityAsyncMutationFailure(completion, IMIntegrityInputError(_(@"A valid integrity report ID is required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/integrity/report/%@", IMIntegrityPathComponent(reportId)];
	return [[IMApiClient shared] DELETE:path
	                                  body:nil
	                            completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (json != nil) {
			completion(NO, IMIntegrityMalformedMutation());
			return;
		}
		completion(YES, nil);
	}];
}

+ (nullable NSURLSessionTask *)deleteIntegrityReportId:(NSString *)reportId
                                            completion:(IMIntegrityMutationCompletion)completion {
	return [self deleteReportId:reportId completion:completion];
}

+ (nullable NSURLSessionTask *)reportCSVForType:(NSString *)type
                                 destinationURL:(NSURL *)destinationURL
                                      completion:(IMIntegrityFileCompletion)completion {
	if (!IMIntegrityReportTypeIsKnown(type)) {
		IMIntegrityAsyncFileFailure(completion, IMIntegrityInputError(_(@"Choose a valid integrity report type.")));
		return nil;
	}
	if (![destinationURL isKindOfClass:[NSURL class]] || !destinationURL.isFileURL || destinationURL.path.length == 0) {
		IMIntegrityAsyncFileFailure(completion, IMIntegrityInputError(_(@"A local destination file is required for the CSV export.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/integrity/report/%@/csv", IMIntegrityPathComponent(type)];
	return [[IMApiClient shared] downloadFile:path
	                                      query:nil
	                             destinationURL:destinationURL
	                                  completion:^(NSURL *fileURL, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![fileURL isKindOfClass:[NSURL class]] || !fileURL.isFileURL || fileURL.path.length == 0) {
			completion(nil, IMIntegrityMalformedFile());
			return;
		}
		NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:NULL];
		NSNumber *fileSize = attributes[NSFileSize];
		if (![fileSize isKindOfClass:[NSNumber class]] || fileSize.unsignedLongLongValue == 0) {
			completion(nil, IMIntegrityMalformedFile());
			return;
		}
		completion(fileURL, nil);
	}];
}

+ (nullable NSURLSessionTask *)integrityReportCSVForType:(NSString *)type
                                          destinationURL:(NSURL *)destinationURL
                                               completion:(IMIntegrityFileCompletion)completion {
	return [self reportCSVForType:type destinationURL:destinationURL completion:completion];
}

+ (nullable NSURLSessionTask *)getIntegrityReportCsvForType:(NSString *)type
                                             destinationURL:(NSURL *)destinationURL
                                                  completion:(IMIntegrityFileCompletion)completion {
	return [self reportCSVForType:type destinationURL:destinationURL completion:completion];
}

@end
