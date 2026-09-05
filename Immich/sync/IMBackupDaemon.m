#import "IMBackupDaemon.h"
#import "IMBackupQueue.h"
#import "IMForegroundSync.h"
#import "IMPrefs.h"
#import "IMSession.h"
#import "IMApiClient.h"
#import "common.h"
#import <BackgroundTasks/BackgroundTasks.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

static BOOL gRunningAsDaemonProcess = NO;

static NSString *IMBackupSupportDirectory(void) {
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
	return support;
}

static NSString *IMBackupSessionFingerprint(void) {
	IMSession *session = IMSession.shared;
	return [NSString stringWithFormat:@"%@|%@|%ld|%lu",
	                                session.baseURL.absoluteString ?: @"",
	                                session.userId ?: @"",
	                                (long)session.authKind,
	                                (unsigned long)session.accessToken.hash];
}

static NSString *const kBackupSyncLockFileName = @"immich-backup-sync.lock";

#if IM_TROLLSTORE
#include <limits.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <spawn.h>
#include <sys/stat.h>

#if __has_include(<spawn_private.h>)
#include <spawn_private.h>
#else
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict, uid_t, uint32_t) __attribute__((weak_import));
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict, uid_t) __attribute__((weak_import));
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict, gid_t) __attribute__((weak_import));
extern int posix_spawnattr_setprocesstype_np(posix_spawnattr_t *, int) __attribute__((weak_import));
extern int posix_spawnattr_setjetsam_ext(posix_spawnattr_t *, short, int, int, int) __attribute__((weak_import));
#endif

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 0x1
#endif
#ifndef POSIX_SPAWN_PROC_TYPE_DAEMON_STANDARD
#define POSIX_SPAWN_PROC_TYPE_DAEMON_STANDARD 0x00000300
#endif
#ifndef POSIX_SPAWN_SETSID
#define POSIX_SPAWN_SETSID 0x0400
#endif

extern char **environ;
#endif

NSString *const IMBackupTaskIdentifier = @"com.lns.immich-ios-14.backup";

static const NSTimeInterval kNormalScheduleInterval = 6.0 * 60.0 * 60.0;
static const NSTimeInterval kMinimumScheduleInterval = 60.0;

static BOOL IMBackupDateIsDistantPast(NSDate *_Nullable date) {
	return date && [date timeIntervalSinceReferenceDate] <= [NSDate.distantPast timeIntervalSinceReferenceDate];
}

#if IM_TROLLSTORE
static NSTimeInterval IMDaemonTimerInterval(void);
static void IMDaemonArmTimer(dispatch_source_t timer, NSTimeInterval interval);
#endif

#if IM_TROLLSTORE
static volatile sig_atomic_t gDaemonStopRequested = 0;
static pid_t gSpawnedDaemonPID = 0;
static NSString *const kDaemonRunFileName = @"immich-backup-daemon.run";

static NSString *IMDaemonRunFilePath(void) {
	return [IMBackupSupportDirectory() stringByAppendingPathComponent:kDaemonRunFileName];
}

static void IMDaemonSignalHandler(int signalNumber) {
	(void)signalNumber;
	gDaemonStopRequested = 1;
}

static void IMRemoveDaemonRunFile(void) {
	NSString *path = IMDaemonRunFilePath();
	if (path.length > 0) {
		unlink(path.fileSystemRepresentation);
	}
}

static BOOL IMWriteDaemonPIDFile(void) {
	NSString *path = IMDaemonRunFilePath();
	int fd = open(path.fileSystemRepresentation, O_RDWR | O_CREAT | O_EXCL, 0600);
	if (fd < 0 && errno == EEXIST) {
		int oldFD = open(path.fileSystemRepresentation, O_RDONLY);
		pid_t oldPID = 0;
		ssize_t bytes = oldFD >= 0 ? read(oldFD, &oldPID, sizeof(oldPID)) : -1;
		if (oldFD >= 0) {
			close(oldFD);
		}
		if (bytes == sizeof(oldPID) && oldPID > 0) {
			int probe = kill(oldPID, 0);
			if (probe == 0 || errno == EPERM) {
			NSLog(@"IMBackupDaemon: daemon already running (PID %d)", oldPID);
			return NO;
			}
		}
		unlink(path.fileSystemRepresentation);
		fd = open(path.fileSystemRepresentation, O_RDWR | O_CREAT | O_EXCL, 0600);
	}
	if (fd < 0) {
		NSLog(@"IMBackupDaemon: cannot create run marker %@ (%s)", path, strerror(errno));
		return NO;
	}
	pid_t pid = getpid();
	(void)write(fd, &pid, sizeof(pid));
	close(fd);
	atexit(IMRemoveDaemonRunFile);
	return YES;
}
#endif

@interface IMBackupDaemon ()
@property (nonatomic) BOOL registered;
@property (nonatomic) BOOL started;
@property (nonatomic) BOOL syncOwnedByDaemon;
@property (nonatomic) BOOL suppressNextFinishNotification;
@property (nonatomic) BOOL runRequestedWhileBusy;
@property (nonatomic) BOOL queuedCheckOnly;
@property (nonatomic) BOOL queuedRetryBackoffBypass;
@property (nonatomic, strong, nullable) BGTask *activeTask;
@property (nonatomic) BOOL activeTaskCompleted;
@property (nonatomic, strong, nullable) NSError *lastError;
@property (nonatomic) dispatch_source_t daemonTimer;
@property (nonatomic, copy, nullable) NSString *activeRunSessionFingerprint;
#if IM_TROLLSTORE
@property (nonatomic) dispatch_source_t daemonSignalSource;
@property (nonatomic) dispatch_source_t daemonInterruptSource;
#endif
@property (nonatomic) int syncRunLockFD;
- (BOOL)acquireSyncRunLock;
- (void)releaseSyncRunLock;
- (void)runNowAllowingCheckOnly:(BOOL)allowCheckOnly retryBackoffBypass:(BOOL)retryBackoffBypass;
- (void)finishRunAfterSessionChange;
@end

@implementation IMBackupDaemon

+ (instancetype)shared {
	static IMBackupDaemon *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMBackupDaemon alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_syncRunLockFD = -1;
		if (!gRunningAsDaemonProcess) {
			NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
			[center addObserver:self
		           selector:@selector(syncDidFinish:)
		               name:IMForegroundSyncDidFinishNotification
		             object:nil];
			[center addObserver:self
		           selector:@selector(sessionDidChange:)
		               name:IMSessionDidChangeNotification
		             object:nil];
			[center addObserver:self
		           selector:@selector(backupPreferenceDidChangeNotification:)
		               name:IMPrefsBackupEnabledDidChangeNotification
		             object:nil];
		}
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self releaseSyncRunLock];
}

- (BOOL)acquireSyncRunLock {
	if (self.syncRunLockFD >= 0) {
		return YES;
	}
	NSString *support = IMBackupSupportDirectory();
	NSString *path = [support stringByAppendingPathComponent:kBackupSyncLockFileName];
	if (path.length == 0) {
		return NO;
	}
	int openFlags = O_CREAT | O_RDWR;
#ifdef O_CLOEXEC
	openFlags |= O_CLOEXEC;
#endif
	int fd = open(path.fileSystemRepresentation, openFlags, 0600);
	if (fd < 0) {
		NSLog(@"IMBackupDaemon: cannot open sync lock %@ (%s)", path, strerror(errno));
		return NO;
	}
	int descriptorFlags = fcntl(fd, F_GETFD);
	if (descriptorFlags < 0 || fcntl(fd, F_SETFD, descriptorFlags | FD_CLOEXEC) != 0) {
		int descriptorError = errno;
		close(fd);
		NSLog(@"IMBackupDaemon: cannot mark sync lock close-on-exec %@ (%s)", path, strerror(descriptorError));
		return NO;
	}
	if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
		int lockError = errno;
		close(fd);
		if (lockError != EWOULDBLOCK && lockError != EAGAIN) {
			NSLog(@"IMBackupDaemon: cannot acquire sync lock %@ (%s)", path, strerror(lockError));
		}
		return NO;
	}
	self.syncRunLockFD = fd;
	return YES;
}

- (void)releaseSyncRunLock {
	int fd = self.syncRunLockFD;
	if (fd < 0) {
		return;
	}
	self.syncRunLockFD = -1;
	(void)flock(fd, LOCK_UN);
	close(fd);
}

- (BOOL)isRunning {
	return IMForegroundSync.shared.isRunning;
}

- (NSDate *)nextRunDate {
	return IMBackupQueue.shared.nextRunDate;
}

- (NSInteger)consecutiveFailures {
	return IMBackupQueue.shared.consecutiveRunFailures;
}

- (NSUInteger)pendingCount {
	return IMBackupQueue.shared.pendingCount;
}

- (void)registerBackgroundTasks {
	if (gRunningAsDaemonProcess || self.registered) {
		return;
	}
	if (![NSThread isMainThread]) {
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf registerBackgroundTasks];
			[weakSelf scheduleNextRun];
		});
		return;
	}
	if (@available(iOS 13.0, *)) {
		BOOL accepted = [[BGTaskScheduler sharedScheduler]
		    registerForTaskWithIdentifier:IMBackupTaskIdentifier
		                           usingQueue:nil
		                     launchHandler:^(BGTask *task) {
			                     [self handleBackgroundTask:task];
		                     }];
		self.registered = accepted;
		if (!accepted) {
			NSLog(@"IMBackupDaemon: BGTask registration rejected");
		}
	}
}

- (void)start {
	if (gRunningAsDaemonProcess) {
		return;
	}
	self.started = YES;
	[self registerBackgroundTasks];
	if (!IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		[self cancelScheduledTask];
		return;
	}
	[self scheduleNextRun];
#if IM_TROLLSTORE
	[self startPrivilegedDaemonIfNeeded];
#endif
}

- (void)applicationDidEnterBackground {
	if (!self.started) {
		[self start];
	}
	if (!IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		return;
	}
	if (!IMForegroundSync.shared.isRunning) {
		[self runScheduled];
	}
	[self scheduleNextRun];
#if IM_TROLLSTORE
	[self startPrivilegedDaemonIfNeeded];
#endif
}

- (void)applicationWillEnterForeground {
	if (!self.started) {
		[self start];
	}
	if (IMPrefs.shared.backupEnabled && IMSession.shared.isLoggedIn) {
		NSDate *next = self.nextRunDate;
		NSDate *attempt = IMBackupQueue.shared.nextAttemptDate;
		if (attempt && (!IMBackupDateIsDistantPast(attempt) || !next) &&
		    (!next || [attempt compare:next] == NSOrderedAscending)) next = attempt;
		if (next && [next compare:[NSDate date]] != NSOrderedDescending && !IMForegroundSync.shared.isRunning) {
			[self runScheduled];
		}
		[self scheduleNextRun];
	}
}

- (void)backupPreferenceDidChangeNotification:(NSNotification *)notification {
	(void)notification;
	[self backupPreferenceDidChange];
}

- (void)backupPreferenceDidChange {
	if (![NSThread isMainThread]) {
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf backupPreferenceDidChange];
		});
		return;
	}
	if (!IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		[IMForegroundSync.shared cancel];
		[self cancelScheduledTask];
#if IM_TROLLSTORE
		[self stopPrivilegedDaemon];
#endif
		return;
	}
	if (!self.started) {
		[self start];
	}
	[self runNow];
	[self scheduleNextRun];
#if IM_TROLLSTORE
	[self startPrivilegedDaemonIfNeeded];
#endif
}

- (void)sessionDidChange:(NSNotification *)notification {
	(void)notification;
	if (!IMSession.shared.isLoggedIn) {
		[IMForegroundSync.shared cancel];
		[self cancelScheduledTask];
		[IMBackupQueue.shared reset];
		self.runRequestedWhileBusy = NO;
		self.queuedCheckOnly = NO;
		self.queuedRetryBackoffBypass = NO;
#if IM_TROLLSTORE
		[self stopPrivilegedDaemon];
#endif
		return;
	}
	if (IMPrefs.shared.backupEnabled) {
		[self start];
	}
}

- (void)runNow {
	[self runNowAllowingCheckOnly:NO retryBackoffBypass:YES];
}

- (void)runCheckNow {
	[self runNowAllowingCheckOnly:YES retryBackoffBypass:YES];
}

- (void)runScheduled {
	[self runNowAllowingCheckOnly:NO retryBackoffBypass:NO];
}

- (void)runNowAllowingCheckOnly:(BOOL)allowCheckOnly retryBackoffBypass:(BOOL)retryBackoffBypass {
	if ((!allowCheckOnly && !IMPrefs.shared.backupEnabled) || !IMSession.shared.isLoggedIn) {
		return;
	}
	if (!retryBackoffBypass) {
		NSDate *nextRun = IMBackupQueue.shared.nextRunDate;
		if (nextRun && [nextRun compare:[NSDate date]] == NSOrderedDescending) {
			[self completeActiveTaskWithSuccess:YES];
			[self scheduleNextRun];
			return;
		}
	}
	if (IMForegroundSync.shared.isRunning) {
		self.runRequestedWhileBusy = YES;
		self.queuedCheckOnly = self.queuedCheckOnly || allowCheckOnly;
		self.queuedRetryBackoffBypass = self.queuedRetryBackoffBypass || retryBackoffBypass;
		return;
	}
	if (![self acquireSyncRunLock]) {
		[self completeActiveTaskWithSuccess:YES];
		[self scheduleNextRun];
		return;
	}
	if (IMForegroundSync.shared.isRunning) {
		[self releaseSyncRunLock];
		self.runRequestedWhileBusy = YES;
		return;
	}
	[IMBackupQueue.shared setNextRunDate:nil];
	self.syncOwnedByDaemon = YES;
	self.suppressNextFinishNotification = YES;
	self.activeRunSessionFingerprint = IMBackupSessionFingerprint();
	__weak typeof(self) weakSelf = self;
	[IMForegroundSync.shared startWithProgress:nil completion:^(NSError *_Nullable error) {
		IMBackupDaemon *strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
#if IM_TROLLSTORE
		if (gRunningAsDaemonProcess) {
			[IMSession.shared reloadFromPersistence];
		}
#endif
		if (strongSelf.activeRunSessionFingerprint.length == 0 ||
		    ![strongSelf.activeRunSessionFingerprint isEqualToString:IMBackupSessionFingerprint()]) {
			[strongSelf finishRunAfterSessionChange];
			return;
		}
		[strongSelf finishRunWithError:error];
	} ignoreRetryBackoff:retryBackoffBypass];
}

- (void)syncDidFinish:(NSNotification *)notification {
	NSString *eventFingerprint = notification.userInfo[IMForegroundSyncSessionFingerprintUserInfoKey];
	if ([eventFingerprint isKindOfClass:[NSString class]] && eventFingerprint.length > 0 &&
	    ![eventFingerprint isEqualToString:IMBackupSessionFingerprint()]) {
		self.suppressNextFinishNotification = NO;
		return;
	}
	if (self.suppressNextFinishNotification) {
		self.suppressNextFinishNotification = NO;
		return;
	}
	NSError *error = notification.userInfo[IMForegroundSyncErrorUserInfoKey];
	[self finishRunWithError:error];
}

- (void)finishRunWithError:(NSError *)error {
	self.activeRunSessionFingerprint = nil;
	if (self.syncOwnedByDaemon) {
		self.syncOwnedByDaemon = NO;
	}
	self.lastError = error;
	if (error) {
		[IMBackupQueue.shared recordRunFailure:error];
	} else {
		[IMBackupQueue.shared recordRunSuccess];
	}
	[self completeActiveTaskWithSuccess:(error == nil)];
	if (self.runRequestedWhileBusy) {
		self.runRequestedWhileBusy = NO;
		BOOL allowCheckOnly = self.queuedCheckOnly;
		BOOL retryBackoffBypass = self.queuedRetryBackoffBypass;
		self.queuedCheckOnly = NO;
		self.queuedRetryBackoffBypass = NO;
		if ((allowCheckOnly || IMPrefs.shared.backupEnabled) && IMSession.shared.isLoggedIn) {
			[self releaseSyncRunLock];
			__weak typeof(self) weakSelf = self;
			dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf runNowAllowingCheckOnly:allowCheckOnly retryBackoffBypass:retryBackoffBypass];
			});
			return;
		}
	}
#if IM_TROLLSTORE
	if (gRunningAsDaemonProcess) {
		[self scheduleDaemonNextRun];
		if (self.daemonTimer) {
			IMDaemonArmTimer(self.daemonTimer, IMDaemonTimerInterval());
		}
		[self releaseSyncRunLock];
		return;
	}
#endif
	[self scheduleNextRun];
	[self releaseSyncRunLock];
}

- (void)finishRunAfterSessionChange {
	self.activeRunSessionFingerprint = nil;
	self.syncOwnedByDaemon = NO;
	self.lastError = nil;
	[self completeActiveTaskWithSuccess:YES];
	BOOL rerun = self.runRequestedWhileBusy;
	BOOL allowCheckOnly = self.queuedCheckOnly;
	BOOL retryBackoffBypass = self.queuedRetryBackoffBypass;
	self.runRequestedWhileBusy = NO;
	self.queuedCheckOnly = NO;
	self.queuedRetryBackoffBypass = NO;
	[self releaseSyncRunLock];
	if (rerun && (allowCheckOnly || IMPrefs.shared.backupEnabled) && IMSession.shared.isLoggedIn) {
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf runNowAllowingCheckOnly:allowCheckOnly retryBackoffBypass:retryBackoffBypass];
		});
		return;
	}
#if IM_TROLLSTORE
	if (gRunningAsDaemonProcess) {
		[self scheduleDaemonNextRun];
		if (self.daemonTimer) IMDaemonArmTimer(self.daemonTimer, IMDaemonTimerInterval());
		return;
	}
#endif
	if (IMPrefs.shared.backupEnabled && IMSession.shared.isLoggedIn) {
		[self scheduleNextRun];
	}
}

#if IM_TROLLSTORE

typedef NS_ENUM(NSInteger, IMDaemonPhotoAccess) {
	IMDaemonPhotoAccessUnknown = 0,
	IMDaemonPhotoAccessReady,
	IMDaemonPhotoAccessNotDetermined,
	IMDaemonPhotoAccessDenied,
};

static IMDaemonPhotoAccess IMDaemonPhotoLibraryAccess(void) {
	if (@available(iOS 14.0, *)) {
		PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
		if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
			return IMDaemonPhotoAccessReady;
		}
		if (status == PHAuthorizationStatusNotDetermined) return IMDaemonPhotoAccessNotDetermined;
		return IMDaemonPhotoAccessDenied;
	}
	PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
	if (status == PHAuthorizationStatusAuthorized) return IMDaemonPhotoAccessReady;
	if (status == PHAuthorizationStatusNotDetermined) return IMDaemonPhotoAccessNotDetermined;
	return IMDaemonPhotoAccessDenied;
}

static BOOL IMDaemonMayStartPhotoSync(void) {
	IMDaemonPhotoAccess access = IMDaemonPhotoLibraryAccess();
	if (access == IMDaemonPhotoAccessReady) return YES;
	if (access == IMDaemonPhotoAccessNotDetermined) {
		NSLog(@"IMBackupDaemon: waiting for foreground PhotoKit authorization");
	} else {
		NSLog(@"IMBackupDaemon: PhotoKit access is unavailable; waiting for the foreground app");
	}
	return NO;
}

static NSTimeInterval IMDaemonTimerInterval(void) {
	NSDate *now = [NSDate date];
	NSDate *next = IMBackupQueue.shared.nextRunDate;
	NSDate *attempt = IMBackupQueue.shared.nextAttemptDate;
	if (attempt && (!IMBackupDateIsDistantPast(attempt) || !next) &&
	    (!next || [attempt compare:next] == NSOrderedAscending)) next = attempt;
	if (!next) return IMBackupQueue.shared.pendingCount > 0 ? kMinimumScheduleInterval : 15.0 * 60.0;
	NSTimeInterval delta = [next timeIntervalSinceDate:now];
	if (delta < 30.0) return 30.0;
	return MIN(delta, IMBackupQueue.shared.pendingCount > 0 ? 5.0 * 60.0 : 15.0 * 60.0);
}

static void IMDaemonArmTimer(dispatch_source_t timer, NSTimeInterval interval) {
	int64_t nanoseconds = (int64_t)(MAX(interval, 1.0) * (NSTimeInterval)NSEC_PER_SEC);
	uint64_t leeway = (uint64_t)MIN(MAX(interval * 0.1, 1.0), 30.0) * NSEC_PER_SEC;
	dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, nanoseconds), DISPATCH_TIME_FOREVER, leeway);
}

- (void)scheduleDaemonNextRun {
	if (!IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		return;
	}
	NSDate *now = [NSDate date];
	NSDate *desired = IMBackupQueue.shared.nextRunDate;
	NSDate *assetRetry = IMBackupQueue.shared.nextAttemptDate;
	if (assetRetry && (!IMBackupDateIsDistantPast(assetRetry) || !desired) &&
	    (!desired || [assetRetry compare:desired] == NSOrderedAscending)) {
		desired = assetRetry;
	}
	if (!desired) {
		desired = IMBackupQueue.shared.pendingCount > 0
		    ? [now dateByAddingTimeInterval:kMinimumScheduleInterval]
		    : [now dateByAddingTimeInterval:kNormalScheduleInterval];
	}
	if ([desired timeIntervalSinceDate:now] < kMinimumScheduleInterval) {
		desired = [now dateByAddingTimeInterval:kMinimumScheduleInterval];
	}
	[IMBackupQueue.shared setNextRunDate:desired];
}
#endif

- (void)scheduleNextRun {
	if (![NSThread isMainThread]) {
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf scheduleNextRun];
		});
		return;
	}
	if (gRunningAsDaemonProcess || !self.started || !IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		return;
	}
	if (!self.registered) {
		return;
	}
	if (@available(iOS 13.0, *)) {
	NSDate *now = [NSDate date];
	NSDate *desired = IMBackupQueue.shared.nextRunDate;
	NSDate *assetRetry = IMBackupQueue.shared.nextAttemptDate;
	if (assetRetry && (!IMBackupDateIsDistantPast(assetRetry) || !desired) &&
	    (!desired || [assetRetry compare:desired] == NSOrderedAscending)) {
		desired = assetRetry;
	}
	if (!desired) {
		desired = IMBackupQueue.shared.pendingCount > 0
		    ? [now dateByAddingTimeInterval:kMinimumScheduleInterval]
		    : [now dateByAddingTimeInterval:kNormalScheduleInterval];
	}
	if ([desired timeIntervalSinceDate:now] < kMinimumScheduleInterval) {
		desired = [now dateByAddingTimeInterval:kMinimumScheduleInterval];
	}
	[IMBackupQueue.shared setNextRunDate:desired];
	[[BGTaskScheduler sharedScheduler] cancelTaskRequestWithIdentifier:IMBackupTaskIdentifier];
	BGProcessingTaskRequest *request = [[BGProcessingTaskRequest alloc] initWithIdentifier:IMBackupTaskIdentifier];
	request.requiresNetworkConnectivity = YES;
	request.requiresExternalPower = NO;
	request.earliestBeginDate = desired;
	NSError *error = nil;
	if (![[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error]) {
		NSLog(@"IMBackupDaemon: unable to schedule backup: %@", error.localizedDescription);
	}
	}
}

- (void)cancelScheduledTask {
	if (@available(iOS 13.0, *)) {
		[[BGTaskScheduler sharedScheduler] cancelTaskRequestWithIdentifier:IMBackupTaskIdentifier];
	}
	[IMBackupQueue.shared setNextRunDate:nil];
}

- (void)handleBackgroundTask:(BGTask *)task {
	if (![NSThread isMainThread]) {
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf handleBackgroundTask:task];
		});
		return;
	}
	self.activeTask = task;
	self.activeTaskCompleted = NO;
	__weak typeof(self) weakSelf = self;
	task.expirationHandler = ^{
		[IMForegroundSync.shared cancel];
		[weakSelf completeActiveTaskWithSuccess:NO];
	};
	if (!IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		[self completeActiveTaskWithSuccess:YES];
		return;
	}
	if (IMForegroundSync.shared.isRunning) {
		return;
	}
	[self runScheduled];
}

- (void)completeActiveTaskWithSuccess:(BOOL)success {
	BGTask *task = self.activeTask;
	if (!task || self.activeTaskCompleted) {
		return;
	}
	self.activeTaskCompleted = YES;
	self.activeTask = nil;
	[task setTaskCompletedWithSuccess:success];
}

- (void)stop {
	[IMForegroundSync.shared cancel];
	[self cancelScheduledTask];
	[self releaseSyncRunLock];
	self.activeRunSessionFingerprint = nil;
	self.started = NO;
	self.runRequestedWhileBusy = NO;
	self.queuedCheckOnly = NO;
	self.queuedRetryBackoffBypass = NO;
#if IM_TROLLSTORE
	[self stopPrivilegedDaemon];
#endif
}

#if IM_TROLLSTORE

- (void)startPrivilegedDaemonIfNeeded {
	if (gRunningAsDaemonProcess || !IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		return;
	}
	if (gSpawnedDaemonPID > 0 && kill(gSpawnedDaemonPID, 0) == 0) {
		return;
	}
	char executable[PATH_MAX];
	uint32_t executableSize = (uint32_t)sizeof(executable);
	if (_NSGetExecutablePath(executable, &executableSize) != 0) {
		NSLog(@"IMBackupDaemon: executable path is too long");
		return;
	}
	NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
	                                                         NSUserDomainMask,
	                                                         YES).firstObject;
	if (support.length > 0) {
		(void)setenv("IM_BACKUP_SUPPORT_PATH", support.fileSystemRepresentation, 1);
	}
	posix_spawnattr_t attributes = NULL;
	int error = posix_spawnattr_init(&attributes);
	if (error != 0) {
		NSLog(@"IMBackupDaemon: posix_spawnattr_init failed (%d)", error);
		return;
	}
	BOOL privateConfigured = YES;
	if (posix_spawnattr_set_persona_np && posix_spawnattr_set_persona_uid_np && posix_spawnattr_set_persona_gid_np) {
		error = posix_spawnattr_set_persona_np(&attributes, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
		if (error == 0) error = posix_spawnattr_set_persona_uid_np(&attributes, 0);
		if (error == 0) error = posix_spawnattr_set_persona_gid_np(&attributes, 0);
	} else {
		privateConfigured = NO;
	}
	if (error == 0 && posix_spawnattr_setprocesstype_np) {
		error = posix_spawnattr_setprocesstype_np(&attributes, POSIX_SPAWN_PROC_TYPE_DAEMON_STANDARD);
	} else if (!posix_spawnattr_setprocesstype_np) {
		privateConfigured = NO;
	}
	if (error == 0 && posix_spawnattr_setjetsam_ext) {
		error = posix_spawnattr_setjetsam_ext(&attributes, 0, 18, 96, 96);
	} else if (!posix_spawnattr_setjetsam_ext) {
		privateConfigured = NO;
	}
	short flags = 0;
	if (error == 0) {
		flags = POSIX_SPAWN_SETSID;
		error = posix_spawnattr_setflags(&attributes, flags);
	}
	if (error != 0) {
		privateConfigured = NO;
		NSLog(@"IMBackupDaemon: private spawn setup failed (%d), falling back to a normal child", error);
		posix_spawnattr_destroy(&attributes);
		attributes = NULL;
		(void)posix_spawnattr_init(&attributes);
	}
	char *arguments[] = { executable, "--daemon", NULL };
	pid_t childPID = 0;
	error = posix_spawn(&childPID, executable, NULL, &attributes, arguments, environ);
	posix_spawnattr_destroy(&attributes);
	if (error != 0) {
		NSLog(@"IMBackupDaemon: posix_spawn failed (%d)", error);
		return;
	}
	gSpawnedDaemonPID = childPID;
	NSLog(@"IMBackupDaemon: helper started (PID %d, privileged=%@)", childPID, privateConfigured ? @"yes" : @"no");
}

- (void)stopPrivilegedDaemon {
	if (gSpawnedDaemonPID > 0) {
		(void)kill(gSpawnedDaemonPID, SIGTERM);
		gSpawnedDaemonPID = 0;
	}
}

- (void)runDaemonProcess {
	[IMPrefs.shared reloadFromPersistence];
	[IMSession.shared reloadFromPersistence];
	[IMBackupQueue.shared reloadFromPersistence];
	if (!IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		return;
	}
	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	self.daemonTimer = timer;
	__weak typeof(self) weakSelf = self;
	IMDaemonArmTimer(timer, IMDaemonTimerInterval());
	dispatch_source_set_event_handler(timer, ^{
		[IMPrefs.shared reloadFromPersistence];
		[IMSession.shared reloadFromPersistence];
		[IMBackupQueue.shared reloadFromPersistence];
		if (gDaemonStopRequested || !IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
			dispatch_source_cancel(timer);
			exit(0);
			return;
		}
		if (!IMDaemonMayStartPhotoSync()) {
			IMDaemonArmTimer(timer, 5.0 * 60.0);
			return;
		}
		NSDate *scheduled = IMBackupQueue.shared.nextRunDate;
		NSDate *attempt = IMBackupQueue.shared.nextAttemptDate;
		NSDate *next = scheduled;
		if (attempt && (!IMBackupDateIsDistantPast(attempt) || !next) &&
		    (!next || [attempt compare:next] == NSOrderedAscending)) next = attempt;
		BOOL due = !next || [next compare:[NSDate date]] != NSOrderedDescending;
		if (due && scheduled && [scheduled compare:[NSDate date]] != NSOrderedDescending) {
			[IMBackupQueue.shared setNextRunDate:nil];
		}
		if (!IMForegroundSync.shared.isRunning && due) {
			[weakSelf runScheduled];
		}
		IMDaemonArmTimer(timer, IMDaemonTimerInterval());
	});
	dispatch_source_set_cancel_handler(timer, ^{
		self.daemonTimer = nil;
	});
	dispatch_resume(timer);
	signal(SIGTERM, SIG_IGN);
	signal(SIGINT, SIG_IGN);
	dispatch_source_t signalSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
	self.daemonSignalSource = signalSource;
	if (signalSource) {
		dispatch_source_set_event_handler(signalSource, ^{
			gDaemonStopRequested = 1;
			dispatch_source_cancel(timer);
			exit(0);
		});
		dispatch_source_set_cancel_handler(signalSource, ^{
			self.daemonSignalSource = nil;
		});
		dispatch_resume(signalSource);
	}
	dispatch_source_t interruptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
	self.daemonInterruptSource = interruptSource;
	if (interruptSource) {
		dispatch_source_set_event_handler(interruptSource, ^{
			gDaemonStopRequested = 1;
			dispatch_source_cancel(timer);
			exit(0);
		});
		dispatch_source_set_cancel_handler(interruptSource, ^{
			self.daemonInterruptSource = nil;
		});
		dispatch_resume(interruptSource);
	}
	NSDate *next = IMBackupQueue.shared.nextRunDate;
	NSDate *attempt = IMBackupQueue.shared.nextAttemptDate;
	if (attempt && (!IMBackupDateIsDistantPast(attempt) || !next) &&
	    (!next || [attempt compare:next] == NSOrderedAscending)) next = attempt;
	if ((!next || [next compare:[NSDate date]] != NSOrderedDescending) && IMDaemonMayStartPhotoSync()) {
		[self runScheduled];
	}
	dispatch_main();
}

#endif

@end

int IMBackupDaemonMain(void) {
#if IM_TROLLSTORE
	gRunningAsDaemonProcess = YES;
	@autoreleasepool {
		if (!IMWriteDaemonPIDFile()) {
			return 0;
		}
		signal(SIGTERM, IMDaemonSignalHandler);
		signal(SIGINT, IMDaemonSignalHandler);
		[[IMBackupDaemon shared] runDaemonProcess];
	}
	return 0;
#else
	return 0;
#endif
}
