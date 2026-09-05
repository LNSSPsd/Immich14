#import "IMFolderApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMFolderError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The server returned an invalid folder response.")}];
}

@implementation IMFolderApi

+ (nullable NSURLSessionTask *)uniquePathsWithCompletion:(void (^)(NSArray<NSString *> *, NSError *))completion {
	return [[IMApiClient shared] GET:@"/view/folder/unique-paths" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSArray class]]) { completion(nil, IMFolderError(nil)); return; }
		NSMutableArray<NSString *> *paths = [NSMutableArray array];
		for (id value in (NSArray *)json) {
			if (![value isKindOfClass:[NSString class]]) { completion(nil, IMFolderError(nil)); return; }
			NSString *path = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
			if (path.length == 0) { completion(nil, IMFolderError(nil)); return; }
			if (![paths containsObject:path]) [paths addObject:path];
		}
		[paths sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
		completion(paths, nil);
	}];
}

+ (nullable NSURLSessionTask *)assetsForOriginalPath:(NSString *)path
                                          completion:(void (^)(NSArray<IMAsset *> *, NSError *))completion {
	if (![path isKindOfClass:[NSString class]] || path.length == 0) {
		NSError *error = IMFolderError(_(@"A folder path is required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	return [[IMApiClient shared] GET:@"/view/folder" query:@{ @"path": path } completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSArray class]]) { completion(nil, IMFolderError(nil)); return; }
		NSArray<IMAsset *> *assets = [IMAsset assetsWithResponseArray:json];
		if (assets.count != [(NSArray *)json count]) { completion(nil, IMFolderError(nil)); return; }
		completion(assets, nil);
	}];
}

@end
