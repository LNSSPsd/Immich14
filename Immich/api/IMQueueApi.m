#import "IMQueueApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMQueueApiInputError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The queue request is invalid.")}];
}

static NSError *IMQueueApiLegacyMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid legacy queue response.")}];
}

static void IMQueueApiLegacyFailure(void (^completion)(IMQueueLegacyResponse *_Nullable response,
	                                                      NSError *_Nullable error),
	                                   NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(nil, error);
	});
}

static NSString *IMQueueApiPathComponent(NSString *value) {
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
	    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

static BOOL IMQueueResponseIsValid(id value) {
	if (![value isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSDictionary *queue = (NSDictionary *)value;
	if (![queue[@"name"] isKindOfClass:[NSString class]] || [queue[@"name"] length] == 0 ||
	    ![queue[@"isPaused"] isKindOfClass:[NSNumber class]] ||
	    ![queue[@"statistics"] isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSDictionary *statistics = queue[@"statistics"];
	for (NSString *key in @[ @"active", @"completed", @"delayed", @"failed", @"waiting", @"paused" ]) {
		if (![statistics[key] isKindOfClass:[NSNumber class]]) {
			return NO;
		}
	}
	return YES;
}

@implementation IMQueueApi

+ (void)allQueuesWithCompletion:(void (^)(NSArray<IMQueue *> *, NSError *))completion {
	[[IMApiClient shared] GET:@"/queues" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			if (!error) error = [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid queue response.")}];
			completion(nil, error);
			return;
		}
		for (id value in (NSArray *)json) {
			if (!IMQueueResponseIsValid(value)) {
				completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid queue response.")}]);
				return;
			}
		}
		completion([IMQueue queuesWithArray:json], nil);
	}];
}

+ (void)setQueueNamed:(NSString *)name paused:(BOOL)paused completion:(void (^)(IMQueue *, NSError *))completion {
	if (name.length == 0) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid queue name.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/queues/%@", name];
	[[IMApiClient shared] PUT:path body:@{ @"isPaused": @(paused) } completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, [NSError errorWithDomain:IMApiErrorDomain
			                                    code:2
			                                userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid queue response.")}]);
			return;
		}
		if (!IMQueueResponseIsValid(json)) {
			completion(nil, [NSError errorWithDomain:IMApiErrorDomain
		                                                     code:2
		                                                 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid queue response.")}]);
			return;
		}
		IMQueue *queue = [[IMQueue alloc] initWithDictionary:json];
		completion(queue, queue ? nil : [NSError errorWithDomain:IMApiErrorDomain
		                                                     code:2
		                                                 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid queue response.")}]);
	}];
}

+ (nullable NSURLSessionTask *)runQueueCommandLegacyNamed:(NSString *)name
	                                                  request:(IMQueueCommandRequest *)request
	                                              completion:(void (^)(IMQueueLegacyResponse *_Nullable, NSError *_Nullable))completion {
	if (!IMQueueNameIsKnown(name)) {
		IMQueueApiLegacyFailure(completion, IMQueueApiInputError(_(@"Choose a valid queue name.")));
		return nil;
	}
	if (![request isKindOfClass:[IMQueueCommandRequest class]]) {
		IMQueueApiLegacyFailure(completion, IMQueueApiInputError(_(@"A valid queue command is required.")));
		return nil;
	}
	NSString *encodedName = IMQueueApiPathComponent(name);
	if (encodedName.length == 0) {
		IMQueueApiLegacyFailure(completion, IMQueueApiInputError(_(@"The queue name cannot be encoded.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/jobs/%@", encodedName];
	return [[IMApiClient shared] PUT:path
	                             body:request.requestDictionary
	                       completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMQueueLegacyResponse *response = [IMQueueLegacyResponse responseWithDictionary:json];
		completion(response, response ? nil : IMQueueApiLegacyMalformedResponse());
	}];
}

+ (nullable NSURLSessionTask *)runQueueCommandLegacyNamed:(NSString *)name
	                                                  command:(NSString *)command
	                                                    force:(NSNumber *)force
	                                              completion:(void (^)(IMQueueLegacyResponse *_Nullable, NSError *_Nullable))completion {
	IMQueueCommandRequest *request = [IMQueueCommandRequest requestWithCommand:command force:force];
	if (!request) {
		IMQueueApiLegacyFailure(completion, IMQueueApiInputError(_(@"Choose a valid queue command and force value.")));
		return nil;
	}
	return [self runQueueCommandLegacyNamed:name request:request completion:completion];
}

+ (nullable NSURLSessionTask *)runQueueCommandLegacyNamed:(NSString *)name
	                                                  command:(NSString *)command
	                                              completion:(void (^)(IMQueueLegacyResponse *_Nullable, NSError *_Nullable))completion {
	return [self runQueueCommandLegacyNamed:name command:command force:nil completion:completion];
}

+ (void)runManualJobNamed:(NSString *)name completion:(void (^)(BOOL, NSError *))completion {
	if (name.length == 0) {
		completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid job name.")}]);
		return;
	}
	[[IMApiClient shared] POST:@"/jobs" body:@{ @"name": name } completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (void)emptyQueueNamed:(NSString *)name includeFailed:(BOOL)includeFailed completion:(void (^)(BOOL, NSError *))completion {
	if (name.length == 0) {
		completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid queue name.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/queues/%@/jobs", name];
	[[IMApiClient shared] DELETE:path body:@{ @"failed": @(includeFailed) } completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

@end
