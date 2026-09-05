#import "IMDuplicateApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMDuplicateValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:0
	                        userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static void IMDuplicateCompleteOnMain(IMDuplicateMutationCompletion completion, BOOL success, NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(success, error);
	});
}

static NSArray<NSString *> *IMDuplicateFilteredIDs(NSArray *values) {
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (id value in values) {
		if ([value isKindOfClass:[NSString class]] && [value length] > 0 && ![result containsObject:value]) {
			[result addObject:value];
		}
	}
	return result;
}

@implementation IMDuplicateApi

+ (nullable NSURLSessionTask *)duplicatesWithCompletion:(IMDuplicatesCompletion)completion {
	return [[IMApiClient shared] GET:@"/duplicates"
	                             query:nil
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMDuplicateValidationError(_(@"The server returned an invalid duplicates response.")));
			return;
		}
		completion([IMDuplicate duplicatesWithResponseArray:(NSArray *)json], nil);
	}];
}

+ (nullable NSURLSessionTask *)getAssetDuplicatesWithCompletion:(IMDuplicatesCompletion)completion {
	return [self duplicatesWithCompletion:completion];
}

+ (nullable NSURLSessionTask *)dismissDuplicateId:(NSString *)duplicateId
                                       completion:(IMDuplicateMutationCompletion)completion {
	if (![duplicateId isKindOfClass:[NSString class]] || duplicateId.length == 0) {
		IMDuplicateCompleteOnMain(completion, NO, IMDuplicateValidationError(_(@"A duplicate group ID is required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/duplicates/%@", duplicateId];
	return [[IMApiClient shared] DELETE:path
	                                  body:nil
	                            completion:^(id _Nullable json, NSError *_Nullable error) {
		completion(error == nil, error);
	}];
}

+ (nullable NSURLSessionTask *)deleteDuplicateId:(NSString *)duplicateId
                                      completion:(IMDuplicateMutationCompletion)completion {
	return [self dismissDuplicateId:duplicateId completion:completion];
}

+ (nullable NSURLSessionTask *)dismissDuplicateIds:(NSArray<NSString *> *)duplicateIds
                                        completion:(IMDuplicateMutationCompletion)completion {
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	for (id value in duplicateIds) {
		if ([value isKindOfClass:[NSString class]] && [value length] > 0 && ![ids containsObject:value]) {
			[ids addObject:value];
		}
	}
	if (ids.count == 0) {
		IMDuplicateCompleteOnMain(completion, NO, IMDuplicateValidationError(_(@"At least one duplicate group is required.")));
		return nil;
	}
	return [[IMApiClient shared] DELETE:@"/duplicates"
	                                  body:@{ @"ids": ids }
	                            completion:^(id _Nullable json, NSError *_Nullable error) {
		completion(error == nil, error);
	}];
}

+ (nullable NSURLSessionTask *)deleteDuplicates:(NSArray<NSString *> *)duplicateIds
                                       completion:(IMDuplicateMutationCompletion)completion {
	return [self dismissDuplicateIds:duplicateIds completion:completion];
}

+ (nullable NSURLSessionTask *)resolveDuplicateId:(NSString *)duplicateId
                                      keepAssetIds:(NSArray<NSString *> *)keepAssetIds
                                     trashAssetIds:(NSArray<NSString *> *)trashAssetIds
                                        completion:(IMDuplicateMutationCompletion)completion {
	if (![duplicateId isKindOfClass:[NSString class]] || duplicateId.length == 0) {
		IMDuplicateCompleteOnMain(completion, NO, IMDuplicateValidationError(_(@"A duplicate group ID is required.")));
		return nil;
	}
	NSDictionary *group = @{
		@"duplicateId": duplicateId,
		@"keepAssetIds": IMDuplicateFilteredIDs(keepAssetIds),
		@"trashAssetIds": IMDuplicateFilteredIDs(trashAssetIds),
	};
	return [self resolveDuplicateGroups:@[ group ] completion:completion];
}

+ (nullable NSURLSessionTask *)resolveDuplicateGroups:(NSArray<NSDictionary *> *)groups
                                            completion:(IMDuplicateMutationCompletion)completion {
	NSMutableArray<NSDictionary *> *validGroups = [NSMutableArray array];
	for (NSDictionary *value in groups) {
		if (![value isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		NSString *duplicateID = [value[@"duplicateId"] isKindOfClass:[NSString class]] ? value[@"duplicateId"] : nil;
		if (duplicateID.length == 0) {
			continue;
		}
		NSArray *keep = [value[@"keepAssetIds"] isKindOfClass:[NSArray class]] ? value[@"keepAssetIds"] : @[];
		NSArray *trash = [value[@"trashAssetIds"] isKindOfClass:[NSArray class]] ? value[@"trashAssetIds"] : @[];
		[validGroups addObject:@{
			@"duplicateId": duplicateID,
			@"keepAssetIds": IMDuplicateFilteredIDs(keep),
			@"trashAssetIds": IMDuplicateFilteredIDs(trash),
		}];
	}
	if (validGroups.count == 0) {
		IMDuplicateCompleteOnMain(completion, NO, IMDuplicateValidationError(_(@"At least one duplicate group is required.")));
		return nil;
	}
	return [[IMApiClient shared] POST:@"/duplicates/resolve"
	                                 body:@{ @"groups": validGroups }
	                           completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(YES, nil);
			return;
		}
		NSError *firstFailure = nil;
		for (id item in (NSArray *)json) {
			if (![item isKindOfClass:[NSDictionary class]]) {
				continue;
			}
			id success = item[@"success"];
			if ([success respondsToSelector:@selector(boolValue)] && ![success boolValue]) {
				NSString *message = [item[@"errorMessage"] isKindOfClass:[NSString class]] ? item[@"errorMessage"] : nil;
				if (message.length == 0 && [item[@"error"] isKindOfClass:[NSString class]]) {
					message = item[@"error"];
				}
				firstFailure = IMDuplicateValidationError(message.length ? message : _(@"The server could not resolve one or more duplicate groups."));
				break;
			}
		}
		completion(firstFailure == nil, firstFailure);
	}];
}

+ (nullable NSURLSessionTask *)resolveDuplicates:(NSArray<NSDictionary *> *)groups
                                      completion:(IMDuplicateMutationCompletion)completion {
	return [self resolveDuplicateGroups:groups completion:completion];
}

@end
