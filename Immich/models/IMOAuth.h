#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** The URL returned by POST /oauth/authorize. */
@interface IMOAuthAuthorizeResponse : NSObject

@property (nonatomic, copy, readonly) NSString *url;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

/** The session payload returned by POST /oauth/callback. */
@interface IMOAuthLoginResponse : NSObject

@property (nonatomic, copy, readonly) NSString *accessToken;
@property (nonatomic, readonly) BOOL isAdmin;
@property (nonatomic, readonly) BOOL isOnboarded;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *profileImagePath;
@property (nonatomic, readonly) BOOL shouldChangePassword;
@property (nonatomic, copy, readonly) NSString *userEmail;
@property (nonatomic, copy, readonly) NSString *userId;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
