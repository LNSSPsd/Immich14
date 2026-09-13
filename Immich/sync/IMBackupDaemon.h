#import <Foundation/Foundation.h>
#import "common.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMBackupTaskIdentifier;

@interface IMBackupDaemon : NSObject

+ (instancetype)shared;

- (void)registerBackgroundTasks;

- (void)start;

- (void)applicationDidEnterBackground;
- (void)applicationWillEnterForeground;

- (void)runNow;
- (void)runCheckNow;
- (void)runScheduled;
- (void)backupPreferenceDidChange;
- (void)stop;

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly, nullable) NSDate *nextRunDate;
@property (nonatomic, readonly) NSInteger consecutiveFailures;
@property (nonatomic, readonly) NSUInteger pendingCount;

#if IM_TROLLSTORE
- (void)startPrivilegedDaemonIfNeeded;
- (void)stopPrivilegedDaemon;
- (NSString *)helperStatusDescription;
- (NSString *)helperLogText;
#endif

@end

int IMBackupDaemonMain(void);

BOOL IMBackupDaemonIsDaemonProcess(void);

#if IM_TROLLSTORE
void IMBackupHelperLogEvent(NSString *message);
#endif

NS_ASSUME_NONNULL_END
