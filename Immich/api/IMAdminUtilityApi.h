#import <Foundation/Foundation.h>
#import "IMMaintenanceDetectInstall.h"
#import "IMTestEmailResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAdminUtilityApi : NSObject

+ (void)unlinkAllOAuthAccountsWithCompletion:(void (^)(BOOL success,
                                                        NSError *_Nullable error))completion;

+ (void)detectPriorInstallWithCompletion:(void (^)(IMMaintenanceDetectInstall *_Nullable result,
                                                   NSError *_Nullable error))completion;

+ (void)sendTestEmailWithSMTPConfiguration:(NSDictionary<NSString *, id> *)smtp
                                completion:(void (^)(IMTestEmailResponse *_Nullable response,
                                                     NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
