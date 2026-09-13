#import "IMBackupDaemon.h"
#import "IMBackupQueue.h"
#import "IMForegroundSync.h"
#import "IMPrefs.h"
#import "IMSession.h"
#import "IMApiClient.h"
#import "IMServerApi.h"
#import "common.h"
#import <Network/Network.h>
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
#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <notify.h>
#include <signal.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>

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
static void IMDaemonArmTimer(dispatch_source_t timer, NSTimeInterval interval);
#endif

#if IM_TROLLSTORE
static volatile sig_atomic_t gDaemonStopRequested = 0;
static pid_t gSpawnedDaemonPID = 0;
static NSString *gDaemonLastOutcome = nil;
static NSString *gDaemonSpawnNote = nil;

static int gHelperLogFD = -1;
static NSString *const kHelperLogFileName = @"immich-backup-helper.log";
static const off_t kHelperLogMaxBytes = 256 * 1024;

static NSString *IMHelperLogPath(void) {
	return [IMBackupSupportDirectory() stringByAppendingPathComponent:kHelperLogFileName];
}

static void IMHelperLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void IMHelperLog(NSString *format, ...) {
	va_list arguments;
	va_start(arguments, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
	va_end(arguments);
	NSLog(@"IMBackupDaemon: %@", message);
	if (gHelperLogFD < 0) {
		gHelperLogFD = open(IMHelperLogPath().fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
		if (gHelperLogFD < 0) return;
	}
	if (lseek(gHelperLogFD, 0, SEEK_END) > kHelperLogMaxBytes) {
		(void)ftruncate(gHelperLogFD, 0); 
	}
	static NSDateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateFormat = @"MM-dd HH:mm:ss";
	});
	NSString *line = [NSString stringWithFormat:@"%@ %@[%d] %@\n", [formatter stringFromDate:[NSDate date]],
	                                           gRunningAsDaemonProcess ? @"helper" : @"app", getpid(), message];
	NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
	(void)write(gHelperLogFD, data.bytes, data.length);
}

static void IMHelperFatalSignalHandler(int signalNumber) {
	if (gHelperLogFD >= 0) {
		char buffer[48] = "crash: fatal signal ";
		size_t length = strlen(buffer);
		char digits[4];
		int count = 0, value = signalNumber;
		do {
			digits[count++] = (char)('0' + value % 10);
			value /= 10;
		} while (value > 0 && count < 3);
		while (count > 0) buffer[length++] = digits[--count];
		buffer[length++] = '\n';
		(void)write(gHelperLogFD, buffer, length);
	}
	signal(signalNumber, SIG_DFL);
	raise(signalNumber);
}

static void IMHelperUncaughtExceptionHandler(NSException *exception) {
	IMHelperLog(@"crash: uncaught %@: %@", exception.name, exception.reason);
}

static volatile sig_atomic_t gLastSignalSender = 0;

static void IMHelperTerminationSignalHandler(int signalNumber, siginfo_t *info, void *context) {
	(void)signalNumber;
	(void)context;
	gLastSignalSender = info ? info->si_pid : 0;
	gDaemonStopRequested = 1;
}

static NSString *IMProcessDescription(pid_t pid) {
	if (pid <= 0) return @"unknown sender";
	int (*pidPath)(int, void *, uint32_t) = (int (*)(int, void *, uint32_t))dlsym(RTLD_DEFAULT, "proc_pidpath");
	char path[PATH_MAX];
	if (pidPath && pidPath(pid, path, sizeof(path)) > 0) {
		return [NSString stringWithFormat:@"pid %d (%s)", pid, path];
	}
	return [NSString stringWithFormat:@"pid %d", pid];
}

static NSArray<NSString *> *IMHelperLogTail(NSUInteger maxLines) {
	NSData *data = [NSData dataWithContentsOfFile:IMHelperLogPath()];
	if (data.length == 0) return @[];
	NSUInteger length = MIN(data.length, (NSUInteger)8192);
	NSData *tail = [data subdataWithRange:NSMakeRange(data.length - length, length)];
	NSString *text = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding]
	    ?: [[NSString alloc] initWithData:tail encoding:NSISOLatin1StringEncoding];
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
		if (line.length > 0) [lines addObject:line];
	}
	if (lines.count > maxLines) {
		[lines removeObjectsInRange:NSMakeRange(0, lines.count - maxLines)];
	}
	return lines;
}

static void IMHelperLogAtExit(void) {
	IMHelperLog(@"exit: process exit()");
}

typedef struct {
	pid_t pid;
	int32_t priority;
	uint64_t user_data;
	int32_t limit; 
	uint32_t state;
} IMMemorystatusPriorityEntry;

typedef struct {
	int32_t priority;
	uint64_t user_data;
} IMMemorystatusPriorityProperties;

static int32_t IMDaemonImportantJetsamPriority(void) {
	if (@available(iOS 16.0, *)) {
		return 180;
	}
	return 18;
}

static int (*IMMemorystatusControl(void))(uint32_t, int32_t, uint32_t, void *, size_t) {
	return (int (*)(uint32_t, int32_t, uint32_t, void *, size_t))dlsym(RTLD_DEFAULT, "memorystatus_control");
}

static BOOL IMDaemonReadJetsamEntry(IMMemorystatusPriorityEntry *entry) {
	int (*control)(uint32_t, int32_t, uint32_t, void *, size_t) = IMMemorystatusControl();
	if (!control) return NO;
	memset(entry, 0, sizeof(*entry));
	return control(1 /* MEMORYSTATUS_CMD_GET_PRIORITY_LIST */, getpid(), 0, entry, sizeof(*entry)) >= (int)sizeof(*entry);
}

static NSString *IMDaemonEnsureJetsamPriority(void) {
	IMMemorystatusPriorityEntry entry;
	if (!IMDaemonReadJetsamEntry(&entry)) {
		return [NSString stringWithFormat:@"jetsam query failed (%s)", strerror(errno)];
	}
	int32_t target = IMDaemonImportantJetsamPriority();
	NSString *raised = @"";
	if (entry.priority < target) {
		IMMemorystatusPriorityProperties properties = { target, 0 };
		int32_t before = entry.priority;
		if (IMMemorystatusControl()(2 /* MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES */, getpid(), 0, &properties, sizeof(properties)) == 0 &&
		    IMDaemonReadJetsamEntry(&entry)) {
			raised = [NSString stringWithFormat:@" (raised from %d)", before];
		} else {
			raised = [NSString stringWithFormat:@" (raise to %d failed: %s)", target, strerror(errno)];
		}
	}
	return [NSString stringWithFormat:@"jetsam priority %d%@, limit %d MB, state 0x%x", entry.priority, raised, entry.limit, entry.state];
}

static NSString *IMAppSandboxDescription(void) {
	int (*check)(pid_t, const char *, int, ...) = (int (*)(pid_t, const char *, int, ...))dlsym(RTLD_DEFAULT, "sandbox_check");
	if (!check) {
		return _(@"sandbox state unknown");
	}
	return check(getpid(), NULL, 0) ? _(@"sandboxed") : _(@"not sandboxed");
}
static const char *const kDaemonStopNotification = "com.lns.immich-ios-14.backup-helper.stop";
static int gDaemonRunFD = -1;
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
	if (gDaemonRunFD >= 0) {
		if (path.length > 0) {
			(void)unlink(path.fileSystemRepresentation);
		}
		(void)flock(gDaemonRunFD, LOCK_UN);
		close(gDaemonRunFD);
		gDaemonRunFD = -1;
	} else if (path.length > 0) {
		(void)unlink(path.fileSystemRepresentation);
	}
}

static pid_t IMReadDaemonPID(void) {
	NSString *path = IMDaemonRunFilePath();
	if (path.length == 0) {
		return 0;
	}
	int fd = open(path.fileSystemRepresentation, O_RDONLY);
	if (fd < 0) {
		return 0;
	}
	pid_t pid = 0;
	ssize_t bytes = read(fd, &pid, sizeof(pid));
	close(fd);
	return bytes == sizeof(pid) && pid > 0 ? pid : 0;
}

static NSString *IMBackupHelperBuildIdentifier(void) {
	static NSString *identifier;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *uuid = @"no-uuid";
		const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
		if (header && header->magic == MH_MAGIC_64) {
			const struct load_command *command = (const struct load_command *)(header + 1);
			for (uint32_t i = 0; i < header->ncmds; i++) {
				if (command->cmd == LC_UUID) {
					uuid = [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
					break;
				}
				command = (const struct load_command *)((const char *)command + command->cmdsize);
			}
		}
		identifier = [NSString stringWithFormat:@"%s (%s) %@", APP_VERSION_STRING, APP_COMMIT_HASH, uuid];
	});
	return identifier;
}

static NSArray<NSString *> *IMReadDaemonMarkerLines(void) {
	NSString *path = IMDaemonRunFilePath();
	if (path.length == 0) {
		return @[];
	}
	int fd = open(path.fileSystemRepresentation, O_RDONLY);
	if (fd < 0) {
		return @[];
	}
	if (lseek(fd, sizeof(pid_t), SEEK_SET) < 0) {
		close(fd);
		return @[];
	}
	char buffer[256];
	ssize_t bytes = read(fd, buffer, sizeof(buffer) - 1);
	close(fd);
	if (bytes <= 0) {
		return @[];
	}
	buffer[bytes] = '\0';
	NSString *text = [NSString stringWithUTF8String:buffer];
	return text.length > 0 ? [text componentsSeparatedByString:@"\n"] : @[];
}

static NSString *_Nullable IMReadDaemonBuildIdentifier(void) {
	NSString *identifier = IMReadDaemonMarkerLines().firstObject;
	return identifier.length > 0 ? identifier : nil;
}

static NSString *_Nullable IMReadDaemonUser(void) {
	NSArray<NSString *> *lines = IMReadDaemonMarkerLines();
	return lines.count > 1 && lines[1].length > 0 ? lines[1] : nil;
}

static BOOL IMDaemonMarkerIsLocked(void) {
	NSString *path = IMDaemonRunFilePath();
	if (path.length == 0) {
		return NO;
	}
	int fd = open(path.fileSystemRepresentation, O_RDONLY);
	if (fd < 0) {
		return NO;
	}
	if (flock(fd, LOCK_EX | LOCK_NB) == 0) {
		(void)flock(fd, LOCK_UN);
		close(fd);
		return NO;
	}
	int lockError = errno;
	close(fd);
	return lockError == EWOULDBLOCK || lockError == EAGAIN;
}

static BOOL IMRemoveStaleDaemonRunFile(void) {
	NSString *path = IMDaemonRunFilePath();
	if (path.length == 0) {
		return YES;
	}
	int fd = open(path.fileSystemRepresentation, O_RDONLY);
	if (fd < 0) {
		if (errno == EACCES) {
			return unlink(path.fileSystemRepresentation) == 0 || errno == ENOENT;
		}
		return errno == ENOENT;
	}
	if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
		close(fd);
		return NO;
	}
	(void)unlink(path.fileSystemRepresentation);
	(void)flock(fd, LOCK_UN);
	close(fd);
	return YES;
}

static BOOL IMWriteDaemonPIDFile(void) {
	NSString *path = IMDaemonRunFilePath();
	int fd = open(path.fileSystemRepresentation, O_RDWR | O_CREAT, 0600);
	if (fd < 0) {
		NSLog(@"IMBackupDaemon: cannot create run marker %@ (%s)", path, strerror(errno));
		return NO;
	}
	if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
		int lockError = errno;
		pid_t oldPID = 0;
		if (lockError == EWOULDBLOCK || lockError == EAGAIN) {
			(void)lseek(fd, 0, SEEK_SET);
			(void)read(fd, &oldPID, sizeof(oldPID));
			NSLog(@"IMBackupDaemon: daemon already running%@", oldPID > 0 ? [NSString stringWithFormat:@" (PID %d)", oldPID] : @"");
		} else {
			NSLog(@"IMBackupDaemon: cannot lock run marker %@ (%s)", path, strerror(lockError));
		}
		close(fd);
		return NO;
	}
	pid_t pid = getpid();
	NSString *markerText = [NSString stringWithFormat:@"%@\n%d", IMBackupHelperBuildIdentifier(), (int)geteuid()];
	NSData *identifierData = [markerText dataUsingEncoding:NSUTF8StringEncoding];
	if (fchmod(fd, 0644) != 0 || ftruncate(fd, 0) != 0 || lseek(fd, 0, SEEK_SET) < 0 || write(fd, &pid, sizeof(pid)) != sizeof(pid) ||
	    (identifierData.length > 0 && write(fd, identifierData.bytes, identifierData.length) != (ssize_t)identifierData.length)) {
		int writeError = errno;
		(void)flock(fd, LOCK_UN);
		close(fd);
		(void)unlink(path.fileSystemRepresentation);
		NSLog(@"IMBackupDaemon: cannot write run marker %@ (%s)", path, strerror(writeError));
		return NO;
	}
	(void)fsync(fd);
	gDaemonRunFD = fd;
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
@property (nonatomic, strong, nullable) nw_path_monitor_t daemonPathMonitor;
@property (nonatomic) BOOL daemonNetworkSatisfied;
@property (nonatomic) BOOL daemonNetworkMetered;
@property (nonatomic) BOOL daemonPingInFlight;
@property (nonatomic, copy, nullable) NSString *daemonLibrarySeenFingerprint;
- (void)daemonArm:(NSTimeInterval)interval;
- (void)daemonArmAfterRunWithError:(nullable NSError *)error;
- (void)daemonEvaluateWithReason:(NSString *)reason;
#endif
@property (nonatomic) int syncRunLockFD;
- (BOOL)acquireSyncRunLock;
- (void)releaseSyncRunLock;
- (void)runNowAllowingCheckOnly:(BOOL)allowCheckOnly retryBackoffBypass:(BOOL)retryBackoffBypass;
- (void)finishRunAfterSessionChange;
@end

BOOL IMBackupDaemonIsDaemonProcess(void) {
	return gRunningAsDaemonProcess;
}

#if IM_TROLLSTORE
void IMBackupHelperLogEvent(NSString *message) {
	IMHelperLog(@"%@", message);
}
#endif

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
	NSString *activeFingerprint = self.activeRunSessionFingerprint;
	if (activeFingerprint.length > 0 &&
	    ![activeFingerprint isEqualToString:IMBackupSessionFingerprint()]) {
		[IMForegroundSync.shared cancel];
	}
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
#if IM_TROLLSTORE
	if (gRunningAsDaemonProcess) {
		[self daemonEvaluateWithReason:@"photo library changed"];
		return;
	}
#endif
	[self runNowAllowingCheckOnly:NO retryBackoffBypass:NO];
}

- (void)runNowAllowingCheckOnly:(BOOL)allowCheckOnly retryBackoffBypass:(BOOL)retryBackoffBypass {
#if IM_TROLLSTORE
	if (gRunningAsDaemonProcess) {
		IMHelperLog(@"run requested (running=%d, failures=%ld, next=%@)", IMForegroundSync.shared.isRunning,
		            (long)IMBackupQueue.shared.consecutiveRunFailures, IMBackupQueue.shared.nextRunDate ?: @"none");
	}
#endif
	if ((!allowCheckOnly && !IMPrefs.shared.backupEnabled) || !IMSession.shared.isLoggedIn) {
		return;
	}
	if (!retryBackoffBypass && IMBackupQueue.shared.consecutiveRunFailures > 0) {
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
#if IM_TROLLSTORE
		if (gRunningAsDaemonProcess) IMHelperLog(@"run skipped: sync lock held by the app");
#endif
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
#if IM_TROLLSTORE
	if (gRunningAsDaemonProcess) IMHelperLog(@"run: started");
#endif
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
		IMHelperLog(@"run: finished%@", error ? [@" with error: " stringByAppendingString:error.localizedDescription ?: @"?"] : @"");
		[self scheduleDaemonNextRun];
		[self daemonArmAfterRunWithError:error];
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
		[self daemonArm:IMDaemonIdleInterval()];
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

static const NSTimeInterval kDaemonIdlePollInterval = 5.0 * 60.0;
static const NSTimeInterval kDaemonUnreachableInterval = 2.0 * 60.0;
static const NSTimeInterval kDaemonMaxErrorInterval = 10.0 * 60.0;

static NSTimeInterval IMDaemonIdleInterval(void) {
	NSDate *attempt = IMBackupQueue.shared.nextAttemptDate;
	if (attempt && !IMBackupDateIsDistantPast(attempt)) {
		return MIN(MAX([attempt timeIntervalSinceNow], 30.0), kDaemonIdlePollInterval);
	}
	return kDaemonIdlePollInterval;
}

static NSString *IMDaemonLibraryFingerprint(void) {
	PHFetchOptions *options = [[PHFetchOptions alloc] init];
	options.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO] ];
	PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithOptions:options];
	return [NSString stringWithFormat:@"%lu|%@", (unsigned long)assets.count, assets.firstObject.localIdentifier ?: @""];
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
	pid_t knownPID = IMReadDaemonPID();
	if (IMDaemonMarkerIsLocked()) {
		NSString *runningIdentifier = IMReadDaemonBuildIdentifier();
		if (![runningIdentifier isEqualToString:IMBackupHelperBuildIdentifier()]) {
			if (knownPID > 0 && knownPID != getpid()) {
				IMHelperLog(@"stopping stale helper (PID %d, build %@) after reinstall",
				            knownPID, runningIdentifier ?: @"unknown");
				(void)kill(knownPID, SIGTERM);
			}
			(void)notify_post(kDaemonStopNotification);
			return;
		}
		if (knownPID > 0 && knownPID != getpid()) {
			gSpawnedDaemonPID = knownPID;
		}
		return;
	}
	if (!IMRemoveStaleDaemonRunFile()) {
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
	if (support.length == 0) {
		support = NSTemporaryDirectory();
	}
	if (support.length > 0) {
		(void)setenv("IM_BACKUP_SUPPORT_PATH", support.fileSystemRepresentation, 1);
	}
	[IMSession.shared publishSharedState];
	[IMPrefs.shared publishSharedState];
	posix_spawnattr_t attributes = NULL;
	int error = posix_spawnattr_init(&attributes);
	if (error != 0) {
		NSLog(@"IMBackupDaemon: posix_spawnattr_init failed (%d)", error);
		gDaemonLastOutcome = [NSString stringWithFormat:_(@"Couldn't start: %s"), strerror(error)];
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
		error = posix_spawnattr_setjetsam_ext(&attributes, 0, IMDaemonImportantJetsamPriority(), 96, 96);
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
	NSString *personaFailure = nil;
	if (error != 0 && privateConfigured) {
		personaFailure = [NSString stringWithFormat:_(@"persona spawn: %s"), strerror(error)];
		NSLog(@"IMBackupDaemon: persona posix_spawn failed (%d: %s); retrying as a plain child", error, strerror(error));
		privateConfigured = NO;
		error = posix_spawn(&childPID, executable, NULL, NULL, arguments, environ);
	}
	if (error != 0) {
		IMHelperLog(@"posix_spawn failed (%d: %s), app %@", error, strerror(error), IMAppSandboxDescription());
		gDaemonLastOutcome = [NSString stringWithFormat:_(@"Couldn't start: %@%s (app %@)"),
		                                                personaFailure ? [personaFailure stringByAppendingString:@"; plain spawn: "] : @"",
		                                                strerror(error), IMAppSandboxDescription()];
		gDaemonSpawnNote = nil;
		return;
	}
	gDaemonLastOutcome = nil;
	gDaemonSpawnNote = personaFailure ? [NSString stringWithFormat:_(@"Plain child, not daemonized (%@)"), personaFailure] : nil;
	gSpawnedDaemonPID = childPID;
	IMHelperLog(@"spawned helper pid %d (privileged=%@)", childPID, privateConfigured ? @"yes" : @"no");
}

- (void)stopPrivilegedDaemon {
	BOOL markerLocked = IMDaemonMarkerIsLocked();
	pid_t pid = IMReadDaemonPID();
	if (markerLocked && pid > 0 && pid != getpid()) {
		IMHelperLog(@"asking helper pid %d to stop", pid);
		if (kill(pid, SIGTERM) != 0 && errno == ESRCH) {
			(void)IMRemoveStaleDaemonRunFile();
		}
		(void)notify_post(kDaemonStopNotification);
	} else if (!markerLocked) {
		(void)IMRemoveStaleDaemonRunFile();
	}
	gSpawnedDaemonPID = 0;
}

- (NSString *)helperStatusDescription {
	if (gSpawnedDaemonPID > 0) {
		int status = 0;
		pid_t reaped = waitpid(gSpawnedDaemonPID, &status, WNOHANG);
		if (reaped == gSpawnedDaemonPID) {
			if (WIFSIGNALED(status)) {
				gDaemonLastOutcome = [NSString stringWithFormat:_(@"Killed by signal %d"), WTERMSIG(status)];
			} else if (WIFEXITED(status)) {
				gDaemonLastOutcome = [NSString stringWithFormat:_(@"Exited with status %d"), WEXITSTATUS(status)];
			}
			gSpawnedDaemonPID = 0;
		} else if (reaped < 0 && errno == ECHILD) {
			gSpawnedDaemonPID = 0; 
		}
	}
	if (IMDaemonMarkerIsLocked()) {
		pid_t pid = IMReadDaemonPID();
		NSString *uid = IMReadDaemonUser();
		NSString *user = !uid ? _(@"unknown user") : [uid isEqualToString:@"0"] ? @"root" : [NSString stringWithFormat:@"uid %@", uid];
		if (![IMReadDaemonBuildIdentifier() isEqualToString:IMBackupHelperBuildIdentifier()]) {
			return [NSString stringWithFormat:_(@"Old build running (PID %d, %@)"), (int)pid, user];
		}
		NSString *running = [NSString stringWithFormat:_(@"Running (PID %d, %@)"), (int)pid, user];
		return gDaemonSpawnNote ? [NSString stringWithFormat:@"%@\n%@", running, gDaemonSpawnNote] : running;
	}
	if (!IMPrefs.shared.backupEnabled || !IMSession.shared.isLoggedIn) {
		return _(@"Off");
	}
	if (gDaemonLastOutcome) {
		return gDaemonLastOutcome;
	}
	NSArray<NSString *> *tail = IMHelperLogTail(2);
	NSString *last = tail.lastObject;
	if ([last containsString:@"exit: process exit()"] && tail.count > 1 && [tail.firstObject containsString:@"exit:"]) {
		last = tail.firstObject; 
	}
	if ([last containsString:@"exit:"] || [last containsString:@"crash:"]) {
		return [NSString stringWithFormat:_(@"Not running. Last: %@"), last];
	}
	if ([last containsString:@"helper["]) {
		return [NSString stringWithFormat:_(@"Not running: killed from outside (jetsam/system) after: %@"), last];
	}
	return _(@"Not running");
}

- (NSString *)helperLogText {
	NSArray<NSString *> *lines = IMHelperLogTail(80);
	return lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : _(@"(empty)");
}

static NSString *_Nullable IMDaemonExitReason(void) {
	if (gDaemonStopRequested) return @"stop requested";
	if (!IMPrefs.shared.backupEnabled) return @"backup is off";
	if (!IMSession.shared.isLoggedIn) {
		return [NSString stringWithFormat:@"logged out (keychain status %ld)", (long)IMSession.shared.lastKeychainStatus];
	}
	return nil;
}

- (void)runDaemonProcess {
	[IMPrefs.shared reloadFromPersistence];
	[IMSession.shared reloadFromPersistence];
	[IMBackupQueue.shared reloadFromPersistence];
	NSString *startupExit = IMDaemonExitReason();
	if (startupExit) {
		IMHelperLog(@"exit: %@", startupExit);
		return;
	}
	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	self.daemonTimer = timer;
	__weak typeof(self) weakSelf = self;
	IMDaemonArmTimer(timer, kDaemonIdlePollInterval);
	dispatch_source_set_event_handler(timer, ^{
		[weakSelf daemonEvaluateWithReason:@"poll"];
	});
	dispatch_source_set_cancel_handler(timer, ^{
		self.daemonTimer = nil;
	});
	dispatch_resume(timer);
	struct sigaction termination;
	memset(&termination, 0, sizeof(termination));
	termination.sa_sigaction = IMHelperTerminationSignalHandler;
	termination.sa_flags = SA_SIGINFO;
	sigemptyset(&termination.sa_mask);
	sigaction(SIGTERM, &termination, NULL);
	sigaction(SIGINT, &termination, NULL);
	dispatch_source_t signalSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
	self.daemonSignalSource = signalSource;
	if (signalSource) {
		dispatch_source_set_event_handler(signalSource, ^{
			gDaemonStopRequested = 1;
			IMHelperLog(@"exit: SIGTERM from %@", IMProcessDescription((pid_t)gLastSignalSender));
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
			IMHelperLog(@"exit: SIGINT from %@", IMProcessDescription((pid_t)gLastSignalSender));
			dispatch_source_cancel(timer);
			exit(0);
		});
		dispatch_source_set_cancel_handler(interruptSource, ^{
			self.daemonInterruptSource = nil;
		});
		dispatch_resume(interruptSource);
	}
	int stopToken = NOTIFY_TOKEN_INVALID;
	uint32_t notifyStatus = notify_register_dispatch(kDaemonStopNotification, &stopToken, dispatch_get_main_queue(), ^(int token) {
		(void)token;
		gDaemonStopRequested = 1;
		IMHelperLog(@"exit: stop requested by the app");
		dispatch_source_cancel(timer);
		exit(0);
	});
	if (notifyStatus != NOTIFY_STATUS_OK) {
		IMHelperLog(@"cannot register stop notification (%u)", notifyStatus);
	}
	nw_path_monitor_t monitor = nw_path_monitor_create();
	nw_path_monitor_set_queue(monitor, dispatch_get_main_queue());
	nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
		IMBackupDaemon *strongSelf = weakSelf;
		if (!strongSelf) return;
		BOOL satisfied = nw_path_get_status(path) == nw_path_status_satisfied;
		BOOL metered = nw_path_uses_interface_type(path, nw_interface_type_cellular) || nw_path_is_expensive(path);
		if (satisfied == strongSelf.daemonNetworkSatisfied && metered == strongSelf.daemonNetworkMetered) return;
		strongSelf.daemonNetworkSatisfied = satisfied;
		strongSelf.daemonNetworkMetered = metered;
		IMHelperLog(@"network: %@", !satisfied ? @"none" : metered ? @"metered (mobile data)" : @"usable");
		if (satisfied) [strongSelf daemonEvaluateWithReason:@"network changed"];
	});
	nw_path_monitor_start(monitor);
	self.daemonPathMonitor = monitor;
	(void)IMForegroundSync.shared;
	IMHelperLog(@"ready");
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf daemonEvaluateWithReason:@"start"];
	});
	[[NSRunLoop mainRunLoop] addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
	[[NSRunLoop mainRunLoop] run];
}

- (void)daemonArm:(NSTimeInterval)interval {
	if (self.daemonTimer) {
		IMDaemonArmTimer(self.daemonTimer, interval);
	}
}

- (void)daemonArmAfterRunWithError:(nullable NSError *)error {
	NSTimeInterval interval = IMDaemonIdleInterval();
	if (error) {
		NSInteger failures = MAX(IMBackupQueue.shared.consecutiveRunFailures, (NSInteger)1);
		interval = MIN(kDaemonUnreachableInterval * (NSTimeInterval)(1 << MIN(failures - 1, (NSInteger)4)), kDaemonMaxErrorInterval);
	}
	IMHelperLog(@"next check in %.0fs", interval);
	[self daemonArm:interval];
}

- (void)daemonEvaluateWithReason:(NSString *)reason {
	[IMPrefs.shared reloadFromPersistence];
	[IMSession.shared reloadFromPersistence];
	[IMBackupQueue.shared reloadFromPersistence];
	NSString *exitReason = IMDaemonExitReason();
	if (exitReason) {
		IMHelperLog(@"exit: %@", exitReason);
		exit(0);
	}
	if (IMForegroundSync.shared.isRunning || self.daemonPingInFlight) {
		return; 
	}
	if (!IMDaemonMayStartPhotoSync()) {
		[self daemonArm:kDaemonIdlePollInterval];
		return;
	}
	if (!self.daemonNetworkSatisfied || (IMPrefs.shared.wifiOnlyUpload && self.daemonNetworkMetered)) {
		IMHelperLog(@"%@: waiting for %@", reason, self.daemonNetworkSatisfied ? @"a non-mobile network" : @"a network");
		[self daemonArm:kDaemonIdlePollInterval]; 
		return;
	}
	NSString *fingerprint = IMDaemonLibraryFingerprint();
	NSInteger failures = IMBackupQueue.shared.consecutiveRunFailures;
	NSDate *attempt = IMBackupQueue.shared.nextAttemptDate;
	NSDate *cadence = IMBackupQueue.shared.nextRunDate;
	BOOL libraryChanged = ![fingerprint isEqualToString:self.daemonLibrarySeenFingerprint ?: @""];
	BOOL retryDue = attempt && !IMBackupDateIsDistantPast(attempt) && [attempt timeIntervalSinceNow] <= 0;
	BOOL cadenceDue = failures == 0 && cadence && [cadence timeIntervalSinceNow] <= 0;
	if (!libraryChanged && failures == 0 && !retryDue && !cadenceDue) {
		[self daemonArm:IMDaemonIdleInterval()];
		return;
	}
	self.daemonPingInFlight = YES;
	__weak typeof(self) weakSelf = self;
	[IMServerApi pingWithCompletion:^(BOOL reachable, NSError *_Nullable error) {
		IMBackupDaemon *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.daemonPingInFlight = NO;
		if (!reachable) {
			IMHelperLog(@"%@: server unreachable (%@), ping again in %.0fs", reason,
			            error.localizedDescription ?: @"no response", kDaemonUnreachableInterval);
			[strongSelf daemonArm:kDaemonUnreachableInterval];
			return;
		}
		strongSelf.daemonLibrarySeenFingerprint = fingerprint;
		IMHelperLog(@"%@: server reachable, running (library %@, failures %ld%@)", reason,
		            libraryChanged ? @"changed" : @"unchanged", (long)failures, retryDue ? @", retry due" : @"");
		[strongSelf runNowAllowingCheckOnly:NO retryBackoffBypass:failures > 0];
		if (!IMForegroundSync.shared.isRunning) {
			[strongSelf daemonArm:60.0]; 
		}
	}];
}

#endif

@end

#if IM_TROLLSTORE
static void IMDaemonDropToSupportDirectoryOwner(void) {
	if (geteuid() != 0) {
		return;
	}
	const char *support = getenv("IM_BACKUP_SUPPORT_PATH");
	struct stat info;
	if (!support || support[0] == '\0' || stat(support, &info) != 0) {
		NSLog(@"IMBackupDaemon: support directory unavailable; staying root");
		return;
	}
	if (info.st_uid == 0) {
		return;
	}
	gid_t gid = info.st_gid;
	if (setgroups(1, &gid) != 0 || setgid(gid) != 0 || setuid(info.st_uid) != 0) {
		NSLog(@"IMBackupDaemon: cannot switch to uid %d (%s); staying root", (int)info.st_uid, strerror(errno));
	}
}
#endif

int IMBackupDaemonMain(void) {
#if IM_TROLLSTORE
	gRunningAsDaemonProcess = YES;
	@autoreleasepool {
		NSString *jetsam = IMDaemonEnsureJetsamPriority(); 
		IMDaemonDropToSupportDirectoryOwner();
		for (int fatal = 0; fatal < 6; fatal++) {
			static const int kFatalSignals[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGFPE, SIGTRAP };
			signal(kFatalSignals[fatal], IMHelperFatalSignalHandler);
		}
		NSSetUncaughtExceptionHandler(IMHelperUncaughtExceptionHandler);
		IMHelperLog(@"start: uid %d, euid %d, parent %d, %@, build %@", (int)getuid(), (int)geteuid(), (int)getppid(),
		            jetsam, IMBackupHelperBuildIdentifier());
		atexit(IMHelperLogAtExit);
		if (!IMWriteDaemonPIDFile()) {
			IMHelperLog(@"exit: another helper holds the run marker");
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
