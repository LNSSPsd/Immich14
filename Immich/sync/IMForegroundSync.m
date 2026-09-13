#import "IMForegroundSync.h"
#import "IMPhotoLibrary.h"
#import "IMAssetApi.h"
#import "IMBackupQueue.h"
#import "IMBackupDaemon.h"
#import "IMPrefs.h"
#import "IMSession.h"
#import "common.h"
#import <Photos/Photos.h>
#import <Network/Network.h>

NSErrorDomain const IMForegroundSyncErrorDomain = @"IMForegroundSyncErrorDomain";
NSNotificationName const IMForegroundSyncProgressNotification = @"IMForegroundSyncProgressNotification";
NSNotificationName const IMForegroundSyncDidFinishNotification = @"IMForegroundSyncDidFinishNotification";
NSString *const IMForegroundSyncErrorUserInfoKey = @"error";
NSString *const IMForegroundSyncSessionFingerprintUserInfoKey = @"sessionFingerprint";

typedef NS_ENUM(NSInteger, IMForegroundSyncErrorCode) {
	IMForegroundSyncErrorPhotoAccessDenied = 1,
	IMForegroundSyncErrorNoWifi = 2,
	IMForegroundSyncErrorCancelled = 3,
	IMForegroundSyncErrorCheckFailed = 4,
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

static NSString *IMSyncSessionFingerprint(void) {
	IMSession *session = IMSession.shared;
	return [NSString stringWithFormat:@"%@|%@|%ld|%lu",
	                                session.baseURL.absoluteString ?: @"",
	                                session.userId ?: @"",
	                                (long)session.authKind,
	                                (unsigned long)session.accessToken.hash];
}

static NSError *IMSyncSessionChangedError(void) {
	return [NSError errorWithDomain:IMForegroundSyncErrorDomain
	                            code:IMForegroundSyncErrorCancelled
	                        userInfo:@{ NSLocalizedDescriptionKey: _(@"Session changed — sync cancelled.") }];
}

@interface IMForegroundSync () <PHPhotoLibraryChangeObserver>
@property (nonatomic) dispatch_queue_t workQueue;
@property (nonatomic) nw_path_monitor_t pathMonitor;
@property (atomic) BOOL wifiAvailable;
@property (nonatomic) dispatch_block_t pendingAutoCheck;

@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@property (nonatomic, readwrite) NSInteger syncedCount;
@property (nonatomic, readwrite) NSInteger pendingUploadCount;
@property (nonatomic, readwrite) NSInteger uploadedCount;
@property (nonatomic, readwrite) NSInteger totalCount;
@property (nonatomic, readwrite) NSInteger checkedCount;

@property (nonatomic, strong, nullable) PHFetchResult<PHAsset *> *assetFetchResult;
@property (nonatomic) NSUInteger nextIndex;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingChangedBuckets;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, NSString *> *> *batchItems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, PHAsset *> *batchAssetsById;
@property (nonatomic, copy, nullable) void (^progressBlock)(NSInteger checked, NSInteger total);
@property (nonatomic, copy, nullable) void (^completionBlock)(NSError *_Nullable error);
@property (nonatomic) BOOL cancelled;
@property (nonatomic) BOOL ignoreRetryBackoff;
@property (nonatomic, copy, nullable) NSString *runSessionFingerprint;
@property (nonatomic) BOOL uploadsEnabledForRun;
@property (nonatomic, strong, nullable) NSObject *runToken;
@property (nonatomic, strong, nullable) NSURLSessionTask *activeNetworkTask;
- (BOOL)ensureCurrentRunToken:(NSObject *)token;
- (BOOL)ensureMutableRunToken:(NSObject *)token;
- (void)processNextForToken:(NSObject *)token;
- (void)flushBatchThen:(void (^)(void))next token:(NSObject *)token;
- (void)uploadDeviceAssetIds:(NSArray<NSString *> *)deviceAssetIds
                    assetsById:(NSDictionary<NSString *, PHAsset *> *)assetsById
                          then:(void (^)(void))then
                         token:(NSObject *)token;
- (void)fetchAndUploadLiveVideoForAsset:(PHAsset *)asset
                          deviceAssetId:(NSString *)deviceAssetId
                             completion:(void (^)(NSString *_Nullable livePhotoVideoId))completion
                                  token:(NSObject *)token;
- (void)streamUploadResource:(PHAssetResource *)resource
                       asset:(PHAsset *)asset
            fallbackFilename:(NSString *)fallbackFilename
            livePhotoVideoId:(nullable NSString *)livePhotoVideoId
                       token:(NSObject *)runToken
                  completion:(void (^)(NSString *_Nullable assetId, NSError *_Nullable error))completion;
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
			    !nw_path_uses_interface_type(path, nw_interface_type_cellular) &&
			    !nw_path_is_expensive(path);
		});
		nw_path_monitor_start(_pathMonitor);

		[[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                          selector:@selector(appDidBecomeActive)
		                                              name:UIApplicationDidBecomeActiveNotification
		                                            object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                          selector:@selector(appWillResignActive)
		                                              name:UIApplicationWillResignActiveNotification
		                                            object:nil];
		[[IMDatabase shared] resetUploadingStates];
	}
	return self;
}

- (void)appWillResignActive {
}

#pragma mark - Auto-trigger (backupEnabled only)

- (void)appDidBecomeActive {
	[self triggerAutoCheckIfEnabled];
}

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
#if IM_TROLLSTORE
	if (IMBackupDaemonIsDaemonProcess()) IMBackupHelperLogEvent(@"photo library changed");
#endif
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
		[IMBackupDaemon.shared runScheduled];
	});
	self.pendingAutoCheck = block;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kAutoCheckDebounceSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), block);
}

#pragma mark - Run

- (void)startWithProgress:(void (^)(NSInteger checked, NSInteger total))progress
                completion:(void (^)(NSError *_Nullable error))completion {
	[self startWithProgress:progress completion:completion ignoreRetryBackoff:NO];
}

- (void)startWithProgress:(void (^)(NSInteger checked, NSInteger total))progress
                completion:(void (^)(NSError *_Nullable error))completion
      ignoreRetryBackoff:(BOOL)ignoreRetryBackoff {
	if (self.running) {
		return;
	}
	self.running = YES;
	self.cancelled = NO;
	self.checkedCount = 0;
	self.totalCount = 0;
	self.syncedCount = 0;
	self.pendingUploadCount = 0;
	self.uploadedCount = 0;
	self.pendingChangedBuckets = [NSMutableSet set];
	self.progressBlock = progress;
	self.completionBlock = completion;
	self.ignoreRetryBackoff = ignoreRetryBackoff;
	[[IMPhotoLibrary shared] prepareForRequests];
	[IMMultipartBodyFile removeStaleFiles]; 
	if (IMBackupDaemonIsDaemonProcess()) {
		[IMPrefs.shared reloadFromPersistence];
		[IMSession.shared reloadFromPersistence];
	}
	self.uploadsEnabledForRun = IMPrefs.shared.backupEnabled;
	self.runSessionFingerprint = IMSyncSessionFingerprint();
	NSString *runSessionFingerprint = [self.runSessionFingerprint copy];
	NSObject *runToken = [[NSObject alloc] init];
	self.runToken = runToken;
	[[IMDatabase shared] resetUploadingStates];

	if (IMPrefs.shared.backupEnabled && IMPrefs.shared.wifiOnlyUpload && !self.wifiAvailable) {
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
		if (![strongSelf ensureCurrentRunToken:runToken]) {
			return;
		}
		if (!granted) {
			[strongSelf finishWithError:[NSError errorWithDomain:IMForegroundSyncErrorDomain
			                                                  code:IMForegroundSyncErrorPhotoAccessDenied
			                                              userInfo:@{ NSLocalizedDescriptionKey: _(@"Photo library access denied.") }]];
			return;
		}
		dispatch_async(strongSelf.workQueue, ^{
			PHFetchResult<PHAsset *> *assetFetchResult = [[IMPhotoLibrary shared] fetchAllAssets];
			if (runSessionFingerprint.length == 0 ||
			    ![runSessionFingerprint isEqualToString:IMSyncSessionFingerprint()]) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[strongSelf ensureCurrentRunToken:runToken];
				});
				return;
			}
			BOOL fullPhotoAuthorization = NO;
			if (@available(iOS 14.0, *)) {
				fullPhotoAuthorization = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite] == PHAuthorizationStatusAuthorized;
			} else {
				fullPhotoAuthorization = [PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusAuthorized;
			}
			if (fullPhotoAuthorization && assetFetchResult) {
				NSMutableSet<NSString *> *currentAssetIDs = [NSMutableSet setWithCapacity:assetFetchResult.count];
				[assetFetchResult enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
					NSString *localIdentifier = asset.localIdentifier;
					if (localIdentifier.length > 0) {
						[currentAssetIDs addObject:localIdentifier];
					}
				}];
				[[IMBackupQueue shared] pruneDeviceAssetIdsNotInSet:currentAssetIDs];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) s2 = weakSelf;
				if (!s2) {
					return;
				}
				if (![s2 ensureCurrentRunToken:runToken]) {
					return;
				}
				s2.assetFetchResult = assetFetchResult;
				s2.totalCount = (NSInteger)assetFetchResult.count;
				s2.nextIndex = 0;
				s2.batchItems = [NSMutableArray array];
				s2.batchAssetsById = [NSMutableDictionary dictionary];
				[s2 processNextForToken:runToken];
			});
		});
	}];
}

- (void)cancel {
	if (![NSThread isMainThread]) {
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf cancel];
		});
		return;
	}
	if (!self.running) {
		return;
	}
	self.cancelled = YES;
	[self.activeNetworkTask cancel];
	self.activeNetworkTask = nil;
	[[IMPhotoLibrary shared] cancelOutstandingRequests];
	NSObject *runToken = self.runToken;
	dispatch_async(dispatch_get_main_queue(), ^{
		if (runToken == self.runToken && self.running) {
			[self processNextForToken:runToken];
		}
	});
}

- (BOOL)ensureCurrentRunToken:(NSObject *)runToken {
	if (IMBackupDaemonIsDaemonProcess()) {
		[IMPrefs.shared reloadFromPersistence];
		[IMSession.shared reloadFromPersistence];
	}
	if (!self.running || runToken != self.runToken) {
		return NO;
	}
	NSString *captured = self.runSessionFingerprint;
	if (captured.length > 0 && [captured isEqualToString:IMSyncSessionFingerprint()]) {
		if (self.uploadsEnabledForRun && !IMPrefs.shared.backupEnabled) {
			self.cancelled = YES;
			[self finishWithError:[NSError errorWithDomain:IMForegroundSyncErrorDomain
			                                            code:IMForegroundSyncErrorCancelled
			                                        userInfo:@{ NSLocalizedDescriptionKey: _(@"Backup disabled — sync cancelled.") }]];
			return NO;
		}
		return YES;
	}
	self.cancelled = YES;
	[self finishWithError:IMSyncSessionChangedError()];
	return NO;
}

- (BOOL)ensureMutableRunToken:(NSObject *)runToken {
	if (![self ensureCurrentRunToken:runToken]) {
		return NO;
	}
	if (self.cancelled) {
		[self finishWithError:[NSError errorWithDomain:IMForegroundSyncErrorDomain
		                                            code:IMForegroundSyncErrorCancelled
		                                        userInfo:@{ NSLocalizedDescriptionKey: _(@"Cancelled.") }]];
		return NO;
	}
	return YES;
}

- (void)finishWithError:(nullable NSError *)error {
	if (!self.running) {
		return;
	}
	NSString *sessionFingerprint = self.runSessionFingerprint;
	BOOL sessionMatches = sessionFingerprint.length > 0 &&
	    [sessionFingerprint isEqualToString:IMSyncSessionFingerprint()];
	[[IMDatabase shared] resetUploadingStates];
	self.running = NO;
	if (sessionMatches) {
		[self postPendingBucketChanges];
	} else {
		[self.pendingChangedBuckets removeAllObjects];
	}
	void (^completion)(NSError *_Nullable) = self.completionBlock;
	self.completionBlock = nil;
	self.progressBlock = nil;
	self.runSessionFingerprint = nil;
	self.uploadsEnabledForRun = NO;
	self.runToken = nil;
	self.assetFetchResult = nil;
	[self.activeNetworkTask cancel];
	self.activeNetworkTask = nil;
	[[IMPhotoLibrary shared] cancelOutstandingRequests];
	if (completion) {
		completion(error);
	}
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithCapacity:2];
	if (error) {
		userInfo[IMForegroundSyncErrorUserInfoKey] = error;
	}
	if (sessionFingerprint.length > 0) {
		userInfo[IMForegroundSyncSessionFingerprintUserInfoKey] = sessionFingerprint;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:IMForegroundSyncDidFinishNotification
	                                                    object:self
	                                                  userInfo:userInfo.count > 0 ? userInfo : nil];
}

- (void)postPendingBucketChanges {
	if (self.pendingChangedBuckets.count == 0) {
		return;
	}
	NSArray<NSString *> *buckets = self.pendingChangedBuckets.allObjects;
	[self.pendingChangedBuckets removeAllObjects];
	[[NSNotificationCenter defaultCenter] postNotificationName:IMServerAssetsDidChangeNotification
	                                                    object:self
	                                                  userInfo:@{ IMChangedTimeBucketsUserInfoKey: buckets }];
}

#pragma mark - Sequential scan

- (void)processNextForToken:(NSObject *)runToken {
	if (![self ensureCurrentRunToken:runToken]) {
		return;
	}
	if (self.cancelled) {
		[self finishWithError:[NSError errorWithDomain:IMForegroundSyncErrorDomain
		                                            code:IMForegroundSyncErrorCancelled
		                                        userInfo:@{ NSLocalizedDescriptionKey: _(@"Cancelled.") }]];
		return;
	}
	if (IMPrefs.shared.backupEnabled && IMPrefs.shared.wifiOnlyUpload && !self.wifiAvailable) {
		[self finishWithError:[NSError errorWithDomain:IMForegroundSyncErrorDomain
		                                            code:IMForegroundSyncErrorNoWifi
		                                        userInfo:@{ NSLocalizedDescriptionKey: _(@"Wi-Fi dropped — sync paused (Preferences > Wi-Fi Only Upload is on).") }]];
		return;
	}

	if (!self.assetFetchResult || self.nextIndex >= self.assetFetchResult.count) {
		if (self.batchItems.count > 0) {
			__weak typeof(self) weakSelf = self;
			[self flushBatchThen:^{
				[weakSelf finishWithError:nil];
			} token:runToken];
		} else {
			[self finishWithError:nil];
		}
		return;
	}

	PHAsset *asset = [self.assetFetchResult objectAtIndex:self.nextIndex];
	self.nextIndex++;

	NSString *deviceAssetId = asset.localIdentifier;
	IMSyncState syncState = [[IMDatabase shared] syncStateForDeviceAssetId:deviceAssetId];
	if (syncState == IMSyncStateSynced) {
		self.checkedCount++;
		self.syncedCount++;
		[self reportProgress];
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([self ensureCurrentRunToken:runToken]) {
				[self processNextForToken:runToken];
			}
		});
		return;
	}
	NSDate *retryAt = (!self.ignoreRetryBackoff && syncState == IMSyncStateLocalOnly)
	    ? [[IMBackupQueue shared] nextAttemptDateForDeviceAssetId:deviceAssetId]
	    : nil;
	if (retryAt && [retryAt compare:[NSDate date]] == NSOrderedDescending) {
		self.checkedCount++;
		self.pendingUploadCount++;
		[self reportProgress];
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([self ensureCurrentRunToken:runToken]) {
				[self processNextForToken:runToken];
			}
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
			    if (![strongSelf ensureMutableRunToken:runToken]) {
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
					[[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
					if (IMPrefs.shared.backupEnabled) {
						[[IMBackupQueue shared] recordFailureForDeviceAssetId:deviceAssetId error:error];
					}
					strongSelf.checkedCount++;
				    strongSelf.pendingUploadCount++;
			    }

			    if (strongSelf.batchItems.count >= kBatchSize) {
				    [strongSelf flushBatchThen:^{
					    [strongSelf processNextForToken:runToken];
				    } token:runToken];
			    } else {
				    [strongSelf processNextForToken:runToken];
			    }
		    });
	    }];
}

- (void)flushBatchThen:(void (^)(void))next token:(NSObject *)runToken {
	if (![self ensureMutableRunToken:runToken]) {
		return;
	}
	NSArray<NSDictionary<NSString *, NSString *> *> *items = self.batchItems;
	NSDictionary<NSString *, PHAsset *> *assetsById = self.batchAssetsById;
	self.batchItems = [NSMutableArray array];
	self.batchAssetsById = [NSMutableDictionary dictionary];
	if (IMPrefs.shared.backupEnabled) {
		NSMutableOrderedSet<NSString *> *queuedDeviceAssetIDs = [NSMutableOrderedSet orderedSet];
		for (NSDictionary<NSString *, NSString *> *item in items) {
			NSString *deviceAssetId = IMDeviceAssetIdFromItemId(item[@"id"]);
			if (deviceAssetId.length > 0) [queuedDeviceAssetIDs addObject:deviceAssetId];
		}
		[[IMBackupQueue shared] enqueueDeviceAssetIds:queuedDeviceAssetIDs.array];
	}

	__weak typeof(self) weakSelf = self;
	self.activeNetworkTask = [IMAssetApi bulkUploadCheckWithItems:items
	                           completion:^(NSDictionary<NSString *, NSString *> *_Nullable actionsById,
	                                        NSDictionary<NSString *, NSString *> *_Nullable matchedAssetIdsById,
	                                        NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    strongSelf.activeNetworkTask = nil;
			if (![strongSelf ensureMutableRunToken:runToken]) {
			    return;
		    }

			if (error || !actionsById) {
				NSError *checkError = error ?: [NSError errorWithDomain:IMForegroundSyncErrorDomain
				                                                              code:IMForegroundSyncErrorCheckFailed
				                                                          userInfo:@{ NSLocalizedDescriptionKey: _(@"Server dedup check failed.") }];
				if (IMPrefs.shared.backupEnabled) {
					NSMutableOrderedSet<NSString *> *failedDeviceAssetIDs = [NSMutableOrderedSet orderedSet];
					for (NSDictionary<NSString *, NSString *> *item in items) {
						NSString *deviceAssetId = IMDeviceAssetIdFromItemId(item[@"id"]);
						if (deviceAssetId.length > 0) {
							[failedDeviceAssetIDs addObject:deviceAssetId];
						}
					}
					for (NSString *deviceAssetId in failedDeviceAssetIDs) {
						[[IMBackupQueue shared] recordFailureForDeviceAssetId:deviceAssetId error:checkError];
					}
				}
				[strongSelf finishWithError:checkError];
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
		    NSMutableArray<NSString *> *succeededDeviceAssetIDs = [NSMutableArray array];
		    for (NSString *deviceAssetId in orderedAssetIds) {
			    strongSelf.checkedCount++;
				if ([matchedByAsset[deviceAssetId] boolValue]) {
				    [[IMDatabase shared] setSyncState:IMSyncStateSynced
				                               assetId:matchedAssetIdByAsset[deviceAssetId]
				                     forDeviceAssetId:deviceAssetId];
					strongSelf.syncedCount++;
					[succeededDeviceAssetIDs addObject:deviceAssetId];
				} else if (IMPrefs.shared.backupEnabled) {
					[[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
					[needsUpload addObject:deviceAssetId];
			    } else {
				    [[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
				    strongSelf.pendingUploadCount++;
			    }
		    }
		    [[IMBackupQueue shared] markSucceededDeviceAssetIds:succeededDeviceAssetIDs];

		    [strongSelf uploadDeviceAssetIds:needsUpload
		                          assetsById:assetsById
		                                then:^{
				    if (![strongSelf ensureMutableRunToken:runToken]) {
					    return;
				    }
			    [strongSelf postPendingBucketChanges];
			    [strongSelf reportProgress];
			    next();
		    }
		                               token:runToken];
	    }];
}

- (void)uploadDeviceAssetIds:(NSArray<NSString *> *)deviceAssetIds
                    assetsById:(NSDictionary<NSString *, PHAsset *> *)assetsById
                          then:(void (^)(void))then
                         token:(NSObject *)runToken {
	if (![self ensureMutableRunToken:runToken]) {
		return;
	}
	if (deviceAssetIds.count == 0 || self.cancelled) {
		then();
		return;
	}
	if (IMPrefs.shared.backupEnabled && IMPrefs.shared.wifiOnlyUpload && !self.wifiAvailable) {
		for (NSString *queuedId in deviceAssetIds) {
			[[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:queuedId];
			self.pendingUploadCount++;
		}
		then();
		return;
	}

	NSString *deviceAssetId = deviceAssetIds.firstObject;
	NSArray<NSString *> *rest = [deviceAssetIds subarrayWithRange:NSMakeRange(1, deviceAssetIds.count - 1)];
	PHAsset *asset = assetsById[deviceAssetId];
	if (!asset) {
		[[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
		[[IMBackupQueue shared] recordFailureForDeviceAssetId:deviceAssetId error:nil];
		self.pendingUploadCount++;
		[self uploadDeviceAssetIds:rest assetsById:assetsById then:then token:runToken];
		return;
	}

	[[IMDatabase shared] setSyncState:IMSyncStateUploading assetId:nil forDeviceAssetId:deviceAssetId];

	PHAssetResource *resource = [[IMPhotoLibrary shared] uploadResourceForAsset:asset];
	if (!resource) {
		NSLog(@"IMForegroundSync: no uploadable resource for %@", deviceAssetId);
		[[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
		[[IMBackupQueue shared] recordFailureForDeviceAssetId:deviceAssetId error:nil];
		self.pendingUploadCount++;
		[self uploadDeviceAssetIds:rest assetsById:assetsById then:then token:runToken];
		return;
	}

	__weak typeof(self) weakSelf = self;
	[self fetchAndUploadLiveVideoForAsset:asset
	                        deviceAssetId:deviceAssetId
	                           completion:^(NSString *_Nullable livePhotoVideoId) {
		typeof(self) s3 = weakSelf;
		if (!s3 || ![s3 ensureMutableRunToken:runToken]) {
			return;
		}
		NSString *fallbackName = asset.mediaType == PHAssetMediaTypeVideo ? @"video.mov" : @"photo.jpg";
		[s3 streamUploadResource:resource
		                   asset:asset
		        fallbackFilename:fallbackName
		        livePhotoVideoId:livePhotoVideoId
		                   token:runToken
		              completion:^(NSString *_Nullable uploadedAssetId, NSError *_Nullable uploadError) {
			typeof(self) s2 = weakSelf;
			if (!s2 || ![s2 ensureMutableRunToken:runToken]) {
				return;
			}
			if (uploadedAssetId) {
				[[IMDatabase shared] setSyncState:IMSyncStateSynced assetId:uploadedAssetId forDeviceAssetId:deviceAssetId];
				[[IMBackupQueue shared] markSucceededDeviceAssetId:deviceAssetId];
				s2.syncedCount++;
				s2.uploadedCount++;
				if (asset.creationDate) {
					[s2.pendingChangedBuckets addObject:IMTimeBucketKeyForDate(asset.creationDate)];
				}
			} else {
				NSLog(@"IMForegroundSync: upload failed for %@: %@", deviceAssetId, uploadError);
				[[IMDatabase shared] setSyncState:IMSyncStateLocalOnly assetId:nil forDeviceAssetId:deviceAssetId];
				[[IMBackupQueue shared] recordFailureForDeviceAssetId:deviceAssetId error:uploadError];
				s2.pendingUploadCount++;
			}
			[s2 uploadDeviceAssetIds:rest assetsById:assetsById then:then token:runToken];
		}];
	}
	                                token:runToken];
}

- (void)streamUploadResource:(PHAssetResource *)resource
                       asset:(PHAsset *)asset
            fallbackFilename:(NSString *)fallbackFilename
            livePhotoVideoId:(nullable NSString *)livePhotoVideoId
                       token:(NSObject *)runToken
                  completion:(void (^)(NSString *_Nullable assetId, NSError *_Nullable error))completion {
	NSString *filename = resource.originalFilename.length > 0 ? resource.originalFilename : fallbackFilename;
	NSError *bodyError = nil;
	IMMultipartBodyFile *body = [IMAssetApi uploadBodyWithFilename:filename
	                                                 fileCreatedAt:IMISO8601StringFromDate(asset.creationDate)
	                                                fileModifiedAt:IMISO8601StringFromDate(asset.modificationDate ?: asset.creationDate)
	                                              livePhotoVideoId:livePhotoVideoId
	                                                         error:&bodyError];
	if (!body) {
		completion(nil, bodyError);
		return;
	}
	__weak typeof(self) weakSelf = self;
	[[IMPhotoLibrary shared] streamResource:resource
	                           chunkHandler:^(NSData *chunk) {
		                           [body appendFileData:chunk];
	                           }
	                             completion:^(NSError *_Nullable readError) {
		NSError *finishError = nil;
		BOOL ready = !readError && [body finishWithError:&finishError];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) strongSelf = weakSelf;
			if (!strongSelf || ![strongSelf ensureMutableRunToken:runToken]) {
				[body discard];
				return;
			}
			if (!ready) {
				[body discard];
				completion(nil, readError ?: finishError);
				return;
			}
			strongSelf.activeNetworkTask = [IMAssetApi uploadAssetBody:body
			                                                completion:^(NSString *_Nullable assetId, NSError *_Nullable error) {
				typeof(self) s2 = weakSelf;
				if (s2) s2.activeNetworkTask = nil;
				completion(assetId, error);
			}];
		});
	}];
}

- (void)fetchAndUploadLiveVideoForAsset:(PHAsset *)asset
                          deviceAssetId:(NSString *)deviceAssetId
                             completion:(void (^)(NSString *_Nullable livePhotoVideoId))completion
                                  token:(NSObject *)runToken {
	if (![self ensureMutableRunToken:runToken]) {
		return;
	}
	PHAssetResource *video = [[IMPhotoLibrary shared] pairedVideoResourceForAsset:asset];
	if (!video) {
		completion(nil);
		return;
	}
	[self streamUploadResource:video
	                     asset:asset
	          fallbackFilename:@"live.mov"
	          livePhotoVideoId:nil
	                     token:runToken
	                completion:^(NSString *_Nullable videoAssetId, NSError *_Nullable error) {
		if (![self ensureMutableRunToken:runToken]) {
			return;
		}
		if (!videoAssetId) {
			NSLog(@"IMForegroundSync: paired video upload failed for %@: %@", deviceAssetId, error);
		}
		completion(videoAssetId);
	}];
}

- (void)reportProgress {
	if (self.progressBlock) {
		self.progressBlock(self.checkedCount, self.totalCount);
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:IMForegroundSyncProgressNotification object:self];
}

@end
