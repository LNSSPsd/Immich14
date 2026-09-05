#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAdminOnboardingStatus : NSObject
@property (nonatomic, readonly, getter=isOnboarded) BOOL onboarded;
+ (nullable instancetype)statusWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMReverseGeocodingState : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *lastImportFileName;
@property (nonatomic, copy, readonly, nullable) NSString *lastUpdate;
+ (nullable instancetype)stateWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMVersionCheckState : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *checkedAt;
@property (nonatomic, copy, readonly, nullable) NSString *releaseVersion;
+ (nullable instancetype)stateWithDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
