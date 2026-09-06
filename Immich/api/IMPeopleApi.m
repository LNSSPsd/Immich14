#import "IMPeopleApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMPeopleError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

static NSError *IMPeopleMalformedResponse(void) {
	return IMPeopleError(_(@"The server returned an invalid people response."));
}

static NSError *IMPeopleMalformedMutationResponse(void) {
	return IMPeopleError(_(@"The server returned an invalid people mutation response."));
}

static void IMPeopleAsync(void (^block)(void)) {
	dispatch_async(dispatch_get_main_queue(), block);
}

static NSArray<NSString *> *_Nullable IMPeopleValidIDs(NSArray<NSString *> *values) {
	if (![values isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:values.count];
	for (id value in values) {
		if (![value isKindOfClass:[NSString class]]) continue;
		NSString *identifier = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (identifier.length && ![ids containsObject:identifier]) [ids addObject:identifier];
	}
	return ids;
}

static BOOL IMPeopleUUIDv4Valid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = value.lowercaseString;
	if (![raw isEqualToString:canonical]) return NO;
	unichar variant = [canonical characterAtIndex:19];
	return [canonical characterAtIndex:14] == '4' && (variant == '8' || variant == '9' || variant == 'a' || variant == 'b');
}

static void IMPeopleParseProfile(id json, NSError *requestError, IMPersonProfileCompletion completion) {
	if (requestError) {
		completion(nil, requestError);
		return;
	}
	IMPersonProfile *person = [json isKindOfClass:[NSDictionary class]] ? [IMPersonProfile personWithResponseDictionary:json] : nil;
	completion(person, person ? nil : IMPeopleMalformedResponse());
}

@implementation IMPeopleApi

+ (nullable NSURLSessionTask *)personWithId:(NSString *)personId completion:(IMPersonProfileCompletion)completion {
	if (![personId isKindOfClass:[NSString class]] || personId.length == 0) {
		NSError *error = IMPeopleError(_(@"A person ID is required."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/people/%@", personId];
	return [[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		IMPeopleParseProfile(json, error, completion);
	}];
}

+ (nullable NSURLSessionTask *)statisticsForPersonId:(NSString *)personId
                                         completion:(IMPersonStatisticsCompletion)completion {
	if (![personId isKindOfClass:[NSString class]] || personId.length == 0) {
		NSError *error = IMPeopleError(_(@"A person ID is required."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/people/%@/statistics", personId];
	return [[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMPersonStatistics *statistics = [json isKindOfClass:[NSDictionary class]] ? [IMPersonStatistics statisticsWithResponseDictionary:json] : nil;
		completion(statistics, statistics ? nil : IMPeopleError(_(@"The server returned invalid person statistics.")));
	}];
}

+ (nullable NSURLSessionTask *)updatePersonId:(NSString *)personId
                                          name:(NSString *)name
                                     birthDate:(NSString *)birthDate
                                       hidden:(NSNumber *)hidden
                                     favorite:(NSNumber *)favorite
                                        color:(NSString *)color
                             featureFaceAssetId:(NSString *)featureFaceAssetId
                                    completion:(IMPersonProfileCompletion)completion {
	if (![personId isKindOfClass:[NSString class]] || personId.length == 0) {
		NSError *error = IMPeopleError(_(@"A person ID is required."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	if (featureFaceAssetId != nil && !IMPeopleUUIDv4Valid(featureFaceAssetId)) {
		NSError *error = IMPeopleError(_(@"The featured photo must be a valid asset ID."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	if (name != nil) body[@"name"] = name;
	if (birthDate != nil) body[@"birthDate"] = birthDate.length ? birthDate : [NSNull null];
	if (hidden != nil) body[@"isHidden"] = @([hidden boolValue]);
	if (favorite != nil) body[@"isFavorite"] = @([favorite boolValue]);
	if (color != nil) body[@"color"] = color.length ? color : [NSNull null];
	if (featureFaceAssetId.length) body[@"featureFaceAssetId"] = featureFaceAssetId;
	if (body.count == 0) {
		NSError *error = IMPeopleError(_(@"Choose at least one person field to update."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/people/%@", personId];
	return [[IMApiClient shared] PUT:path body:body completion:^(id json, NSError *error) {
		IMPeopleParseProfile(json, error, completion);
	}];
}

+ (nullable NSURLSessionTask *)mergePersonId:(NSString *)personId
                              withPersonIds:(NSArray<NSString *> *)personIds
                                  completion:(IMPersonMutationResultsCompletion)completion {
	if (![personId isKindOfClass:[NSString class]] || personId.length == 0) {
		NSError *error = IMPeopleError(_(@"A target person ID is required."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	NSArray<NSString *> *allIDs = IMPeopleValidIDs(personIds);
	NSMutableArray<NSString *> *mergeIDs = [allIDs mutableCopy] ?: [NSMutableArray array];
	[mergeIDs removeObject:personId];
	if (mergeIDs.count == 0) {
		NSError *error = IMPeopleError(_(@"Choose at least one other person to merge."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/people/%@/merge", personId];
	return [[IMApiClient shared] POST:path body:@{ @"ids": mergeIDs } completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMPeopleMalformedResponse());
			return;
		}
		NSArray<IMPersonMutationResult *> *results = [IMPersonMutationResult strictResultsWithResponseArray:json];
		NSSet<NSString *> *expectedIds = [NSSet setWithArray:mergeIDs];
		if (!results || results.count != mergeIDs.count || expectedIds.count != mergeIDs.count) {
			completion(nil, IMPeopleMalformedMutationResponse());
			return;
		}
		NSMutableSet<NSString *> *returnedIds = [NSMutableSet setWithCapacity:results.count];
		for (IMPersonMutationResult *result in results) {
			if (![expectedIds containsObject:result.resultId] || [returnedIds containsObject:result.resultId]) {
				completion(nil, IMPeopleMalformedMutationResponse());
				return;
			}
			[returnedIds addObject:result.resultId];
		}
		if (![returnedIds isEqualToSet:expectedIds]) {
			completion(nil, IMPeopleMalformedMutationResponse());
			return;
		}
		completion(results, nil);
	}];
}

+ (nullable NSURLSessionTask *)reassignFacesToPersonId:(NSString *)personId
                                                  data:(NSArray<NSDictionary *> *)data
                                            completion:(IMPeopleProfilesCompletion)completion {
	if (![personId isKindOfClass:[NSString class]] || personId.length == 0) {
		NSError *error = IMPeopleError(_(@"A target person ID is required."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	if (![data isKindOfClass:[NSArray class]] || data.count == 0) {
		NSError *error = IMPeopleError(_(@"At least one face assignment is required."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithCapacity:data.count];
	for (id value in data) {
		if (![value isKindOfClass:[NSDictionary class]]) continue;
		NSString *sourcePersonId = [value[@"personId"] isKindOfClass:[NSString class]] ? value[@"personId"] : nil;
		NSString *assetId = [value[@"assetId"] isKindOfClass:[NSString class]] ? value[@"assetId"] : nil;
		if (sourcePersonId.length == 0 || assetId.length == 0) continue;
		[items addObject:@{ @"personId": sourcePersonId, @"assetId": assetId }];
	}
	if (items.count == 0) {
		NSError *error = IMPeopleError(_(@"Each face assignment needs a person ID and asset ID."));
		IMPeopleAsync(^{ completion(nil, error); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/people/%@/reassign", personId];
	return [[IMApiClient shared] PUT:path body:@{ @"data": items } completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMPeopleMalformedResponse());
			return;
		}
		completion([IMPersonProfile peopleWithResponseArray:json], nil);
	}];
}

+ (nullable NSURLSessionTask *)deletePersonId:(NSString *)personId
                                    completion:(void (^)(BOOL, NSError *))completion {
	if (![personId isKindOfClass:[NSString class]] || personId.length == 0) {
		NSError *error = IMPeopleError(_(@"A person ID is required."));
		IMPeopleAsync(^{ completion(NO, error); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/people/%@", personId];
	return [[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (nullable NSURLSessionTask *)deletePersonIds:(NSArray<NSString *> *)personIds
                                      completion:(void (^)(BOOL, NSError *))completion {
	NSArray<NSString *> *ids = IMPeopleValidIDs(personIds);
	if (ids.count == 0) {
		NSError *error = IMPeopleError(_(@"At least one person ID is required."));
		IMPeopleAsync(^{ completion(NO, error); });
		return nil;
	}
	return [[IMApiClient shared] DELETE:@"/people" body:@{ @"ids": ids } completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

@end
