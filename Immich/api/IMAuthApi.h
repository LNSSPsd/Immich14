#import <Foundation/Foundation.h>
#import "IMAdminUser.h"
#import "IMOAuth.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAuthApi : NSObject

+ (void)signUpAdminWithBaseURL:(NSURL *)baseURL
                          email:(NSString *)email
                           name:(NSString *)name
                        password:(NSString *)password
                      completion:(void (^)(IMAdminUser *_Nullable user,
                                           NSError *_Nullable error))completion;

+ (void)loginWithBaseURL:(NSURL *)baseURL
                    email:(NSString *)email
                 password:(NSString *)password
        responseCompletion:(void (^)(IMOAuthLoginResponse *_Nullable response,
                                     NSError *_Nullable error))completion;

+ (void)loginWithBaseURL:(NSURL *)baseURL
                    email:(NSString *)email
                 password:(NSString *)password
               completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)loginWithBaseURL:(NSURL *)baseURL
                   apiKey:(NSString *)apiKey
               completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)validateTokenWithCompletion:(void (^)(BOOL valid))completion;

+ (void)validateSessionWithCompletion:(void (^)(BOOL valid, BOOL authRejected))completion;

+ (void)logoutWithCompletion:(void (^)(void))completion;

+ (void)unlockSessionWithPIN:(NSString *)pin
                   completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)lockSessionWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)setupPIN:(NSString *)pin completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)changePIN:(NSString *)newPIN
       currentPIN:(nullable NSString *)currentPIN
         password:(nullable NSString *)password
       completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)resetPINWithPassword:(nullable NSString *)password
                          pin:(nullable NSString *)pin
                   completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)authStatusWithCompletion:(void (^)(BOOL pinConfigured,
                                            BOOL isElevated,
                                            NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
