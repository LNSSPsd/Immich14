#import "IMPhotoLibrary.h"
#import <CommonCrypto/CommonDigest.h>

@implementation IMPhotoLibrary

+ (instancetype)shared {
	static IMPhotoLibrary *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMPhotoLibrary alloc] init];
	});
	return shared;
}

- (void)requestAuthorizationWithCompletion:(void (^)(BOOL granted))completion {
	[PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite
	                                            handler:^(PHAuthorizationStatus status) {
		    BOOL granted = (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited);
		    dispatch_async(dispatch_get_main_queue(), ^{
			    completion(granted);
		    });
	    }];
}

- (NSInteger)totalAssetCount {
	PHFetchOptions *options = [[PHFetchOptions alloc] init];
	return (NSInteger)[PHAsset fetchAssetsWithOptions:options].count;
}

- (NSArray<PHAsset *> *)allAssets {
	PHFetchOptions *options = [[PHFetchOptions alloc] init];
	options.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES] ];
	PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithOptions:options];
	NSMutableArray<PHAsset *> *assets = [NSMutableArray arrayWithCapacity:result.count];
	[result enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
		[assets addObject:asset];
	}];
	return assets;
}

- (NSArray<PHAssetResource *> *)contentResourcesForAsset:(PHAsset *)asset {
	NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
	PHAssetResource *original = nil;
	PHAssetResource *current = nil;
	for (PHAssetResource *resource in resources) {
		if (resource.type == PHAssetResourceTypePhoto || resource.type == PHAssetResourceTypeVideo) {
			original = resource;
		} else if (resource.type == PHAssetResourceTypeFullSizePhoto || resource.type == PHAssetResourceTypeFullSizeVideo) {
			current = resource;
		}
	}
	NSMutableArray<PHAssetResource *> *picked = [NSMutableArray array];
	if (original) {
		[picked addObject:original];
	}
	if (current) {
		[picked addObject:current];
	}
	if (picked.count == 0 && resources.firstObject) {
		[picked addObject:resources.firstObject];
	}
	return picked;
}

- (void)checksumForResource:(PHAssetResource *)resource
                  completion:(void (^)(NSString *_Nullable checksumHex, NSError *_Nullable error))completion {
	__block CC_SHA1_CTX ctx;
	CC_SHA1_Init(&ctx);

	PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
	options.networkAccessAllowed = YES; 

	[[PHAssetResourceManager defaultManager]
	    requestDataForAssetResource:resource
	                         options:options
	            dataReceivedHandler:^(NSData *_Nonnull data) {
		    CC_SHA1_Update(&ctx, data.bytes, (CC_LONG)data.length);
	    }
	               completionHandler:^(NSError *_Nullable error) {
		    if (error) {
			    completion(nil, error);
			    return;
		    }
		    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
		    CC_SHA1_Final(digest, &ctx);
		    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
		    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
			    [hex appendFormat:@"%02x", digest[i]];
		    }
		    completion(hex, nil);
	    }];
}

- (void)checksumsForAsset:(PHAsset *)asset
                completion:(void (^)(NSArray<NSString *> *_Nullable checksums,
                                      NSString *_Nullable filename,
                                      NSError *_Nullable error))completion {
	NSArray<PHAssetResource *> *resources = [self contentResourcesForAsset:asset];
	if (resources.count == 0) {
		completion(nil, nil, [NSError errorWithDomain:@"IMPhotoLibrary"
		                                          code:1
		                                      userInfo:@{ NSLocalizedDescriptionKey: @"Asset has no resource" }]);
		return;
	}

	NSString *filename = resources.firstObject.originalFilename;
	NSMutableArray<NSString *> *checksums = [NSMutableArray arrayWithCapacity:resources.count];
	dispatch_queue_t collectQueue = dispatch_queue_create("com.lns.immich-ios-14.photolib.collect", DISPATCH_QUEUE_SERIAL);
	dispatch_group_t group = dispatch_group_create();

	for (PHAssetResource *resource in resources) {
		dispatch_group_enter(group);
		[self checksumForResource:resource
		                completion:^(NSString *_Nullable checksumHex, NSError *_Nullable error) {
			    dispatch_async(collectQueue, ^{
				    if (checksumHex) {
					    [checksums addObject:checksumHex];
				    } else {
					    NSLog(@"IMPhotoLibrary: checksum failed for a resource of %@: %@", asset.localIdentifier, error);
				    }
				    dispatch_group_leave(group);
			    });
		    }];
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		if (checksums.count == 0) {
			completion(nil, nil, [NSError errorWithDomain:@"IMPhotoLibrary"
			                                          code:2
			                                      userInfo:@{ NSLocalizedDescriptionKey: @"All resource checksums failed" }]);
			return;
		}
		completion(checksums, filename, nil);
	});
}

- (nullable PHAssetResource *)uploadResourceForAsset:(PHAsset *)asset {
	NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
	PHAssetResource *original = nil;
	PHAssetResource *current = nil;
	for (PHAssetResource *resource in resources) {
		if (resource.type == PHAssetResourceTypePhoto || resource.type == PHAssetResourceTypeVideo) {
			original = resource;
		} else if (resource.type == PHAssetResourceTypeFullSizePhoto || resource.type == PHAssetResourceTypeFullSizeVideo) {
			current = resource;
		}
	}
	return current ?: original ?: resources.firstObject;
}

- (void)pairedLivePhotoVideoForAsset:(PHAsset *)asset
                           completion:(void (^)(NSData *_Nullable data,
                                                 NSString *_Nullable filename,
                                                 NSError *_Nullable error))completion {
	if (!(asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive)) {
		completion(nil, nil, nil);
		return;
	}
	NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];
	PHAssetResource *original = nil;
	PHAssetResource *current = nil;
	for (PHAssetResource *resource in resources) {
		if (resource.type == PHAssetResourceTypePairedVideo) {
			original = resource;
		} else if (resource.type == PHAssetResourceTypeFullSizePairedVideo) {
			current = resource;
		}
	}
	PHAssetResource *resource = current ?: original;
	if (!resource) {
		completion(nil, nil, nil);
		return;
	}

	NSMutableData *buffer = [NSMutableData data];
	PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
	options.networkAccessAllowed = YES;
	NSString *filename = resource.originalFilename;

	[[PHAssetResourceManager defaultManager]
	    requestDataForAssetResource:resource
	                         options:options
	            dataReceivedHandler:^(NSData *_Nonnull data) {
		    [buffer appendData:data];
	    }
	               completionHandler:^(NSError *_Nullable error) {
		    if (error) {
			    completion(nil, nil, error);
			    return;
		    }
		    completion(buffer, filename, nil);
	    }];
}

- (void)originalDataForAsset:(PHAsset *)asset
                   completion:(void (^)(NSData *_Nullable data,
                                         NSString *_Nullable filename,
                                         NSError *_Nullable error))completion {
	PHAssetResource *resource = [self uploadResourceForAsset:asset];
	if (!resource) {
		completion(nil, nil, [NSError errorWithDomain:@"IMPhotoLibrary"
		                                          code:3
		                                      userInfo:@{ NSLocalizedDescriptionKey: @"Asset has no resource" }]);
		return;
	}

	NSMutableData *buffer = [NSMutableData data];
	PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
	options.networkAccessAllowed = YES;
	NSString *filename = resource.originalFilename;

	[[PHAssetResourceManager defaultManager]
	    requestDataForAssetResource:resource
	                         options:options
	            dataReceivedHandler:^(NSData *_Nonnull data) {
		    [buffer appendData:data];
	    }
	               completionHandler:^(NSError *_Nullable error) {
		    if (error) {
			    completion(nil, nil, error);
			    return;
		    }
		    completion(buffer, filename, nil);
	    }];
}

@end
