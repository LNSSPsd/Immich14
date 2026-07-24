#import <Foundation/Foundation.h>
#import "IMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const IMForegroundSyncErrorDomain;

@interface IMForegroundSync : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) NSInteger syncedCount;        
@property (nonatomic, readonly) NSInteger pendingUploadCount; 

- (void)startWithProgress:(void (^)(NSInteger checked, NSInteger total))progress
                completion:(void (^)(NSError *_Nullable error))completion;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
