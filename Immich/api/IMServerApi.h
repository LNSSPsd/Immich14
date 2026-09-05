#import <Foundation/Foundation.h>
#import "IMServerStorage.h"
#import "IMServerStats.h"
#import "IMServerInfo.h"
#import "IMServerApkLinks.h"
#import "IMUserLicense.h"
#import "IMMaintenanceAuth.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMServerApi : NSObject

+ (void)serverVersionWithCompletion:(void (^)(NSString *_Nullable versionString, NSError *_Nullable error))completion;
+ (nullable NSString *)cachedServerVersion;

+ (void)serverStorageWithCompletion:(void (^)(IMServerStorage *_Nullable storage, NSError *_Nullable error))completion;
+ (nullable IMServerStorage *)cachedServerStorage;

+ (void)serverAboutWithCompletion:(void (^)(IMServerAbout *_Nullable about, NSError *_Nullable error))completion;
+ (void)serverFeaturesWithCompletion:(void (^)(IMServerFeatures *_Nullable features, NSError *_Nullable error))completion;
+ (void)serverConfigWithCompletion:(void (^)(IMServerConfig *_Nullable config, NSError *_Nullable error))completion;
+ (void)supportedMediaTypesWithCompletion:(void (^)(IMServerMediaTypes *_Nullable mediaTypes, NSError *_Nullable error))completion;
+ (void)serverVersionCheckWithCompletion:(void (^)(IMServerVersionCheck *_Nullable state, NSError *_Nullable error))completion;
+ (void)serverVersionHistoryWithCompletion:(void (^)(NSArray<IMServerVersionHistoryEntry *> *_Nullable history, NSError *_Nullable error))completion;
+ (void)pingWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)serverApkLinksWithCompletion:(void (^)(IMServerApkLinks *_Nullable links,
                                                 NSError *_Nullable error))completion;

+ (void)serverLicenseWithCompletion:(void (^)(IMUserLicense *_Nullable license,
                                                NSError *_Nullable error))completion;
+ (void)setServerLicenseWithActivationKey:(NSString *)activationKey
                                licenseKey:(NSString *)licenseKey
                                completion:(void (^)(IMUserLicense *_Nullable license,
                                                      NSError *_Nullable error))completion;
+ (void)deleteServerLicenseWithCompletion:(void (^)(BOOL success,
                                                       NSError *_Nullable error))completion;

+ (void)serverStatisticsWithCompletion:(void (^)(IMServerStats *_Nullable stats,
                                                  NSError *_Nullable error))completion;
+ (void)maintenanceStatusWithCompletion:(void (^)(NSDictionary *_Nullable status,
                                                    NSError *_Nullable error))completion;
+ (void)setMaintenanceAction:(NSString *)action
       restoreBackupFilename:(nullable NSString *)filename
                   completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)maintenanceLoginWithToken:(nullable NSString *)token
                        completion:(void (^)(IMMaintenanceAuth *_Nullable auth,
                                              NSError *_Nullable error))completion;

+ (void)clearCached;

@end

NS_ASSUME_NONNULL_END
