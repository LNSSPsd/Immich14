#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMUser : NSObject

@property (nonatomic, copy, readonly) NSString *userId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *email;
@property (nonatomic, copy, readonly, nullable) NSString *avatarColor;
@property (nonatomic, copy, readonly, nullable) NSString *profileImagePath;
@property (nonatomic, copy, readonly, nullable) NSString *profileChangedAt;
@property (nonatomic, copy, readonly, nullable) NSString *oauthId;
@property (nonatomic, readonly) BOOL isAdmin;
@property (nonatomic, readonly) long long quotaUsageInBytes;
@property (nonatomic, readonly) long long quotaSizeInBytes; 

- (instancetype)initWithDictionary:(NSDictionary *)dict;

+ (nullable instancetype)userWithResponseDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
