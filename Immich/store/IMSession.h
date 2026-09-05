#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMSessionAuthKind) {
	IMSessionAuthKindBearer = 0,
	IMSessionAuthKindAPIKey = 1,
};

@interface IMSession : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isLoggedIn) BOOL loggedIn;
@property (nonatomic, copy, readonly, nullable) NSURL *baseURL;      
@property (nonatomic, copy, readonly, nullable) NSString *accessToken; 
@property (nonatomic, copy, readonly, nullable) NSString *userId;
@property (nonatomic, readonly) IMSessionAuthKind authKind; 

- (void)reloadFromPersistence;

- (void)startWithBaseURL:(NSURL *)baseURL
             accessToken:(NSString *)token
                  userId:(NSString *)userId;

- (void)startWithBaseURL:(NSURL *)baseURL
                  apiKey:(NSString *)apiKey
                  userId:(nullable NSString *)userId;

- (void)logout;

- (nullable NSString *)authorizationHeader;

- (nullable NSString *)apiKeyHeaderValue;

@end

NS_ASSUME_NONNULL_END
