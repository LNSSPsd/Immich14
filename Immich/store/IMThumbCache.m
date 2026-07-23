#import "IMThumbCache.h"
#import "IMAssetApi.h"

@interface IMThumbCacheTask ()
@property (atomic) BOOL cancelled;
@property (atomic, nullable) NSURLSessionTask *networkTask;
@end

@implementation IMThumbCacheTask
- (void)cancel {
	self.cancelled = YES;
	[self.networkTask cancel];
}
@end

@interface IMThumbCache ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *memoryCache;
@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, copy) NSString *diskCacheDir;
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
		_ioQueue = dispatch_queue_create("com.lns.immich-ios-14.thumbcache", DISPATCH_QUEUE_CONCURRENT);

		NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
		_diskCacheDir = [caches stringByAppendingPathComponent:@"thumbnails"];
		[[NSFileManager defaultManager] createDirectoryAtPath:_diskCacheDir
		                           withIntermediateDirectories:YES
		                                            attributes:nil
		                                                 error:nil];
	}
	return self;
}

- (NSString *)cacheKeyForAssetId:(NSString *)assetId size:(NSString *)size {
	return [NSString stringWithFormat:@"%@_%@", assetId, size];
}

- (NSString *)diskPathForKey:(NSString *)key {
	return [self.diskCacheDir stringByAppendingPathComponent:[key stringByAppendingPathExtension:@"jpg"]];
}

- (nullable IMThumbCacheTask *)thumbnailForAssetId:(NSString *)assetId
                                                size:(NSString *)size
                                          completion:(void (^)(UIImage *_Nullable image))completion {
	NSString *key = [self cacheKeyForAssetId:assetId size:size];

	UIImage *cached = [self.memoryCache objectForKey:key];
	if (cached) {
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(cached);
		});
		return nil;
	}

	IMThumbCacheTask *task = [[IMThumbCacheTask alloc] init];
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
				[weakSelf.memoryCache setObject:diskImage forKey:key cost:diskData.length];
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
						    [weakSelf.memoryCache setObject:netImage forKey:key cost:data.length];
					    }
					    [data writeToFile:path atomically:YES];
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

@end
