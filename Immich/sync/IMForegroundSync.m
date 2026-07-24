#import "IMForegroundSync.h"
#import "IMPhotoLibrary.h"
#import "IMAssetApi.h"
#import "IMPrefs.h"
#import "common.h"
#import <Photos/Photos.h>
#import <Network/Network.h>

NSErrorDomain const IMForegroundSyncErrorDomain = @"IMForegroundSyncErrorDomain";

typedef NS_ENUM(NSInteger, IMForegroundSyncErrorCode) {
	IMForegroundSyncErrorPhotoAccessDenied = 1,
	IMForegroundSyncErrorNoWifi = 2,
	IMForegroundSyncErrorCancelled = 3,
};

static const NSUInteger kBatchSize = 20;
static const int64_t kAutoCheckDebounceSeconds = 3;

static NSString *IMDeviceAssetIdFromItemId(NSString *itemId) {
	NSRange hash = [itemId rangeOfString:@"#"];
	return hash.location == NSNotFound ? itemId : [itemId substringToIndex:hash.location];
}

static NSString *IMISO8601StringFromDate(NSDate *_Nullable date) {
	static NSISO8601DateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSISO8601DateFormatter alloc] init];
		formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	});
	return [formatter stringFromDate:date ?: [NSDate date]];
}

@interface IMForegroundSync () <PHPhotoLibraryChangeObserver>
@property (nonatomic) dispatch_queue_t workQueue;
@property (nonatomic) nw_path_monitor_t pathMonitor;
@property (atomic) BOOL wifiAvailable;
@property (nonatomic) dispatch_block_t pendingAutoCheck;

@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, readwrite) NSInteger syncedCount;
@property (nonatomic, readwrite) NSInteger pendingUploadCount;

@property (nonatomic, strong, nullable) NSArray<PHAsset *> *assets;
@property (nonatomic) NSUInteger nextIndex;
@property (nonatomic) NSInteger checkedCount;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSString *> *> *batchItems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PHAsset *> *batchAssetsById;
@property (nonatomic, copy, nullable) void (^progressBlock)(NSInteger checked, NSInteger total);
@property (nonatomic, copy, nullable) void (^completionBlock)(NSError *_Nullable error);
@property (nonatomic) BOOL cancelled;
@end

@implementation IMForegroundSync

+ (instancetype)shared {
	static IMForegroundSync *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMForegroundSync alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_workQueue = dispatch_queue_create("com.lns.immich-ios-14.sync", DISPATCH_QUEUE_SERIAL);
		_wifiAvailable = YES; 

		_pathMonitor = nw_path_monitor_create();
		nw_path_monitor_set_queue(_pathMonitor, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
		__weak typeof(self) weakSelf = self;
		nw_path_monitor_set_update_handler(_pathMonitor, ^(nw_path_t path) {
			weakSelf.wifiAvailable = nw_path_get_status(path) == nw_path_status_satisfied &&
			    nw_path_uses_interface_type(path, nw_interface_type_wifi);
		});
		nw_path_monitor_start(_pathMonitor);

		[[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                          selector:@selector(appDidBecomeActive)
		                                              name:UIApplicationDidBecomeActiveNotification
		                                            object:nil];
	}
	return self;
}

#pragma mark - Auto-trigger (backupEnabled only)

- (void)appDidBecomeActive {
	[self triggerAutoCheckIfEnabled];
}

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self triggerAutoCheckIfEnabled];
	});
}

- (void)triggerAutoCheckIfEnabled {
	if (!IMPrefs.shared.backupEnabled || self.running) {
		return;
	}
	if (self.pendingAutoCheck) {
		dispatch_block_cancel(self.pendingAutoCheck);
	}
	__weak typeof(self) weakSelf = self;
	dispatch_block_t block = dispatch_block_create(0, ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || strongSelf.running || !IMPrefs.shared.backupEnabled) {
			return;
		}
		[strongSelf startWithProgress:^(NSInteger checked, NSInteger total) {
		    }
		                    completion:^(NSError *_Nullable error) {
		    }];
	});
	self.pendingAutoCheck = block;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kAutoCheckDebounceSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), block);
}

#pragma mark - Run

- (void)startWithProgress:(void (^)(NSInteger checked, NSInteger total))progress
                completion:(void (^)(NSError *_Nullable error))completion {
	if (self.running) {
		return;
	}
	self.running = YES;
	self.cancelled = NO;
	self.checkedCount = 0;
	self.syncedCount = 0;
	self.pendingUploadCount = 0;
	self.progressBlock = progress;
	self.completionBlock = completion;

	if (IMPrefs.shared.wifiOnlyUpload && !self.wifiAvailable) {
		[self finishWithError:[NSError errorWithDomain:IMForegroundSyncErrorDomain
		                                            code:IMForegroundSyncErrorNoWifi
		                                        userInfo:@{ NSLocalizedDescriptionKey: _(@"Waiting for Wi-Fi (Preferences > Wi-Fi Only Upload is on).") }]];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[IMPhotoLibrary shared] requestAuthorizationWithCompletion:^(BOOL granted) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		if (!granted) {
			[strongSelf finishWithError:[NSError errorWithDomain:IMForegroundSyncErrorDomain
			                                                  code:IMForegroundSyncErrorPhotoAccessDenied
			                                              userInfo:@{ NSLocalizedDescriptionKey: _(@"Photo library access denied.") }]];
			return;
		}
		dispatch_async(strongSelf.workQueue, ^{
			NSArray<PHAsset *> *assets = [[IMPhotoLibrary shared] allAssets];
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) s2 = weakSelf;
				if (!s2) {
					return;
				}
				s2.assets = assets;
				s2.nextIndex = 0;
				s2.batchItems = [NSMutableArray array];
				s2.batchAssetsById = [NSMutableDictionary dictionary];
				[s2 processNext];
			});
		});
	}];
}

- (void)cancel {
	self.cancelled = YES;
}

- (void)finishWithError:(nullable NSError *)error {
	self.running = NO;
	void (^completion)(NSError *_Nullable) = self.completionBlock;
	self.completionBlock = nil;
	self.progressBlock = nil;
	if (completion) {
		completion(error);
	}
}

#pragma mark - Sequential scan

- (void)processNext {
	if (self.cancelled) {
		[self finishWithError:[NSError errorWithDomain:IMForegroundSyncErrorDomain
		                                            code:IMForegroundSyncErrorCancelled
		                                        userInfo:@{ NSLocalizedDescriptionKey: _(@"Cancelled.") }]];
		return;
	}

	if (self.nextIndex >= self.assets.count) {
		if (self.batchItems.count > 0) {
			__weak typeof(self) weakSelf = self;
			[self flushBatchThen:^{
				[weakSelf finishWithError:nil];
			}];
		} else {
			[self finishWithError:nil];
		}
		return;
	}

	PHAsset *asset = self.assets[self.nextIndex];
	self.nextIndex++;

	NSString *deviceAssetId = asset.localIdentifier;
	if ([[IMDatabase shared] syncStateForDeviceAssetId:deviceAssetId] == IMSyncStateSynced) {
		self.checkedCount++;
		self.syncedCount++;
		[self reportProgress];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self processNext];
		});
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[IMPhotoLibrary shared] checksumsForAsset:asset
	                                 completion:^(NSArray<NSString *> *_Nullable checksums, NSString *_Nullable filename, NSError *_Nullable error) {
		    dispatch_async(dispatch_get_main_queue(), ^{
			    typeof(self) strongSelf = weakSelf;
			    if (!strongSelf) {
				    return;
			    }
			    if (checksums.count > 0) {
				    [checksums enumerateObjectsUsingBlock:^(NSString *checksum, NSUInteger idx, BOOL *stop) {
					    NSString *itemId = checksums.count > 1
					        ? [NSString stringWithFormat:@"%@#%lu", deviceAssetId, (unsigned long)idx]
					        : deviceAssetId;
					    [strongSelf.batchItems addObject:@{ @"id": itemId, @"checksum": checksum }];
				    }];
				    strongSelf.batchAssetsById[deviceAssetId] = asset;
			    } else {
				    NSLog(@"IMForegroundSync: checksum failed for %@: %@", deviceAssetId, error);
				    strongSelf.checkedCount++;
			    }

			    if (strongSelf.batchItems.count >= kBatchSize) {
				    [strongSelf flushBatchThen:^{
					    [strongSelf processNext];
				    }];
			    } else {
				    [strongSelf processNext];
			    }
		    });
	    }];
}

- (void)flushBatchThen:(void (^)(void))next {
	NSArray<NSDictionary<NSString *, NSString *> *> *items = self.batchItems;
	NSDictionary<NSString *, PHAsset *> *assetsById = self.batchAssetsById;
	self.batchItems = [NSMutableArray array];
	self.batchAssetsById = [NSMutableDictionary dictionary];

	__weak typeof(self) weakSelf = self;
	[IMAssetApi bulkUploadCheckWithItems:items
	                           completion:^(NSDictionary<NSString *, NSString *> *_Nullable actionsById,
	                                        NSDictionary<NSString *, NSString *> *_Nullable matchedAssetIdsById,
	                                        NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }

		    NSMutableOrderedSet<NSString *> *orderedAssetIds = [NSMutableOrderedSet orderedSet];
		    NSMutableDictionary<NSString *, NSNumber *> *matchedByAsset = [NSMutableDictionary dictionary];
		    NSMutableDictionary<NSString *, NSString *> *matchedAssetIdByAsset = [NSMutableDictionary dictionary];

		    for (NSDictionary<NSString *, NSString *> *item in items) {
			    NSString *itemId = item[@"id"];
			    NSString *deviceAssetId = IMDeviceAssetIdFromItemId(itemId);
			    [orderedAssetIds addObject:deviceAssetId];

			    NSString *action = actionsById[itemId];
			    if ([action isEqualToString:@"reject"]) {
				    matchedByAsset[deviceAssetId] = @YES;
				    NSString *assetId = matchedAssetIdsById[itemId];
				    if (assetId) {
					    matchedAssetIdByAsset[deviceAssetId] = assetId;
				    }
			    } else {
				    if (![action isEqualToString:@"accept"]) {
					    NSLog(@"IMForegroundSync: bulk-upload-check missing/unknown action for %@: %@", itemId, error);
				    }
				    if (!matchedByAsset[deviceAssetId]) {
					    matchedByAsset[deviceAssetId] = @NO;
				    }
			    }
		    }

		    NSMutableArray<NSString *> *needsUpload = [NSMutableArray array];
		    for (NSString *deviceAssetId in orderedAssetIds) {
			    strongSelf.checkedCount++;
			    if ([matchedByAsset[deviceAssetId] boolValue]) {
				    [[IMDatabase shared] setSyncState:IMSyncStateSynced
				                               assetId:matchedAssetIdByAsset[deviceAssetId]
				                     forDeviceAssetId:deviceAssetId];
				    strongSelf.syncedCount++;
			    } else if (IMPrefs.shared.backupEnabled) {
				    [[IMDatabase shared] setSyncState:IMSyncStateUploading assetId:nil forDeviceAssetId:deviceAssetId];
				    [needsUpload addObject:deviceAssetId];
			    } else {
				    [[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
				    strongSelf.pendingUploadCount++;
			    }
		    }

		    [strongSelf uploadDeviceAssetIds:needsUpload
		                          assetsById:assetsById
		                                then:^{
			    [strongSelf reportProgress];
			    next();
		    }];
	    }];
}

- (void)uploadDeviceAssetIds:(NSArray<NSString *> *)deviceAssetIds
                    assetsById:(NSDictionary<NSString *, PHAsset *> *)assetsById
                          then:(void (^)(void))then {
	if (deviceAssetIds.count == 0 || self.cancelled) {
		then();
		return;
	}

	NSString *deviceAssetId = deviceAssetIds.firstObject;
	NSArray<NSString *> *rest = [deviceAssetIds subarrayWithRange:NSMakeRange(1, deviceAssetIds.count - 1)];
	PHAsset *asset = assetsById[deviceAssetId];
	if (!asset) {
		[[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
		self.pendingUploadCount++;
		[self uploadDeviceAssetIds:rest assetsById:assetsById then:then];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[[IMPhotoLibrary shared] originalDataForAsset:asset
	                                    completion:^(NSData *_Nullable data, NSString *_Nullable filename, NSError *_Nullable error) {
		    dispatch_async(dispatch_get_main_queue(), ^{
			    typeof(self) strongSelf = weakSelf;
			    if (!strongSelf) {
				    return;
			    }
			    if (!data || !filename) {
				    NSLog(@"IMForegroundSync: read failed for upload %@: %@", deviceAssetId, error);
				    [[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
				    strongSelf.pendingUploadCount++;
				    [strongSelf uploadDeviceAssetIds:rest assetsById:assetsById then:then];
				    return;
			    }
			    [IMAssetApi uploadAssetData:data
			                        filename:filename
			                   fileCreatedAt:IMISO8601StringFromDate(asset.creationDate)
			                  fileModifiedAt:IMISO8601StringFromDate(asset.modificationDate ?: asset.creationDate)
			                      completion:^(NSString *_Nullable uploadedAssetId, NSError *_Nullable uploadError) {
				    typeof(self) s2 = weakSelf;
				    if (!s2) {
					    return;
				    }
				    if (uploadedAssetId) {
					    [[IMDatabase shared] setSyncState:IMSyncStateSynced assetId:uploadedAssetId forDeviceAssetId:deviceAssetId];
					    s2.syncedCount++;
				    } else {
					    NSLog(@"IMForegroundSync: upload failed for %@: %@", deviceAssetId, uploadError);
					    [[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
					    s2.pendingUploadCount++;
				    }
				    [s2 uploadDeviceAssetIds:rest assetsById:assetsById then:then];
			    }];
		    });
	    }];
}

- (void)reportProgress {
	if (self.progressBlock) {
		self.progressBlock(self.checkedCount, self.assets.count);
	}
}

@end
