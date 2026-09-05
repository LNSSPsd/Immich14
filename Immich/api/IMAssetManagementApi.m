#import "IMAssetManagementApi.h"
#import "IMApiClient.h"
#import "common.h"
#include <string.h>

NSString *const IMAssetJobNameRefreshFaces = @"refresh-faces";
NSString *const IMAssetJobNameRefreshMetadata = @"refresh-metadata";
NSString *const IMAssetJobNameRegenerateThumbnail = @"regenerate-thumbnail";
NSString *const IMAssetJobNameTranscodeVideo = @"transcode-video";

static NSError *IMAssetManagementInputError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"Invalid asset operation.") }];
}

static NSError *IMAssetManagementResponseError(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{ NSLocalizedDescriptionKey: _(@"The server returned an invalid asset operation response.") }];
}

static BOOL IMAssetManagementUUIDIsValid(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) {
		return NO;
	}
	NSString *raw = (NSString *)value;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:raw];
	if (!uuid || ![raw.lowercaseString isEqualToString:uuid.UUIDString.lowercaseString]) {
		return NO;
	}
	unichar version = [raw characterAtIndex:14];
	unichar variant = [raw characterAtIndex:19];
	BOOL validVariant = (variant == '8' || variant == '9' || variant == 'a' || variant == 'A' ||
	                     variant == 'b' || variant == 'B');
	return version == '4' && validVariant;
}

static BOOL IMAssetManagementUUIDArrayIsValid(id value) {
	if (![value isKindOfClass:[NSArray class]] || [(NSArray *)value count] == 0) {
		return NO;
	}
	for (id assetId in (NSArray *)value) {
		if (!IMAssetManagementUUIDIsValid(assetId)) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMAssetManagementVisibilityIsValid(id value) {
	return [value isKindOfClass:[NSString class]] &&
	       [@[ @"timeline", @"archive", @"hidden", @"locked" ] containsObject:value];
}

static NSString *IMAssetManagementPathComponent(NSString *value) {
	NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
	[allowed addCharactersInString:@"-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static BOOL IMAssetManagementBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) {
		return NO;
	}
	NSNumber *number = (NSNumber *)value;
	if (strcmp(number.objCType, @encode(BOOL)) != 0) {
		return NO;
	}
	return number.doubleValue == 0.0 || number.doubleValue == 1.0;
}

@implementation IMAssetManagementApi

+ (void)finish:(id)json error:(NSError *)error completion:(void (^)(BOOL, NSError *))completion {
	completion(error == nil, error);
}

+ (void)setVisibility:(NSString *)visibility forAssetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAssetManagementVisibilityIsValid(visibility)) {
		completion(NO, IMAssetManagementInputError(_(@"Choose a valid asset visibility.")));
		return;
	}
	if (!IMAssetManagementUUIDArrayIsValid(assetIds)) {
		completion(NO, IMAssetManagementInputError(_(@"At least one valid asset ID is required.")));
		return;
	}
	[[IMApiClient shared] PUT:@"/assets" body:@{@"ids": assetIds, @"visibility": visibility} completion:^(id json, NSError *error) {
		[self finish:json error:error completion:completion];
	}];
}

+ (void)setVisibility:(NSString *)visibility forAssetId:(NSString *)assetId completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAssetManagementVisibilityIsValid(visibility)) {
		completion(NO, IMAssetManagementInputError(_(@"Choose a valid asset visibility.")));
		return;
	}
	if (!IMAssetManagementUUIDIsValid(assetId)) {
		completion(NO, IMAssetManagementInputError(_(@"A valid asset ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/assets/%@", IMAssetManagementPathComponent(assetId)];
	[[IMApiClient shared] PUT:path body:@{@"visibility": visibility} completion:^(id json, NSError *error) {
		[self finish:json error:error completion:completion];
	}];
}

+ (void)restoreAssetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAssetManagementUUIDArrayIsValid(assetIds)) {
		completion(NO, IMAssetManagementInputError(_(@"At least one valid asset ID is required.")));
		return;
	}
	[[IMApiClient shared] POST:@"/trash/restore/assets" body:@{@"ids": assetIds} completion:^(id json, NSError *error) {
		[self finish:json error:error completion:completion];
	}];
}

+ (void)restoreAllTrashWithCompletion:(void (^)(BOOL, NSError *))completion {
	[[IMApiClient shared] POST:@"/trash/restore" body:nil completion:^(id json, NSError *error) {
		[self finish:json error:error completion:completion];
	}];
}

+ (void)emptyTrashWithCompletion:(void (^)(BOOL, NSError *))completion {
	[[IMApiClient shared] POST:@"/trash/empty" body:nil completion:^(id json, NSError *error) {
		[self finish:json error:error completion:completion];
	}];
}

+ (void)copyAssetFromId:(NSString *)sourceAssetId
              toAssetId:(NSString *)targetAssetId
                options:(NSDictionary<NSString *, NSNumber *> *)options
             completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAssetManagementUUIDIsValid(sourceAssetId) || !IMAssetManagementUUIDIsValid(targetAssetId)) {
		completion(NO, IMAssetManagementInputError(_(@"Enter valid source and target asset IDs.")));
		return;
	}
	if ([sourceAssetId.lowercaseString isEqualToString:targetAssetId.lowercaseString]) {
		completion(NO, IMAssetManagementInputError(_(@"Source and target assets must be different.")));
		return;
	}
	if (options && ![options isKindOfClass:[NSDictionary class]]) {
		completion(NO, IMAssetManagementInputError(_(@"Copy options are invalid.")));
		return;
	}
	NSSet<NSString *> *allowedKeys = [NSSet setWithArray:@[ @"albums", @"favorite", @"sharedLinks", @"sidecar", @"stack" ]];
	for (id rawKey in options) {
		if (![rawKey isKindOfClass:[NSString class]] || ![allowedKeys containsObject:rawKey] ||
		    !IMAssetManagementBoolean(options[rawKey])) {
			completion(NO, IMAssetManagementInputError(_(@"Copy options are invalid.")));
			return;
		}
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
		@"sourceId": sourceAssetId,
		@"targetId": targetAssetId,
		@"albums": @YES,
		@"favorite": @YES,
		@"sharedLinks": @YES,
		@"sidecar": @YES,
		@"stack": @YES,
	}];
	[body addEntriesFromDictionary:options ?: @{}];
	[[IMApiClient shared] PUT:@"/assets/copy" body:body completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
		} else if (json != nil) {
			completion(NO, IMAssetManagementResponseError());
		} else {
			completion(YES, nil);
		}
	}];
}

+ (void)runAssetJobNamed:(NSString *)jobName
             forAssetIds:(NSArray<NSString *> *)assetIds
              completion:(void (^)(BOOL, NSError *))completion {
	NSSet<NSString *> *allowedNames = [NSSet setWithArray:@[
		IMAssetJobNameRefreshFaces,
		IMAssetJobNameRefreshMetadata,
		IMAssetJobNameRegenerateThumbnail,
		IMAssetJobNameTranscodeVideo,
	]];
	if (![jobName isKindOfClass:[NSString class]] || ![allowedNames containsObject:jobName]) {
		completion(NO, IMAssetManagementInputError(_(@"Choose a valid asset job.")));
		return;
	}
	if (![assetIds isKindOfClass:[NSArray class]] || assetIds.count == 0) {
		completion(NO, IMAssetManagementInputError(_(@"Select at least one asset.")));
		return;
	}
	for (id assetId in assetIds) {
		if (!IMAssetManagementUUIDIsValid(assetId)) {
			completion(NO, IMAssetManagementInputError(_(@"One or more asset IDs are invalid.")));
			return;
		}
	}
	[[IMApiClient shared] POST:@"/assets/jobs"
	                        body:@{ @"assetIds": assetIds, @"name": jobName }
	                  completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
		} else if (json != nil) {
			completion(NO, IMAssetManagementResponseError());
		} else {
			completion(YES, nil);
		}
	}];
}

@end
