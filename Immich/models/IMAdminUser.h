#import <Foundation/Foundation.h>
#import "IMUserLicense.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAdminUser : NSObject
@property (nonatomic, copy, readonly) NSString *userId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *email;
@property (nonatomic, copy, readonly) NSString *status;
@property (nonatomic, copy, readonly) NSString *avatarColor;
@property (nonatomic, copy, readonly, nullable) NSString *storageLabel;
@property (nonatomic, copy, readonly) NSString *createdAt;
@property (nonatomic, copy, readonly) NSString *profileChangedAt;
@property (nonatomic, copy, readonly) NSString *profileImagePath;
@property (nonatomic, copy, readonly) NSString *oauthId;
@property (nonatomic, copy, readonly) NSString *updatedAt;
@property (nonatomic, strong, readonly, nullable) IMUserLicense *license;
@property (nonatomic, readonly) BOOL isAdmin;
@property (nonatomic, readonly) BOOL shouldChangePassword;
@property (nonatomic, readonly) long long quotaUsageInBytes;
@property (nonatomic, readonly) long long quotaSizeInBytes;
@property (nonatomic, copy, readonly, nullable) NSString *deletedAt;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (nullable instancetype)userWithResponseDictionary:(NSDictionary *)dictionary;
+ (nullable instancetype)userWithCompatibleResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMAdminUser *> *)usersWithArray:(NSArray *)array;
@end

NS_ASSUME_NONNULL_END
