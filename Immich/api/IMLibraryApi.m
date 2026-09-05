#import "IMLibraryApi.h"
#import "IMApiClient.h"
#import "common.h"

@implementation IMLibraryApi

static NSError *IMLibraryMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid library response.")}];
}

+ (void)allLibrariesWithCompletion:(void (^)(NSArray<IMLibrary *> *, NSError *))completion {
	[[IMApiClient shared] GET:@"/libraries" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSArray class]]) { completion(nil, IMLibraryMalformedResponse()); return; }
		NSMutableArray *libraries = [NSMutableArray array];
		for (id value in (NSArray *)json) if ([value isKindOfClass:[NSDictionary class]]) [libraries addObject:[[IMLibrary alloc] initWithDictionary:value]];
		completion(libraries, nil);
	}];
}

+ (void)createLibraryWithName:(NSString *)name
	                   ownerId:(NSString *)ownerId
	              importPaths:(NSArray<NSString *> *)importPaths
	       exclusionPatterns:(NSArray<NSString *> *)exclusionPatterns
	                completion:(void (^)(IMLibrary *, NSError *))completion {
	if (name.length == 0 || ownerId.length == 0) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"A library name and owner are required.")}]);
		return;
	}
	NSMutableDictionary *body = [@{ @"name": name, @"ownerId": ownerId } mutableCopy];
	if (importPaths) body[@"importPaths"] = importPaths;
	if (exclusionPatterns) body[@"exclusionPatterns"] = exclusionPatterns;
	[[IMApiClient shared] POST:@"/libraries" body:body completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		completion([json isKindOfClass:[NSDictionary class]] ? [[IMLibrary alloc] initWithDictionary:json] : nil,
		           [json isKindOfClass:[NSDictionary class]] ? nil : IMLibraryMalformedResponse());
	}];
}

+ (void)updateLibraryId:(NSString *)libraryId
	                 name:(NSString *)name
	           importPaths:(NSArray<NSString *> *)importPaths
	    exclusionPatterns:(NSArray<NSString *> *)exclusionPatterns
	             completion:(void (^)(IMLibrary *, NSError *))completion {
	if (libraryId.length == 0) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"A library ID is required.")}]);
		return;
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	if (name) body[@"name"] = name;
	if (importPaths) body[@"importPaths"] = importPaths;
	if (exclusionPatterns) body[@"exclusionPatterns"] = exclusionPatterns;
	if (body.count == 0) { completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"Choose a library setting to update.")}]); return; }
	NSString *path = [NSString stringWithFormat:@"/libraries/%@", libraryId];
	[[IMApiClient shared] PUT:path body:body completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		completion([json isKindOfClass:[NSDictionary class]] ? [[IMLibrary alloc] initWithDictionary:json] : nil,
		           [json isKindOfClass:[NSDictionary class]] ? nil : IMLibraryMalformedResponse());
	}];
}

+ (void)deleteLibraryId:(NSString *)libraryId completion:(void (^)(BOOL, NSError *))completion {
	if (libraryId.length == 0) { completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"A library ID is required.")}]); return; }
	[[IMApiClient shared] DELETE:[NSString stringWithFormat:@"/libraries/%@", libraryId] body:nil completion:^(id json, NSError *error) { completion(error == nil, error); }];
}

+ (void)scanLibraryId:(NSString *)libraryId completion:(void (^)(BOOL, NSError *))completion {
	if (libraryId.length == 0) { completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"A library ID is required.")}]); return; }
	[[IMApiClient shared] POST:[NSString stringWithFormat:@"/libraries/%@/scan", libraryId] body:nil completion:^(id json, NSError *error) { completion(error == nil, error); }];
}

+ (void)statisticsForLibraryId:(NSString *)libraryId completion:(void (^)(IMLibraryStats *, NSError *))completion {
	if (libraryId.length == 0) { completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"A library ID is required.")}]); return; }
	[[IMApiClient shared] GET:[NSString stringWithFormat:@"/libraries/%@/statistics", libraryId] query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		completion([json isKindOfClass:[NSDictionary class]] ? [[IMLibraryStats alloc] initWithDictionary:json] : nil,
		           [json isKindOfClass:[NSDictionary class]] ? nil : IMLibraryMalformedResponse());
	}];
}

+ (void)validateLibraryId:(NSString *)libraryId importPaths:(NSArray<NSString *> *)importPaths completion:(void (^)(NSArray<IMLibraryValidation *> *, NSError *))completion {
	if (libraryId.length == 0) { completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"A library ID is required.")}]); return; }
	[[IMApiClient shared] POST:[NSString stringWithFormat:@"/libraries/%@/validate", libraryId] body:@{ @"importPaths": importPaths ?: @[] } completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSDictionary class]]) { completion(nil, IMLibraryMalformedResponse()); return; }
		id raw = ((NSDictionary *)json)[@"importPaths"];
		NSMutableArray *results = [NSMutableArray array];
		if ([raw isKindOfClass:[NSArray class]]) for (id value in (NSArray *)raw) if ([value isKindOfClass:[NSDictionary class]]) [results addObject:[[IMLibraryValidation alloc] initWithDictionary:value]];
		completion(results, nil);
	}];
}

@end
