#import <Foundation/Foundation.h>
#import "IMOAuth.h"
#import "IMUser.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMOAuthApi : NSObject

+ (NSString *)nativeRedirectURI;

+ (void)authorizeWithBaseURL:(NSURL *)baseURL
                  redirectURI:(NSString *)redirectURI
                         state:(nullable NSString *)state
                 codeChallenge:(nullable NSString *)codeChallenge
                    completion:(void (^)(IMOAuthAuthorizeResponse *_Nullable response,
                                         NSError *_Nullable error))completion;

+ (void)finishLoginWithBaseURL:(NSURL *)baseURL
                    callbackURL:(NSURL *)callbackURL
                           state:(nullable NSString *)state
                     codeVerifier:(nullable NSString *)codeVerifier
                        completion:(void (^)(IMOAuthLoginResponse *_Nullable response,
                                             NSError *_Nullable error))completion;

+ (void)linkWithCallbackURL:(NSURL *)callbackURL
                       state:(nullable NSString *)state
                 codeVerifier:(nullable NSString *)codeVerifier
                    completion:(void (^)(IMUser *_Nullable user,
                                         NSError *_Nullable error))completion;

+ (void)unlinkWithCompletion:(void (^)(IMUser *_Nullable user,
                                       NSError *_Nullable error))completion;

+ (void)backchannelLogoutWithToken:(NSString *)logoutToken
                        completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (nullable NSURL *)mobileRedirectURLWithBaseURL:(NSURL *)baseURL
                                      queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems;

@end

NS_ASSUME_NONNULL_END
