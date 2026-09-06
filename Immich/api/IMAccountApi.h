#import <Foundation/Foundation.h>
#import "IMSessionInfo.h"
#import "IMSessionCreate.h"
#import "IMAPIKey.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAccountApi : NSObject
+ (void)changePassword:(NSString *)currentPassword
           newPassword:(NSString *)newPassword
      invalidateSessions:(BOOL)invalidateSessions
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)sessionsWithCompletion:(void (^)(NSArray<IMSessionInfo *> *_Nullable sessions, NSError *_Nullable error))completion;
+ (void)createSessionWithRequest:(IMSessionCreateRequest *)request
                       completion:(void (^)(IMSessionInfo *_Nullable session,
                                             NSError *_Nullable error))completion;
+ (void)createSessionWithDeviceOS:(nullable NSString *)deviceOS
                        deviceType:(nullable NSString *)deviceType
                         duration:(nullable NSNumber *)duration
                        completion:(void (^)(IMSessionInfo *_Nullable session,
                                              NSError *_Nullable error))completion;
+ (void)updateSessionId:(NSString *)sessionId
       pendingSyncReset:(BOOL)pendingSyncReset
              completion:(void (^)(IMSessionInfo *_Nullable session,
                                    NSError *_Nullable error))completion;
+ (void)requestSyncResetForSessionId:(NSString *)sessionId
                          completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)deleteSessionId:(NSString *)sessionId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)lockSessionId:(NSString *)sessionId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)deleteAllOtherSessionsWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)apiKeysWithCompletion:(void (^)(NSArray<IMAPIKey *> *_Nullable keys, NSError *_Nullable error))completion;
+ (void)currentAPIKeyWithCompletion:(void (^)(IMAPIKey *_Nullable key, NSError *_Nullable error))completion;
+ (void)createAPIKeyNamed:(NSString *)name
	             permissions:(NSArray<NSString *> *)permissions
	             completion:(void (^)(IMAPIKey *_Nullable key, NSString *_Nullable secret, NSError *_Nullable error))completion;
+ (void)updateAPIKeyId:(NSString *)keyId
	                 name:(NSString *)name
	          permissions:(NSArray<NSString *> *)permissions
	          completion:(void (^)(IMAPIKey *_Nullable key, NSError *_Nullable error))completion;
+ (void)deleteAPIKeyId:(NSString *)keyId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
