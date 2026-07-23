#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAuthApi : NSObject

+ (void)loginWithBaseURL:(NSURL *)baseURL
                    email:(NSString *)email
                 password:(NSString *)password
               completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)validateTokenWithCompletion:(void (^)(BOOL valid))completion;

+ (void)logoutWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
