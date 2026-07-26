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

@interface IMAlbumAssetsTask ()
@property (atomic) BOOL cancelled;
@property (atomic, strong, nullable) NSURLSessionTask *currentTask;
@end

@implementation IMAlbumAssetsTask

- (void)cancel {
	self.cancelled = YES;
	[self.currentTask cancel];
}

@end

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

static const NSInteger kIMAlbumAssetsPageSize = 1000;
static const NSInteger kIMAlbumAssetsMaxPages = 100;

+ (IMAlbumAssetsTask *)assetsInAlbumId:(NSString *)albumId
                                  order:(nullable NSString *)order
                             completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	IMAlbumAssetsTask *task = [[IMAlbumAssetsTask alloc] init];
	[self fetchAlbumAssetsPage:1
	                   albumId:albumId
	                     order:order
	               accumulated:[NSMutableArray array]
	                      task:task
	                completion:completion];
	return task;
}

+ (void)fetchAlbumAssetsPage:(NSInteger)page
                     albumId:(NSString *)albumId
                       order:(nullable NSString *)order
                 accumulated:(NSMutableArray<IMAsset *> *)accumulated
                        task:(IMAlbumAssetsTask *)task
                  completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	if (task.cancelled) {
		return;
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
		@"albumIds": @[ albumId ],
		@"page": @(page),
		@"size": @(kIMAlbumAssetsPageSize),
	}];
	if (order.length > 0) {
		body[@"order"] = order;
	}
	task.currentTask = [[IMApiClient shared] POST:@"/search/metadata"
	                                          body:body
	                                    completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (task.cancelled) {
			    return;
		    }
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    id assetsValue = IMValueOrNil(((NSDictionary *)json)[@"assets"]);
		    NSDictionary *assetsDict = [assetsValue isKindOfClass:[NSDictionary class]] ? assetsValue : nil;
		    id items = IMValueOrNil(assetsDict[@"items"]);
		    NSArray<IMAsset *> *pageAssets = [IMAsset assetsWithResponseArray:[items isKindOfClass:[NSArray class]] ? items : @[]];
		    [accumulated addObjectsFromArray:pageAssets];
		    id nextPage = IMValueOrNil(assetsDict[@"nextPage"]);
		    NSInteger next = 0;
		    if ([nextPage isKindOfClass:[NSString class]] || [nextPage isKindOfClass:[NSNumber class]]) {
			    next = [nextPage integerValue];
		    }
		    if (next > page && page < kIMAlbumAssetsMaxPages && pageAssets.count > 0) {
			    [self fetchAlbumAssetsPage:next
			                       albumId:albumId
			                         order:order
			                   accumulated:accumulated
			                          task:task
			                    completion:completion];
			    return;
		    }
		    completion([accumulated copy], nil);
	    }];
}

+ (nullable NSURLSessionTask *)assetsInAlbumId:(NSString *)albumId
                                    completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	[self assetsInAlbumId:albumId order:nil completion:completion];
	return nil;
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

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
          toAlbumId:(NSString *)albumId
 detailedCompletion:(void (^)(NSInteger added, NSInteger duplicates, NSInteger failed, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/albums/%@/assets", albumId];
	[[IMApiClient shared] PUT:path
	                      body:@{ @"ids": assetIds }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSArray class]]) {
			    completion(0, 0, (NSInteger)assetIds.count, error);
			    return;
		    }
		    NSInteger added = 0, duplicates = 0, failed = 0;
		    for (NSDictionary *entry in (NSArray *)json) {
			    if (![entry isKindOfClass:[NSDictionary class]]) {
				    failed++;
				    continue;
			    }
			    if ([entry[@"success"] isEqual:@YES]) {
				    added++;
				    continue;
			    }
			    id reason = IMValueOrNil(entry[@"error"]);
			    if ([reason isKindOfClass:[NSString class]] && [reason isEqualToString:@"duplicate"]) {
				    duplicates++;
			    } else {
				    failed++;
			    }
		    }
		    if (added > 0) {
			    [self adjustCachedAssetCountForAlbumId:albumId delta:added];
		    }
		    completion(added, duplicates, failed, nil);
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

#pragma mark - Cache maintenance

+ (void)adjustCachedAssetCountForAlbumId:(NSString *)albumId delta:(NSInteger)delta {
	if (delta == 0 || sCachedAlbums.count == 0) {
		return;
	}
	NSMutableArray<IMAlbum *> *updated = [sCachedAlbums mutableCopy];
	for (NSUInteger i = 0; i < updated.count; i++) {
		if ([updated[i].albumId isEqualToString:albumId]) {
			updated[i] = [updated[i] albumByAdjustingAssetCount:delta];
			break;
		}
	}
	sCachedAlbums = updated;
}

@end
