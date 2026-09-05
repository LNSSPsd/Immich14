#import "IMDownloadApi.h"
#import "IMApiClient.h"
#import "common.h"
#include <math.h>
#include <string.h>

static NSError *IMDownloadInputError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The download request is invalid.") }];
}

static NSError *IMDownloadMalformedResponseError(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{ NSLocalizedDescriptionKey: _(@"The server returned invalid download information.") }];
}

static BOOL IMDownloadUUIDv4(id value) {
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
	BOOL validVariant = variant == '8' || variant == '9' || variant == 'a' || variant == 'A' ||
	                    variant == 'b' || variant == 'B';
	return version == '4' && validVariant;
}

static BOOL IMDownloadUUIDArray(NSArray *assetIds) {
	if (![assetIds isKindOfClass:[NSArray class]] || assetIds.count == 0) {
		return NO;
	}
	NSMutableSet<NSString *> *seen = [NSMutableSet setWithCapacity:assetIds.count];
	for (id value in assetIds) {
		if (!IMDownloadUUIDv4(value)) {
			return NO;
		}
		NSString *canonical = [(NSString *)value lowercaseString];
		if ([seen containsObject:canonical]) {
			return NO;
		}
		[seen addObject:canonical];
	}
	return YES;
}

static BOOL IMDownloadOptionalArchiveSize(NSNumber *archiveSize) {
	if (!archiveSize) {
		return YES;
	}
	if (![archiveSize isKindOfClass:[NSNumber class]]) {
		return NO;
	}
	const char *type = archiveSize.objCType;
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) {
		return NO;
	}
	double value = archiveSize.doubleValue;
	return isfinite(value) && floor(value) == value && value >= 1.0 &&
	       value <= 9007199254740991.0 && value <= (double)NSIntegerMax;
}

static BOOL IMDownloadUUIDString(NSString *value) {
	return IMDownloadUUIDv4(value);
}

static NSDictionary<NSString *, id> *IMDownloadInfoBody(NSArray<NSString *> *assetIds,
	                                                        NSString *albumId,
	                                                        NSString *userId,
	                                                        NSNumber *archiveSize,
	                                                        NSError **errorOut) {
	if (assetIds && !IMDownloadUUIDArray(assetIds)) {
		if (errorOut) *errorOut = IMDownloadInputError(_(@"Select at least one valid asset."));
		return nil;
	}
	if (albumId && !IMDownloadUUIDString(albumId)) {
		if (errorOut) *errorOut = IMDownloadInputError(_(@"The album ID is invalid."));
		return nil;
	}
	if (userId && !IMDownloadUUIDString(userId)) {
		if (errorOut) *errorOut = IMDownloadInputError(_(@"The user ID is invalid."));
		return nil;
	}
	NSInteger selectorCount = (assetIds ? 1 : 0) + (albumId ? 1 : 0) + (userId ? 1 : 0);
	if (selectorCount != 1) {
		if (errorOut) *errorOut = IMDownloadInputError(_(@"Choose assets, an album, or a user to download."));
		return nil;
	}
	if (!IMDownloadOptionalArchiveSize(archiveSize)) {
		if (errorOut) *errorOut = IMDownloadInputError(_(@"The archive size must be a positive whole number."));
		return nil;
	}
	NSMutableDictionary<NSString *, id> *body = [NSMutableDictionary dictionary];
	if (assetIds) body[@"assetIds"] = [assetIds copy];
	if (albumId) body[@"albumId"] = albumId;
	if (userId) body[@"userId"] = userId;
	if (archiveSize) body[@"archiveSize"] = archiveSize;
	return body;
}

@interface IMDownloadApi ()
+ (nullable NSURLSessionTask *)downloadInfoWithBody:(NSDictionary<NSString *, id> *)body
	                                      completion:(void (^)(IMDownloadResponseDto *_Nullable response,
	                                                           NSError *_Nullable error))completion;
@end

@implementation IMDownloadApi

+ (NSURLSessionTask *)downloadInfoWithBody:(NSDictionary<NSString *, id> *)body
	                             completion:(void (^)(IMDownloadResponseDto *_Nullable response,
	                                                   NSError *_Nullable error))completion {
	return [[IMApiClient shared] POST:@"/download/info" body:body completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMDownloadResponseDto *response = [IMDownloadResponseDto responseWithDictionary:json];
		completion(response, response ? nil : IMDownloadMalformedResponseError());
	}];
}

+ (NSURLSessionTask *)downloadInfoForAssetIds:(NSArray<NSString *> *)assetIds
	                                  archiveSize:(NSNumber *)archiveSize
	                                   completion:(void (^)(IMDownloadResponseDto *, NSError *))completion {
	NSError *error = nil;
	NSDictionary *body = IMDownloadInfoBody(assetIds, nil, nil, archiveSize, &error);
	if (!body) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	return [self downloadInfoWithBody:body completion:completion];
}

+ (NSURLSessionTask *)downloadInfoForAlbumId:(NSString *)albumId
	                                 archiveSize:(NSNumber *)archiveSize
	                                  completion:(void (^)(IMDownloadResponseDto *, NSError *))completion {
	NSError *error = nil;
	NSDictionary *body = IMDownloadInfoBody(nil, albumId, nil, archiveSize, &error);
	if (!body) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	return [self downloadInfoWithBody:body completion:completion];
}

+ (NSURLSessionTask *)downloadInfoForUserId:(NSString *)userId
	                                 archiveSize:(NSNumber *)archiveSize
	                                  completion:(void (^)(IMDownloadResponseDto *, NSError *))completion {
	NSError *error = nil;
	NSDictionary *body = IMDownloadInfoBody(nil, nil, userId, archiveSize, &error);
	if (!body) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	return [self downloadInfoWithBody:body completion:completion];
}

+ (NSURLSessionTask *)downloadArchiveForAssetIds:(NSArray<NSString *> *)assetIds
	                                           edited:(BOOL)edited
	                                              key:(NSString *)key
	                                             slug:(NSString *)slug
	                                   destinationURL:(NSURL *)destinationURL
	                                       completion:(void (^)(NSURL *, NSError *))completion {
	if (!IMDownloadUUIDArray(assetIds)) {
		NSError *error = IMDownloadInputError(_(@"Select at least one valid asset."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	if (![destinationURL isKindOfClass:[NSURL class]] || !destinationURL.isFileURL || destinationURL.path.length == 0) {
		NSError *error = IMDownloadInputError(_(@"A local destination file is required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	if (key && (![key isKindOfClass:[NSString class]] || key.length == 0 || key.length > 512) ||
	    slug && (![slug isKindOfClass:[NSString class]] || slug.length == 0 || slug.length > 512)) {
		NSError *error = IMDownloadInputError(_(@"The shared-link identifier is invalid."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
	if (key.length > 0) query[@"key"] = key;
	if (slug.length > 0) query[@"slug"] = slug;
	NSDictionary *body = @{ @"assetIds": [assetIds copy], @"edited": @(edited) };
	return [[IMApiClient shared] downloadFile:@"/download/archive"
	                                     method:@"POST"
	                                      query:query.count ? query : nil
	                                       body:body
	                              destinationURL:destinationURL
	                                  completion:completion];
}

@end
