#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSession : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isLoggedIn) BOOL loggedIn;
@property (nonatomic, copy, readonly, nullable) NSURL *baseURL;      
@property (nonatomic, copy, readonly, nullable) NSString *accessToken;
@property (nonatomic, copy, readonly, nullable) NSString *userId;

- (void)startWithBaseURL:(NSURL *)baseURL
             accessToken:(NSString *)token
                  userId:(NSString *)userId;

- (void)logout;

- (nullable NSString *)authorizationHeader;

@end

NS_ASSUME_NONNULL_END
