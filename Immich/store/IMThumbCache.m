#import "IMThumbCache.h"
#import "IMAssetApi.h"

@interface IMThumbCacheTask ()
@property (atomic) BOOL cancelled;
@property (atomic, nullable) NSURLSessionTask *networkTask;
@end

static NSUInteger IMDecodedByteCost(UIImage *image) {
	CGFloat scale = image.scale > 0 ? image.scale : 1;
	return (NSUInteger)(image.size.width * scale * image.size.height * scale * 4);
}

@implementation IMThumbCacheTask
- (void)cancel {
	self.cancelled = YES;
	[self.networkTask cancel];
}
@end

static const unsigned long long kDiskCacheCapBytes = 256 * 1024 * 1024;
static const NSUInteger kWritesPerTrimCheck = 100;

@interface IMThumbCache ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memoryCache;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, copy) NSString *diskCacheDir;
@property (atomic) NSUInteger writesSinceTrim;
@end

@implementation IMThumbCache

+ (instancetype)shared {
	static IMThumbCache *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMThumbCache alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_memoryCache = [[NSCache alloc] init];
		_memoryCache.countLimit = 500;
		_memoryCache.totalCostLimit = 64 * 1024 * 1024; 
		_ioQueue = dispatch_queue_create("com.lns.immich-ios-14.thumbcache", DISPATCH_QUEUE_CONCURRENT);

		NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
		_diskCacheDir = [caches stringByAppendingPathComponent:@"thumbnails"];
		[[NSFileManager defaultManager] createDirectoryAtPath:_diskCacheDir
		                           withIntermediateDirectories:YES
		                                            attributes:nil
		                                                 error:nil];
		[self trimDiskCache];
	}
	return self;
}

- (void)trimDiskCache {
	NSString *dir = self.diskCacheDir;
	dispatch_barrier_async(self.ioQueue, ^{
		NSFileManager *fm = [NSFileManager defaultManager];
		NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
		unsigned long long total = 0;
		for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
			NSString *path = [dir stringByAppendingPathComponent:name];
			NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
			if (!attrs) {
				continue;
			}
			total += attrs.fileSize;
			[entries addObject:@{ @"path": path,
			                      @"size": @(attrs.fileSize),
			                      @"date": attrs.fileModificationDate ?: [NSDate distantPast] }];
		}
		if (total <= kDiskCacheCapBytes) {
			return;
		}
		[entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			return [a[@"date"] compare:b[@"date"]];
		}];
		unsigned long long target = kDiskCacheCapBytes * 8 / 10;
		for (NSDictionary *entry in entries) {
			if (total <= target) {
				break;
			}
			if ([fm removeItemAtPath:entry[@"path"] error:nil]) {
				total -= [entry[@"size"] unsignedLongLongValue];
			}
		}
	});
}

- (NSString *)cacheKeyForAssetId:(NSString *)assetId size:(NSString *)size {
	return [NSString stringWithFormat:@"%@_%@", assetId, size];
}

- (NSString *)diskPathForKey:(NSString *)key {
	return [self.diskCacheDir stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"jpg"]];
}

- (IMThumbCacheTask *)thumbnailForAssetId:(NSString *)assetId
                                      size:(NSString *)size
                                completion:(void (^)(UIImage *_Nullable image))completion {
	NSString *key = [self cacheKeyForAssetId:assetId size:size];
	IMThumbCacheTask *task = [[IMThumbCacheTask alloc] init];

	UIImage *cached = [self.memoryCache objectForKey:key];
	if (cached) {
		if (NSThread.isMainThread) {
			completion(cached);
		} else {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (!task.cancelled) {
					completion(cached);
				}
			});
		}
		return task;
	}

	NSString *path = [self diskPathForKey:key];
	__weak typeof(self) weakSelf = self;

	dispatch_async(self.ioQueue, ^{
		if (task.cancelled) {
			return;
		}
		NSData *diskData = [NSData dataWithContentsOfFile:path];
		if (diskData) {
			UIImage *diskImage = [UIImage imageWithData:diskData];
			if (diskImage) {
				[weakSelf.memoryCache setObject:diskImage forKey:key cost:IMDecodedByteCost(diskImage)];
				[[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate: [NSDate date] }
				                                  ofItemAtPath:path
				                                         error:nil];
			}
			if (!task.cancelled) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (!task.cancelled) {
						completion(diskImage);
					}
				});
			}
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			if (task.cancelled) {
				return;
			}
			task.networkTask = [IMAssetApi thumbnailDataForAssetId:assetId
			                                                    size:size
			                                              completion:^(NSData *_Nullable data, NSError *_Nullable error) {
				    if (task.cancelled) {
					    return;
				    }
				    if (!data) {
					    completion(nil);
					    return;
				    }
				    dispatch_async(weakSelf.ioQueue, ^{
					    UIImage *netImage = [UIImage imageWithData:data];
					    if (netImage) {
						    [weakSelf.memoryCache setObject:netImage forKey:key cost:IMDecodedByteCost(netImage)];
					    }
					    [data writeToFile:path atomically:YES];
					    typeof(self) cache = weakSelf;
					    if (cache) {
						    cache.writesSinceTrim += 1;
						    if (cache.writesSinceTrim >= kWritesPerTrimCheck) {
							    cache.writesSinceTrim = 0;
							    [cache trimDiskCache];
						    }
					    }
					    if (!task.cancelled) {
						    dispatch_async(dispatch_get_main_queue(), ^{
							    if (!task.cancelled) {
								    completion(netImage);
							    }
						    });
					    }
				    });
			    }];
		});
	});

	return task;
}

- (void)diskCacheSizeWithCompletion:(void (^)(unsigned long long bytes))completion {
	NSString *dir = self.diskCacheDir;
	dispatch_async(self.ioQueue, ^{
		NSFileManager *fm = [NSFileManager defaultManager];
		unsigned long long total = 0;
		for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
			NSDictionary *attrs = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
			total += attrs.fileSize;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(total);
		});
	});
}

- (void)clearWithCompletion:(void (^)(void))completion {
	[self.memoryCache removeAllObjects];
	NSString *dir = self.diskCacheDir;
	dispatch_async(self.ioQueue, ^{
		NSFileManager *fm = [NSFileManager defaultManager];
		for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
			[fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			completion();
		});
	});
}

@end
