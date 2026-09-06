#import "IMAccountApi.h"
#import "IMApiClient.h"
#import "IMAdminUser.h"
#import "common.h"

static BOOL IMAccountSessionResponseIsValid(id value) {
	return [value isKindOfClass:[NSDictionary class]] &&
	       [value[@"id"] isKindOfClass:[NSString class]] && [value[@"id"] length] > 0;
}

static BOOL IMAccountAPIKeyResponseIsValid(id value) {
	return [IMAPIKey keyWithResponseDictionary:value] != nil;
}

static BOOL IMAccountUUIDv4IsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = value.lowercaseString;
	return [raw isEqualToString:canonical] && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static NSString *IMAccountPathComponent(NSString *value) {
	NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
	[allowed addCharactersInString:@"-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

@implementation IMAccountApi

+ (void)changePassword:(NSString *)currentPassword
           newPassword:(NSString *)newPassword
      invalidateSessions:(BOOL)invalidateSessions
             completion:(void (^)(BOOL, NSError *))completion {
	if (currentPassword.length == 0 || newPassword.length < 8) {
		completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Enter the current password and a new password with at least 8 characters.")}]);
		return;
	}
	NSDictionary *body = @{ @"password": currentPassword, @"newPassword": newPassword, @"invalidateSessions": @(invalidateSessions) };
	[[IMApiClient shared] POST:@"/auth/change-password" body:body completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (![IMAdminUser userWithResponseDictionary:json]) {
			completion(NO, [NSError errorWithDomain:IMApiErrorDomain
			                                  code:2
			                              userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid password-change response.")}]);
			return;
		}
		completion(YES, nil);
	}];
}

+ (void)sessionsWithCompletion:(void (^)(NSArray<IMSessionInfo *> *, NSError *))completion {
	[[IMApiClient shared] GET:@"/sessions" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			if (!error) error = [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid sessions response.")}];
			completion(nil, error);
			return;
		}
		for (id value in (NSArray *)json) {
			if (!IMAccountSessionResponseIsValid(value) ||
			    ![IMSessionInfo sessionWithResponseDictionary:value]) {
				completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid sessions response.")}]);
				return;
			}
		}
		completion([IMSessionInfo sessionsWithArray:json], nil);
	}];
}

+ (void)createSessionWithRequest:(IMSessionCreateRequest *)request
                       completion:(void (^)(IMSessionInfo *_Nullable, NSError *_Nullable))completion {
	if (![request isKindOfClass:[IMSessionCreateRequest class]]) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"A valid child-session request is required.")}]);
		return;
	}
	[[IMApiClient shared] POST:@"/sessions" body:request.requestDictionary completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMSessionInfo *session = [IMSessionInfo sessionWithResponseDictionary:json];
		if (!session || session.token.length == 0) {
			completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid child-session response.")}]);
			return;
		}
		completion(session, nil);
	}];
}

+ (void)createSessionWithDeviceOS:(NSString *)deviceOS
                        deviceType:(NSString *)deviceType
                         duration:(NSNumber *)duration
                        completion:(void (^)(IMSessionInfo *_Nullable, NSError *_Nullable))completion {
	IMSessionCreateRequest *request = [IMSessionCreateRequest requestWithDeviceOS:deviceOS
	                                                                      deviceType:deviceType
	                                                                       duration:duration];
	if (!request) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Enter valid child-session device details and duration.")}]);
		return;
	}
	[self createSessionWithRequest:request completion:completion];
}

+ (void)updateSessionId:(NSString *)sessionId
       pendingSyncReset:(BOOL)pendingSyncReset
              completion:(void (^)(IMSessionInfo *_Nullable, NSError *_Nullable))completion {
	if (!IMAccountUUIDv4IsValid(sessionId)) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid session identifier.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/sessions/%@", IMAccountPathComponent(sessionId)];
	[[IMApiClient shared] PUT:path body:@{ @"isPendingSyncReset": @(pendingSyncReset) } completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMSessionInfo *session = [IMSessionInfo sessionWithResponseDictionary:json];
		completion(session, session ? nil : [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid session response.")}]);
	}];
}

+ (void)deleteSessionId:(NSString *)sessionId completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAccountUUIDv4IsValid(sessionId)) {
		completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid session identifier.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/sessions/%@", IMAccountPathComponent(sessionId)];
	[[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) { completion(error == nil, error); }];
}

+ (void)lockSessionId:(NSString *)sessionId completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAccountUUIDv4IsValid(sessionId)) {
		completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid session identifier.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/sessions/%@/lock", IMAccountPathComponent(sessionId)];
	[[IMApiClient shared] POST:path body:nil completion:^(id json, NSError *error) {
		(void)json;
		completion(error == nil, error);
	}];
}

+ (void)deleteAllOtherSessionsWithCompletion:(void (^)(BOOL, NSError *))completion {
	[[IMApiClient shared] DELETE:@"/sessions" body:nil completion:^(id json, NSError *error) { completion(error == nil, error); }];
}

+ (void)apiKeysWithCompletion:(void (^)(NSArray<IMAPIKey *> *, NSError *))completion {
	[[IMApiClient shared] GET:@"/api-keys" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			if (!error) error = [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid API-key response.")}];
			completion(nil, error);
			return;
		}
		for (id value in (NSArray *)json) {
			if (!IMAccountAPIKeyResponseIsValid(value)) {
				completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid API-key response.")}]);
				return;
			}
		}
		NSMutableArray<IMAPIKey *> *keys = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (NSDictionary *value in (NSArray *)json) [keys addObject:[IMAPIKey keyWithResponseDictionary:value]];
		completion(keys, nil);
	}];
}

+ (void)currentAPIKeyWithCompletion:(void (^)(IMAPIKey *_Nullable key, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/api-keys/me" query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (!IMAccountAPIKeyResponseIsValid(json)) {
			completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid current API-key response.")}]);
			return;
		}
		IMAPIKey *key = [IMAPIKey keyWithResponseDictionary:json];
		completion(key, key.keyId.length ? nil : [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid current API-key response.")}]);
	}];
}

+ (void)createAPIKeyNamed:(NSString *)name
	             permissions:(NSArray<NSString *> *)permissions
	             completion:(void (^)(IMAPIKey *, NSString *, NSError *))completion {
	if (permissions.count == 0) {
		completion(nil, nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Choose at least one API-key permission.")}]);
		return;
	}
	NSMutableDictionary *body = [@{ @"permissions": permissions } mutableCopy];
	if (name.length) body[@"name"] = name;
	[[IMApiClient shared] POST:@"/api-keys" body:body completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSDictionary class]]) {
			if (!error) {
				error = [NSError errorWithDomain:IMApiErrorDomain
				                            code:2
				                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid API-key response.")}];
			}
			completion(nil, nil, error);
			return;
		}
		NSDictionary *response = (NSDictionary *)json;
		id keyJSON = response[@"apiKey"];
		IMAPIKey *key = [IMAPIKey keyWithResponseDictionary:keyJSON];
		id secret = response[@"secret"];
		if (!key || key.keyId.length == 0 || ![secret isKindOfClass:[NSString class]] || [secret length] == 0) {
			completion(nil, nil, [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid API-key response.")}]);
			return;
		}
		completion(key, secret, nil);
	}];
}

+ (void)updateAPIKeyId:(NSString *)keyId
	                 name:(NSString *)name
	          permissions:(NSArray<NSString *> *)permissions
	          completion:(void (^)(IMAPIKey *, NSError *))completion {
	if (keyId.length == 0 || permissions.count == 0) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"API-key name and permissions are required.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/api-keys/%@", keyId];
	NSMutableDictionary *body = [@{ @"permissions": permissions } mutableCopy];
	if (name.length) body[@"name"] = name;
	[[IMApiClient shared] PUT:path body:body completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, [NSError errorWithDomain:IMApiErrorDomain
			                                    code:2
			                                userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid API-key response.")}]);
			return;
		}
		if (!IMAccountAPIKeyResponseIsValid(json)) {
			completion(nil, [NSError errorWithDomain:IMApiErrorDomain
			                                    code:2
			                                userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid API-key response.")}]);
			return;
		}
		IMAPIKey *key = [IMAPIKey keyWithResponseDictionary:json];
		if (!key || key.keyId.length == 0) {
			completion(nil, [NSError errorWithDomain:IMApiErrorDomain
			                                    code:2
			                                userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid API-key response.")}]);
			return;
		}
		completion(key, nil);
	}];
}

+ (void)deleteAPIKeyId:(NSString *)keyId completion:(void (^)(BOOL, NSError *))completion {
	if (keyId.length == 0) {
		completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid API-key identifier.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/api-keys/%@", keyId];
	[[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) { completion(error == nil, error); }];
}

@end
