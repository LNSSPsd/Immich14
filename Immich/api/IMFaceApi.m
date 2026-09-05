#import "IMFaceApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMFaceError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSError *IMFaceMalformed(void) {
	return [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid face response.")}];
}

static NSError *IMFaceMutationMalformed(void) {
	return [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid face mutation response.")}];
}

static NSString *IMFacePathComponent(NSString *value) {
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
	    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static void IMFaceFailAsync(void (^completion)(id, NSError *), NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
}

static void IMFaceMutationFailAsync(void (^completion)(BOOL, NSError *), NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
}

@implementation IMFaceApi

+ (nullable NSURLSessionTask *)createFaceWithRequest:(IMAssetFaceCreate *)request
                                          completion:(void (^)(BOOL, NSError *))completion {
	if (![request isKindOfClass:[IMAssetFaceCreate class]]) {
		IMFaceMutationFailAsync(completion, IMFaceError(_(@"A valid face request is required.")));
		return nil;
	}
	return [[IMApiClient shared] POST:@"/faces"
	                              body:request.requestDictionary
	                        completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (json != nil) {
			completion(NO, IMFaceMutationMalformed());
			return;
		}
		completion(YES, nil);
	}];
}

+ (nullable NSURLSessionTask *)createFaceForAssetId:(NSString *)assetId
                                           personId:(NSString *)personId
                                        imageWidth:(NSInteger)imageWidth
                                       imageHeight:(NSInteger)imageHeight
                                                 x:(NSInteger)x
                                                 y:(NSInteger)y
                                              width:(NSInteger)width
                                             height:(NSInteger)height
                                         completion:(void (^)(BOOL, NSError *))completion {
	IMAssetFaceCreate *request = [IMAssetFaceCreate requestWithAssetId:assetId
	                                                             personId:personId
	                                                          imageWidth:imageWidth
	                                                         imageHeight:imageHeight
	                                                                   x:x
	                                                                   y:y
	                                                                width:width
	                                                               height:height];
	if (!request) {
		IMFaceMutationFailAsync(completion, IMFaceError(_(@"Enter valid asset, person, and face coordinates.")));
		return nil;
	}
	return [self createFaceWithRequest:request completion:completion];
}

+ (nullable NSURLSessionTask *)facesForAssetId:(NSString *)assetId
                                    completion:(void (^)(NSArray<IMAssetFace *> *_Nullable faces, NSError *_Nullable error))completion {
	if (![assetId isKindOfClass:[NSString class]] || assetId.length == 0) {
		IMFaceFailAsync(completion, IMFaceError(_(@"An asset ID is required.")));
		return nil;
	}
	return [[IMApiClient shared] GET:@"/faces"
	                           query:@{ @"id": assetId }
	                      completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMFaceMalformed());
			return;
		}
		NSArray *rows = (NSArray *)json;
		NSArray<IMAssetFace *> *faces = [IMAssetFace facesWithResponseArray:rows];
		completion(faces.count == rows.count ? faces : nil, faces.count == rows.count ? nil : IMFaceMalformed());
	}];
}

+ (nullable NSURLSessionTask *)reassignFaceId:(NSString *)faceId
                                  toPersonId:(NSString *)personId
                                  completion:(void (^)(IMPerson *_Nullable person, NSError *_Nullable error))completion {
	if (![faceId isKindOfClass:[NSString class]] || faceId.length == 0 ||
	    ![personId isKindOfClass:[NSString class]] || personId.length == 0) {
		IMFaceFailAsync(completion, IMFaceError(_(@"A face and person are required.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/faces/%@", IMFacePathComponent(personId)];
	return [[IMApiClient shared] PUT:path body:@{ @"id": faceId } completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMPerson *person = [json isKindOfClass:[NSDictionary class]] ? [IMPerson personWithDictionary:json] : nil;
		completion(person, person ? nil : IMFaceMalformed());
	}];
}

+ (nullable NSURLSessionTask *)deleteFaceId:(NSString *)faceId
                                      force:(BOOL)force
                                completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (![faceId isKindOfClass:[NSString class]] || faceId.length == 0) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, IMFaceError(_(@"A face ID is required."))); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/faces/%@", IMFacePathComponent(faceId)];
	return [[IMApiClient shared] DELETE:path body:@{ @"force": @(force) } completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

@end
