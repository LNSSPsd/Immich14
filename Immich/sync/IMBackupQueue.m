#import "IMBackupQueue.h"
#include <stdlib.h>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

static NSString *const kQueueFileName = @"immich-backup-queue.plist";
static NSString *const kQueueVersionKey = @"version";
static NSString *const kQueueEntriesKey = @"entries";
static NSString *const kQueueRunFailuresKey = @"consecutiveRunFailures";
static NSString *const kQueueNextRunKey = @"nextRunAt";

static NSString *const kEntryAttemptsKey = @"attempts";
static NSString *const kEntryNextAttemptKey = @"nextAttemptAt";
static NSString *const kEntryEnqueuedKey = @"enqueuedAt";
static NSString *const kEntryLastErrorKey = @"lastError";

static const NSTimeInterval kBaseRetryDelay = 30.0;
static const NSTimeInterval kMaxRetryDelay = 6.0 * 60.0 * 60.0;

@interface IMBackupQueue ()
@property (nonatomic) dispatch_queue_t stateQueue;
@property (nonatomic, copy) NSString *statePath;
@property (nonatomic, copy) NSString *lockPath;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *entries;
@property (nonatomic) NSInteger mutableConsecutiveRunFailures;
@property (nonatomic, copy, nullable) NSDate *mutableNextRunDate;
@end

@implementation IMBackupQueue

+ (instancetype)shared {
	static IMBackupQueue *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMBackupQueue alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_stateQueue = dispatch_queue_create("com.lns.immich-ios-14.backup-queue", DISPATCH_QUEUE_SERIAL);
		const char *sharedPath = getenv("IM_BACKUP_SUPPORT_PATH");
		NSString *support = (sharedPath && sharedPath[0] != '\0')
		    ? [NSString stringWithUTF8String:sharedPath]
		    : nil;
		if (support.length == 0) {
			support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
			                                             NSUserDomainMask,
			                                             YES).firstObject;
		}
		if (support.length == 0) {
			support = NSTemporaryDirectory();
		}
		[[NSFileManager defaultManager] createDirectoryAtPath:support
		                          withIntermediateDirectories:YES
		                                           attributes:nil
		                                                error:nil];
		_statePath = [support stringByAppendingPathComponent:kQueueFileName];
		_lockPath = [support stringByAppendingPathComponent:[kQueueFileName stringByAppendingString:@".lock"]];
		_entries = [NSMutableDictionary dictionary];
		[self loadState];
	}
	return self;
}

- (void)loadStateFromDiskLocked {
	[self.entries removeAllObjects];
	NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:self.statePath];
	NSDictionary *savedEntries = [root isKindOfClass:[NSDictionary class]] ? root[kQueueEntriesKey] : nil;
	if ([savedEntries isKindOfClass:[NSDictionary class]]) {
		[savedEntries enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			if (![key isKindOfClass:[NSString class]] ||
			    ![value isKindOfClass:[NSDictionary class]] ||
			    [(NSString *)key length] == 0) {
				return;
			}
			NSMutableDictionary *entry = [(NSDictionary *)value mutableCopy];
			if (![entry[kEntryAttemptsKey] isKindOfClass:[NSNumber class]]) {
				entry[kEntryAttemptsKey] = @0;
			}
			if (![entry[kEntryEnqueuedKey] isKindOfClass:[NSDate class]]) {
				entry[kEntryEnqueuedKey] = [NSDate date];
			}
			if (entry[kEntryNextAttemptKey] && ![entry[kEntryNextAttemptKey] isKindOfClass:[NSDate class]]) {
				[entry removeObjectForKey:kEntryNextAttemptKey];
			}
			self.entries[(NSString *)key] = entry;
		}];
	}
	NSNumber *failures = [root[kQueueRunFailuresKey] isKindOfClass:[NSNumber class]]
	    ? root[kQueueRunFailuresKey]
	    : @0;
	self.mutableConsecutiveRunFailures = MAX(0, failures.integerValue);
	self.mutableNextRunDate = [root[kQueueNextRunKey] isKindOfClass:[NSDate class]]
	    ? root[kQueueNextRunKey]
	    : nil;
}

- (void)loadState {
	dispatch_sync(self.stateQueue, ^{
		[self loadStateFromDiskLocked];
	});
}

- (void)reloadFromPersistence {
	dispatch_sync(self.stateQueue, ^{
		int lockFD = open(self.lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
		if (lockFD >= 0 && flock(lockFD, LOCK_SH) != 0) {
			close(lockFD);
			lockFD = -1;
		}
		[self loadStateFromDiskLocked];
		if (lockFD >= 0) {
			(void)flock(lockFD, LOCK_UN);
			close(lockFD);
		}
	});
}

- (void)pruneDeviceAssetIdsNotInSet:(NSSet<NSString *> *)deviceAssetIds {
	if (!deviceAssetIds) {
		return;
	}
	NSSet<NSString *> *validIDs = [deviceAssetIds copy];
	dispatch_sync(self.stateQueue, ^{
		int lockFD = open(self.lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
		BOOL locked = lockFD >= 0 && flock(lockFD, LOCK_EX) == 0;
		if (!locked) {
			if (lockFD >= 0) close(lockFD);
			return;
		}
		[self loadStateFromDiskLocked];
		BOOL changed = NO;
		for (NSString *deviceAssetId in [self.entries.allKeys copy]) {
			if (![validIDs containsObject:deviceAssetId]) {
				[self.entries removeObjectForKey:deviceAssetId];
				changed = YES;
			}
		}
		if (changed) {
			[self persistStateLocked];
		}
		(void)flock(lockFD, LOCK_UN);
		close(lockFD);
	});
}

- (void)performLockedMutation:(void (^)(void))mutation {
	int lockFD = open(self.lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
	if (lockFD < 0 || flock(lockFD, LOCK_EX) != 0) {
		if (lockFD >= 0) close(lockFD);
		return;
	}
	[self loadStateFromDiskLocked];
	if (mutation) mutation();
	[self persistStateLocked];
	(void)flock(lockFD, LOCK_UN);
	close(lockFD);
}

- (void)persistStateLocked {
	NSMutableDictionary *root = [NSMutableDictionary dictionaryWithDictionary:@{
		kQueueVersionKey: @1,
		kQueueEntriesKey: self.entries.copy,
		kQueueRunFailuresKey: @(MAX(0, self.mutableConsecutiveRunFailures)),
	}];
	if (self.mutableNextRunDate) {
		root[kQueueNextRunKey] = self.mutableNextRunDate;
	}
	if (![root writeToFile:self.statePath atomically:YES]) {
		NSLog(@"IMBackupQueue: failed to persist %@", self.statePath);
	}
}

- (NSUInteger)pendingCount {
	__block NSUInteger count = 0;
	dispatch_sync(self.stateQueue, ^{
		count = self.entries.count;
	});
	return count;
}

- (NSDate *)nextAttemptDate {
	__block NSDate *result = nil;
	dispatch_sync(self.stateQueue, ^{
		for (NSDictionary *entry in self.entries.objectEnumerator) {
			NSDate *date = [entry[kEntryNextAttemptKey] isKindOfClass:[NSDate class]]
			    ? entry[kEntryNextAttemptKey]
			    : [NSDate distantPast];
			if (!result || [date compare:result] == NSOrderedAscending) {
				result = date;
			}
		}
	});
	return [result copy];
}

- (NSInteger)consecutiveRunFailures {
	__block NSInteger result = 0;
	dispatch_sync(self.stateQueue, ^{
		result = self.mutableConsecutiveRunFailures;
	});
	return result;
}

- (NSDate *)nextRunDate {
	__block NSDate *result = nil;
	dispatch_sync(self.stateQueue, ^{
		result = [self.mutableNextRunDate copy];
	});
	return result;
}

- (void)enqueueDeviceAssetId:(NSString *)deviceAssetId {
	[self enqueueDeviceAssetIds:deviceAssetId.length > 0 ? @[ deviceAssetId ] : @[]];
}

- (void)enqueueDeviceAssetIds:(NSArray<NSString *> *)deviceAssetIds {
	if (![deviceAssetIds isKindOfClass:[NSArray class]] || deviceAssetIds.count == 0) return;
	dispatch_sync(self.stateQueue, ^{
		[self performLockedMutation:^{
			NSDate *now = [NSDate date];
			for (id value in deviceAssetIds) {
				if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) continue;
				NSString *deviceAssetId = (NSString *)value;
				if (!self.entries[deviceAssetId]) {
					self.entries[deviceAssetId] = [@{
						kEntryAttemptsKey: @0,
						kEntryEnqueuedKey: now,
					} mutableCopy];
				}
			}
		}];
	});
}

- (void)markSucceededDeviceAssetId:(NSString *)deviceAssetId {
	[self markSucceededDeviceAssetIds:deviceAssetId.length > 0 ? @[ deviceAssetId ] : @[]];
}

- (void)markSucceededDeviceAssetIds:(NSArray<NSString *> *)deviceAssetIds {
	if (![deviceAssetIds isKindOfClass:[NSArray class]] || deviceAssetIds.count == 0) return;
	dispatch_sync(self.stateQueue, ^{
		[self performLockedMutation:^{
			for (id value in deviceAssetIds) {
				if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
					[self.entries removeObjectForKey:value];
				}
			}
		}];
	});
}

- (NSDate *)nextAttemptDateForDeviceAssetId:(NSString *)deviceAssetId {
	if (deviceAssetId.length == 0) {
		return nil;
	}
	__block NSDate *result = nil;
	dispatch_sync(self.stateQueue, ^{
		NSDictionary *entry = self.entries[deviceAssetId];
		if ([entry[kEntryNextAttemptKey] isKindOfClass:[NSDate class]]) {
			result = [entry[kEntryNextAttemptKey] copy];
		}
	});
	return result;
}

static NSTimeInterval IMRetryDelayForAttempt(NSUInteger attempt) {
	if (attempt == 0) {
		return kBaseRetryDelay;
	}
	NSUInteger shift = MIN(attempt - 1, (NSUInteger)16);
	NSTimeInterval delay = kBaseRetryDelay * (NSTimeInterval)(1ULL << shift);
	return MIN(delay, kMaxRetryDelay);
}

- (void)recordFailureForDeviceAssetId:(NSString *)deviceAssetId
                                error:(NSError *_Nullable)error {
	if (deviceAssetId.length == 0) {
		return;
	}
	dispatch_sync(self.stateQueue, ^{
		[self performLockedMutation:^{
			NSMutableDictionary *entry = self.entries[deviceAssetId];
			if (!entry) {
				entry = [@{
					kEntryAttemptsKey: @0,
					kEntryEnqueuedKey: [NSDate date],
				} mutableCopy];
				self.entries[deviceAssetId] = entry;
			}
			NSUInteger attempts = [entry[kEntryAttemptsKey] unsignedIntegerValue] + 1;
			entry[kEntryAttemptsKey] = @(attempts);
			entry[kEntryNextAttemptKey] = [NSDate dateWithTimeIntervalSinceNow:IMRetryDelayForAttempt(attempts)];
			NSString *message = error.localizedDescription;
			if (message.length > 0) {
				entry[kEntryLastErrorKey] = [message substringToIndex:MIN(message.length, (NSUInteger)512)];
			} else {
				[entry removeObjectForKey:kEntryLastErrorKey];
			}
		}];
	});
}

- (NSArray<NSString *> *)readyDeviceAssetIdsAtDate:(NSDate *)date limit:(NSUInteger)limit {
	if (limit == 0) {
		return @[];
	}
	NSDate *now = date ?: [NSDate date];
	__block NSArray<NSString *> *result = nil;
	dispatch_sync(self.stateQueue, ^{
		NSArray<NSString *> *sorted = [self.entries.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
			NSDictionary *left = self.entries[a];
			NSDictionary *right = self.entries[b];
			NSDate *leftDate = [left[kEntryNextAttemptKey] isKindOfClass:[NSDate class]] ? left[kEntryNextAttemptKey] : [NSDate distantPast];
			NSDate *rightDate = [right[kEntryNextAttemptKey] isKindOfClass:[NSDate class]] ? right[kEntryNextAttemptKey] : [NSDate distantPast];
			NSComparisonResult order = [leftDate compare:rightDate];
			return order == NSOrderedSame ? [a compare:b] : order;
		}];
		NSMutableArray<NSString *> *ready = [NSMutableArray arrayWithCapacity:MIN(limit, sorted.count)];
		for (NSString *deviceAssetId in sorted) {
			NSDictionary *entry = self.entries[deviceAssetId];
			NSDate *retryAt = [entry[kEntryNextAttemptKey] isKindOfClass:[NSDate class]] ? entry[kEntryNextAttemptKey] : nil;
			if (retryAt && [retryAt compare:now] == NSOrderedDescending) {
				continue;
			}
			[ready addObject:deviceAssetId];
			if (ready.count >= limit) {
				break;
			}
		}
		result = ready.copy;
	});
	return result ?: @[];
}

- (void)recordRunFailure:(NSError *_Nullable)error {
	dispatch_sync(self.stateQueue, ^{
		[self performLockedMutation:^{
			self.mutableConsecutiveRunFailures = MIN(self.mutableConsecutiveRunFailures + 1, (NSInteger)16);
			NSTimeInterval delay = IMRetryDelayForAttempt((NSUInteger)self.mutableConsecutiveRunFailures);
			self.mutableNextRunDate = [NSDate dateWithTimeIntervalSinceNow:delay];
			if (error.localizedDescription.length > 0) {
				NSLog(@"IMBackupQueue: run failed (attempt %ld), retry in %.0fs: %@",
				      (long)self.mutableConsecutiveRunFailures,
				      delay,
				      error.localizedDescription);
			}
		}];
	});
}

- (void)recordRunSuccess {
	dispatch_sync(self.stateQueue, ^{
		[self performLockedMutation:^{
			self.mutableConsecutiveRunFailures = 0;
			self.mutableNextRunDate = nil;
		}];
	});
}

- (void)setNextRunDate:(NSDate *)date {
	dispatch_sync(self.stateQueue, ^{
		[self performLockedMutation:^{
			self.mutableNextRunDate = [date copy];
		}];
	});
}

- (void)reset {
	dispatch_sync(self.stateQueue, ^{
		[self performLockedMutation:^{
			[self.entries removeAllObjects];
			self.mutableConsecutiveRunFailures = 0;
			self.mutableNextRunDate = nil;
		}];
	});
}

@end
