#import "IMUserApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMUserMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid user response.")}];
}

static BOOL IMUserUUIDv4(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = value.lowercaseString;
	return [raw isEqualToString:canonical] && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static NSString *IMUserPathComponent(NSString *value) {
	NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
	[allowed addCharactersInString:@"-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

@implementation IMUserApi

static IMUser *sCachedUser;

+ (void)currentUserWithCompletion:(void (^)(IMUser *_Nullable user, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/users/me"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
			if (error || ![json isKindOfClass:[NSDictionary class]]) {
				completion(nil, error ?: IMUserMalformedResponse());
				return;
			}
			IMUser *user = [IMUser userWithResponseDictionary:(NSDictionary *)json];
			if (!user) {
				completion(nil, IMUserMalformedResponse());
				return;
			}
			sCachedUser = user;
			completion(user, nil);
		}];
}

+ (nullable IMUser *)cachedUser {
	return sCachedUser;
}

+ (void)userWithId:(NSString *)userId
        completion:(void (^)(IMUser *_Nullable user, NSError *_Nullable error))completion {
	if (!IMUserUUIDv4(userId)) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"A valid user ID is required.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/users/%@", IMUserPathComponent(userId)];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, IMUserMalformedResponse());
			return;
		}
		IMUser *user = [[IMUser alloc] initWithDictionary:json];
		if (!user || !user.userId.length || !user.email.length || !user.name.length) {
			completion(nil, IMUserMalformedResponse());
			return;
		}
		completion(user, nil);
	}];
}

+ (void)updateCurrentUserWithFields:(NSDictionary<NSString *,id> *)fields completion:(void (^)(IMUser *, NSError *))completion {
	[[IMApiClient shared] PUT:@"/users/me" body:fields completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:NSDictionary.class]) { completion(nil, error ?: IMUserMalformedResponse()); return; }
		IMUser *user = [IMUser userWithResponseDictionary:json];
		if (!user) { completion(nil, IMUserMalformedResponse()); return; }
		sCachedUser = user;
		completion(user, nil);
	}];
}

+ (void)clearCachedUser {
	sCachedUser = nil;
}

+ (nullable NSURLSessionTask *)profileImageDataForUserId:(NSString *)userId
                                              completion:(void (^)(NSData *_Nullable, NSError *_Nullable))completion {
	if (![userId isKindOfClass:[NSString class]] || userId.length == 0) {
		NSError *error = [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"A user ID is required to load the profile image.")}];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/users/%@/profile-image", userId];
	return [[IMApiClient shared] getData:path query:nil completion:completion];
}

+ (nullable NSURLSessionTask *)uploadProfileImageData:(NSData *)data
                                             filename:(NSString *)filename
                                           completion:(void (^)(BOOL, NSError *_Nullable))completion {
	if (data.length == 0 || filename.length == 0) {
		NSError *error = [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Choose a non-empty profile image.")}];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
		return nil;
	}
	return [[IMApiClient shared] multipartPOST:@"/users/profile-image"
	                                    fields:@{}
	                                 fileField:@"file"
	                                  filename:filename
	                                  fileData:data
	                                completion:^(id json, NSError *error) {
		if (error) { completion(NO, error); return; }
		[self currentUserWithCompletion:^(IMUser *user, NSError *refreshError) {
			completion(refreshError == nil, refreshError);
		}];
	}];
}

+ (nullable NSURLSessionTask *)deleteProfileImageWithCompletion:(void (^)(BOOL, NSError *_Nullable))completion {
	return [[IMApiClient shared] DELETE:@"/users/profile-image" body:nil completion:^(id json, NSError *error) {
		if (error) { completion(NO, error); return; }
		sCachedUser = nil;
		[self currentUserWithCompletion:^(IMUser *user, NSError *refreshError) {
			completion(refreshError == nil, refreshError);
		}];
	}];
}

@end
