#import <Foundation/Foundation.h>
#import "IMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const IMForegroundSyncErrorDomain;

extern NSNotificationName const IMForegroundSyncProgressNotification;
extern NSNotificationName const IMForegroundSyncDidFinishNotification;
extern NSString *const IMForegroundSyncErrorUserInfoKey;
extern NSString *const IMForegroundSyncSessionFingerprintUserInfoKey;

@interface IMForegroundSync : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) NSInteger checkedCount;       
@property (nonatomic, readonly) NSInteger totalCount;         
@property (nonatomic, readonly) NSInteger syncedCount;        
@property (nonatomic, readonly) NSInteger pendingUploadCount; 
@property (nonatomic, readonly) NSInteger uploadedCount;      

- (void)startWithProgress:(void (^_Nullable)(NSInteger checked, NSInteger total))progress
                completion:(void (^_Nullable)(NSError *_Nullable error))completion;

- (void)startWithProgress:(void (^_Nullable)(NSInteger checked, NSInteger total))progress
                completion:(void (^_Nullable)(NSError *_Nullable error))completion
      ignoreRetryBackoff:(BOOL)ignoreRetryBackoff;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
