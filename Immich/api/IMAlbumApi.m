#import "IMAlbumApi.h"
#import "IMApiClient.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMAllBulkIdsSucceeded(id json) {
	if (![json isKindOfClass:[NSArray class]]) {
		return NO;
	}
	for (NSDictionary *entry in (NSArray *)json) {
		if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"success"] isEqual:@YES]) {
			return NO;
		}
	}
	return YES;
}

@implementation IMAlbumApi

static NSArray<IMAlbum *> *sCachedAlbums;

#pragma mark - Album CRUD

+ (void)allAlbumsWithCompletion:(void (^)(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/albums"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSArray class]]) {
			    completion(nil, error);
			    return;
		    }
		    NSArray<IMAlbum *> *albums = [IMAlbum albumsWithArray:(NSArray *)json];
		    sCachedAlbums = albums;
		    completion(albums, nil);
	    }];
}

+ (NSArray<IMAlbum *> *)cachedAlbums {
	return sCachedAlbums ?: @[];
}

+ (void)createAlbumWithName:(NSString *)name
                   completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion {
	[[IMApiClient shared] POST:@"/albums"
	                       body:@{ @"albumName": name }
	                 completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    completion([IMAlbum albumWithDictionary:json], nil);
	    }];
}

+ (void)renameAlbumId:(NSString *)albumId
                   name:(NSString *)name
             completion:(void (^)(IMAlbum *_Nullable album, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/albums/%@", albumId];
	[[IMApiClient shared] PATCH:path
	                        body:@{ @"albumName": name }
	                  completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    completion([IMAlbum albumWithDictionary:json], nil);
	    }];
}

+ (void)deleteAlbumId:(NSString *)albumId completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/albums/%@", albumId];
	[[IMApiClient shared] DELETE:path
	                         body:nil
	                   completion:^(id _Nullable json, NSError *_Nullable error) {
		    completion(error == nil, error);
	    }];
}

#pragma mark - Contents

+ (nullable NSURLSessionTask *)assetsInAlbumId:(NSString *)albumId
                                    completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [[IMApiClient shared] POST:@"/search/metadata"
	                              body:@{ @"albumIds": @[ albumId ] }
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    id assetsValue = IMValueOrNil(((NSDictionary *)json)[@"assets"]);
		    NSDictionary *assetsDict = [assetsValue isKindOfClass:[NSDictionary class]] ? assetsValue : nil;
		    id items = IMValueOrNil(assetsDict[@"items"]);
		    completion([IMAsset assetsWithResponseArray:[items isKindOfClass:[NSArray class]] ? items : @[]], nil);
	    }];
}

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
          toAlbumId:(NSString *)albumId
         completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/albums/%@/assets", albumId];
	[[IMApiClient shared] PUT:path
	                      body:@{ @"ids": assetIds }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    completion(!error && IMAllBulkIdsSucceeded(json), error);
	    }];
}

+ (void)removeAssetIds:(NSArray<NSString *> *)assetIds
          fromAlbumId:(NSString *)albumId
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/albums/%@/assets", albumId];
	[[IMApiClient shared] DELETE:path
	                         body:@{ @"ids": assetIds }
	                   completion:^(id _Nullable json, NSError *_Nullable error) {
		    completion(!error && IMAllBulkIdsSucceeded(json), error);
	    }];
}

@end
