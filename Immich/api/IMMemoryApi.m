#import "IMMemoryApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMMemoryMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid memory response.")}];
}

static NSError *IMMemoryValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: message}];
}

static void IMMemoryFailObjectAsync(void (^completion)(id, NSError *), NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
}

static void IMMemoryFailBoolAsync(void (^completion)(BOOL, NSError *), NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
}

static NSString *IMMemoryPathComponent(NSString *value) {
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
	    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static NSArray<NSString *> *IMMemoryNormalizedIDs(NSArray<NSString *> *ids) {
	if (![ids isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:ids.count];
	NSMutableSet<NSString *> *seen = [NSMutableSet setWithCapacity:ids.count];
	for (id raw in ids) {
		if (![raw isKindOfClass:[NSString class]]) continue;
		NSString *value = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (value.length && ![seen containsObject:value]) {
			[seen addObject:value];
			[result addObject:value];
		}
	}
	return result;
}

static BOOL IMMemoryDateStringIsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
	static NSISO8601DateFormatter *formatter;
	static NSISO8601DateFormatter *plainFormatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSISO8601DateFormatter alloc] init];
		formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
		plainFormatter = [[NSISO8601DateFormatter alloc] init];
		plainFormatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
	});
	return [formatter dateFromString:value] != nil || [plainFormatter dateFromString:value] != nil;
}

static IMMemory *IMMemoryParseResponse(id json) {
	return [json isKindOfClass:[NSDictionary class]] ? [IMMemory memoryWithResponseDictionary:json] : nil;
}

static NSError *IMMemoryValidateBulkResponse(id json, NSArray<NSString *> *requestedIDs) {
	if (![json isKindOfClass:[NSArray class]]) return IMMemoryMalformedResponse();
	NSArray *rows = (NSArray *)json;
	if (rows.count != requestedIDs.count) return IMMemoryMalformedResponse();
	NSMutableSet<NSString *> *expected = [NSMutableSet setWithArray:requestedIDs];
	for (id row in rows) {
		if (![row isKindOfClass:[NSDictionary class]]) return IMMemoryMalformedResponse();
		id identifier = row[@"id"];
		id success = row[@"success"];
		if (![identifier isKindOfClass:[NSString class]] || ![expected containsObject:identifier] ||
		    ![success isKindOfClass:[NSNumber class]]) return IMMemoryMalformedResponse();
		if (![success boolValue]) {
			NSString *message = [row[@"errorMessage"] isKindOfClass:[NSString class]] ? row[@"errorMessage"] : nil;
			return IMMemoryValidationError(message.length ? message : _(@"The server rejected one or more memory photos."));
		}
		[expected removeObject:identifier];
	}
	return expected.count == 0 ? nil : IMMemoryMalformedResponse();
}

@interface IMMemoryApi ()
+ (void)mutateAssetIds:(NSArray<NSString *> *)assetIds
              memoryId:(NSString *)memoryId
                method:(NSString *)method
            completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
@end

@implementation IMMemoryApi

+ (void)allMemoriesWithCompletion:(void (^)(NSArray<IMMemory *> *_Nullable memories,
                                             NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/memories"
	                     query:@{ @"isTrashed": @"false", @"order": @"desc", @"size": @"100" }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMMemoryMalformedResponse());
			return;
		}
		NSArray *rows = (NSArray *)json;
		NSArray<IMMemory *> *memories = [IMMemory memoriesWithResponseArray:rows];
		if (memories.count != rows.count) {
			completion(nil, IMMemoryMalformedResponse());
			return;
		}
		completion(memories, nil);
	}];
}

+ (void)statisticsWithCompletion:(void (^)(IMMemoryStatistics *_Nullable statistics,
                                            NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/memories/statistics"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    IMMemoryStatistics *statistics = [IMMemoryStatistics statisticsWithDictionary:json];
		    completion(statistics, statistics ? nil : IMMemoryMalformedResponse());
	    }];
}

+ (void)memoryWithId:(NSString *)memoryId
          completion:(void (^)(IMMemory *_Nullable memory, NSError *_Nullable error))completion {
	if (![memoryId isKindOfClass:[NSString class]] || memoryId.length == 0) {
		IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"A memory ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/memories/%@", IMMemoryPathComponent(memoryId)];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMMemory *memory = IMMemoryParseResponse(json);
		completion(memory, memory ? nil : IMMemoryMalformedResponse());
	}];
}

+ (void)createMemoryWithType:(NSString *)type
                     dataYear:(NSInteger)dataYear
                    memoryAt:(NSString *)memoryAt
                    assetIds:(NSArray<NSString *> *)assetIds
                    isSaved:(NSNumber *)isSaved
                     seenAt:(NSString *)seenAt
                      showAt:(NSString *)showAt
                      hideAt:(NSString *)hideAt
                  completion:(void (^)(IMMemory *_Nullable memory, NSError *_Nullable error))completion {
	if (![type isKindOfClass:[NSString class]] || ![type isEqualToString:@"on_this_day"] ||
	    dataYear < 1000 || dataYear > 9999 || !IMMemoryDateStringIsValid(memoryAt)) {
		IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"Choose a valid memory type, year, and date.")));
		return;
	}
	NSArray<NSString *> *ids = assetIds ? IMMemoryNormalizedIDs(assetIds) : @[];
	if (assetIds && !ids) {
		IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"Memory photo IDs are invalid.")));
		return;
	}
	for (NSString *date in @[ seenAt ?: @"", showAt ?: @"", hideAt ?: @"" ]) {
		if (date.length && !IMMemoryDateStringIsValid(date)) {
			IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"Memory dates must use RFC3339 format.")));
			return;
		}
	}
	NSMutableDictionary *body = [@{
		@"type": type,
		@"data": @{ @"year": @(dataYear) },
		@"memoryAt": memoryAt,
	} mutableCopy];
	if (ids.count) body[@"assetIds"] = ids;
	if (isSaved) body[@"isSaved"] = @([isSaved boolValue]);
	if (seenAt.length) body[@"seenAt"] = seenAt;
	if (showAt.length) body[@"showAt"] = showAt;
	if (hideAt.length) body[@"hideAt"] = hideAt;
	[[IMApiClient shared] POST:@"/memories" body:body completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMMemory *memory = IMMemoryParseResponse(json);
		completion(memory, memory ? nil : IMMemoryMalformedResponse());
	}];
}

+ (void)updateMemoryId:(NSString *)memoryId
               isSaved:(BOOL)isSaved
            completion:(void (^)(IMMemory *_Nullable memory, NSError *_Nullable error))completion {
	[self updateMemoryId:memoryId fields:@{ @"isSaved": @(isSaved) } completion:completion];
}

+ (void)updateMemoryId:(NSString *)memoryId
                fields:(NSDictionary<NSString *,id> *)fields
            completion:(void (^)(IMMemory *_Nullable memory, NSError *_Nullable error))completion {
	if (![memoryId isKindOfClass:[NSString class]] || memoryId.length == 0) {
		IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"A memory ID is required.")));
		return;
	}
	if (![fields isKindOfClass:[NSDictionary class]] || fields.count == 0) {
		IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"Choose at least one memory field to update.")));
		return;
	}
	NSSet *allowed = [NSSet setWithObjects:@"isSaved", @"seenAt", @"memoryAt", nil];
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	for (NSString *key in fields) {
		if (![allowed containsObject:key]) continue;
		id value = fields[key];
		if ([key isEqualToString:@"isSaved"]) {
			if (![value isKindOfClass:[NSNumber class]]) {
				IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"Saved must be a boolean.")));
				return;
			}
			body[key] = @([value boolValue]);
		} else if ([key isEqualToString:@"seenAt"] && [value isKindOfClass:[NSNull class]]) {
			body[key] = value;
		} else if ([value isKindOfClass:[NSString class]] && IMMemoryDateStringIsValid(value)) {
			body[key] = value;
		} else {
			IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"Memory dates must use RFC3339 format.")));
			return;
		}
	}
	if (body.count == 0) {
		IMMemoryFailObjectAsync(completion, IMMemoryValidationError(_(@"Choose a supported memory field to update.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/memories/%@", IMMemoryPathComponent(memoryId)];
	[[IMApiClient shared] PUT:path body:body completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMMemory *memory = IMMemoryParseResponse(json);
		completion(memory, memory ? nil : IMMemoryMalformedResponse());
	}];
}

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
        toMemoryId:(NSString *)memoryId
         completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	[self mutateAssetIds:assetIds memoryId:memoryId method:@"PUT" completion:completion];
}

+ (void)removeAssetIds:(NSArray<NSString *> *)assetIds
           fromMemoryId:(NSString *)memoryId
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	[self mutateAssetIds:assetIds memoryId:memoryId method:@"DELETE" completion:completion];
}

+ (void)mutateAssetIds:(NSArray<NSString *> *)assetIds
              memoryId:(NSString *)memoryId
                method:(NSString *)method
            completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSArray<NSString *> *ids = IMMemoryNormalizedIDs(assetIds);
	if (![memoryId isKindOfClass:[NSString class]] || memoryId.length == 0 || ids.count == 0) {
		IMMemoryFailBoolAsync(completion, IMMemoryValidationError(_(@"Choose a memory and at least one photo.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/memories/%@/assets", IMMemoryPathComponent(memoryId)];
	IMJSONHandler handler = ^(id json, NSError *error) {
		if (error) { completion(NO, error); return; }
		NSError *validation = IMMemoryValidateBulkResponse(json, ids);
		completion(validation == nil, validation);
	};
	if ([method isEqualToString:@"DELETE"]) {
		[[IMApiClient shared] DELETE:path body:@{ @"ids": ids } completion:handler];
	} else {
		[[IMApiClient shared] PUT:path body:@{ @"ids": ids } completion:handler];
	}
}

+ (void)deleteMemoryId:(NSString *)memoryId
            completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (![memoryId isKindOfClass:[NSString class]] || memoryId.length == 0) {
		IMMemoryFailBoolAsync(completion, IMMemoryValidationError(_(@"A memory ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/memories/%@", IMMemoryPathComponent(memoryId)];
	[[IMApiClient shared] DELETE:path
	                         body:nil
	                   completion:^(id _Nullable json, NSError *_Nullable error) {
		completion(error == nil, error);
	}];
}

@end
