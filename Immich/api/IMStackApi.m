#import "IMStackApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMStackMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid stack response.")}];
}

static NSError *IMStackInputError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The stack request is invalid.")}];
}

static BOOL IMStackIdentifierIsValid(NSString *value) {
	return [value isKindOfClass:[NSString class]] && value.length > 0;
}

static NSString *IMStackPathComponent(NSString *value) {
	NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
	[allowed addCharactersInString:@"-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static BOOL IMStackAssetIdsAreValid(NSArray<NSString *> *assetIds) {
	if (![assetIds isKindOfClass:[NSArray class]] || assetIds.count < 2) {
		return NO;
	}
	for (id value in assetIds) {
		if (!IMStackIdentifierIsValid(value)) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMStackResponseIsValid(id value) {
	if (![value isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSDictionary *stack = (NSDictionary *)value;
	if (![stack[@"id"] isKindOfClass:[NSString class]] || [stack[@"id"] length] == 0 ||
	    ![stack[@"primaryAssetId"] isKindOfClass:[NSString class]] || [stack[@"primaryAssetId"] length] == 0 ||
	    ![stack[@"assets"] isKindOfClass:[NSArray class]]) {
		return NO;
	}
	NSArray *rawAssets = stack[@"assets"];
	return [IMAsset assetsWithResponseArray:rawAssets].count == rawAssets.count;
}

@implementation IMStackApi

+ (nullable NSURLSessionTask *)stacksWithCompletion:(IMStacksCompletion)completion {
	return [[IMApiClient shared] GET:@"/stacks" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSArray class]]) { completion(nil, error ?: IMStackMalformedResponse()); return; }
		NSMutableArray *result = [NSMutableArray array];
		for (id value in (NSArray *)json) {
			if (!IMStackResponseIsValid(value)) { completion(nil, IMStackMalformedResponse()); return; }
			IMStack *stack = [IMStack stackWithResponseDictionary:value];
			if (!stack) { completion(nil, IMStackMalformedResponse()); return; }
			[result addObject:stack];
		}
		completion(result, nil);
	}];
}

+ (nullable NSURLSessionTask *)stackWithId:(NSString *)stackId completion:(void (^)(IMStack *_Nullable, NSError *_Nullable))completion {
	if (!IMStackIdentifierIsValid(stackId)) {
		completion(nil, IMStackInputError(_(@"A stack ID is required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/stacks/%@", IMStackPathComponent(stackId)];
	return [[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (!IMStackResponseIsValid(json)) { completion(nil, IMStackMalformedResponse()); return; }
		IMStack *stack = [IMStack stackWithResponseDictionary:json];
		completion(stack, stack ? nil : IMStackMalformedResponse());
	}];
}

+ (nullable NSURLSessionTask *)createStackWithAssetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(IMStack *_Nullable, NSError *_Nullable))completion {
	if (!IMStackAssetIdsAreValid(assetIds)) {
		completion(nil, IMStackInputError(_(@"At least two valid asset IDs are required to create a stack.")));
		return nil;
	}
	return [[IMApiClient shared] POST:@"/stacks" body:@{ @"assetIds": assetIds } completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (!IMStackResponseIsValid(json)) { completion(nil, IMStackMalformedResponse()); return; }
		IMStack *stack = [IMStack stackWithResponseDictionary:json];
		completion(stack, stack ? nil : IMStackMalformedResponse());
	}];
}

+ (nullable NSURLSessionTask *)updateStack:(NSString *)stackId primaryAssetId:(NSString *)assetId completion:(void (^)(IMStack *_Nullable, NSError *_Nullable))completion {
	if (!IMStackIdentifierIsValid(stackId) || !IMStackIdentifierIsValid(assetId)) {
		completion(nil, IMStackInputError(_(@"A stack ID and primary asset ID are required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/stacks/%@", IMStackPathComponent(stackId)];
	return [[IMApiClient shared] PUT:path body:@{ @"primaryAssetId": assetId } completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (!IMStackResponseIsValid(json)) { completion(nil, IMStackMalformedResponse()); return; }
		IMStack *stack = [IMStack stackWithResponseDictionary:json];
		completion(stack, stack ? nil : IMStackMalformedResponse());
	}];
}

+ (nullable NSURLSessionTask *)deleteStack:(NSString *)stackId completion:(void (^)(BOOL, NSError *_Nullable))completion {
	if (!IMStackIdentifierIsValid(stackId)) {
		completion(NO, IMStackInputError(_(@"A stack ID is required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/stacks/%@", IMStackPathComponent(stackId)];
	return [[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) {
		(void)json;
		completion(error == nil, error);
	}];
}

+ (nullable NSURLSessionTask *)removeAssetId:(NSString *)assetId fromStack:(NSString *)stackId completion:(void (^)(BOOL, NSError *_Nullable))completion {
	if (!IMStackIdentifierIsValid(assetId) || !IMStackIdentifierIsValid(stackId)) {
		completion(NO, IMStackInputError(_(@"A stack ID and asset ID are required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/stacks/%@/assets/%@",
	                  IMStackPathComponent(stackId), IMStackPathComponent(assetId)];
	return [[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) {
		(void)json;
		completion(error == nil, error);
	}];
}

@end
