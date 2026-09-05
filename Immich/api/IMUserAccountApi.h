#import <Foundation/Foundation.h>
#import "IMCalendarHeatmap.h"
#import "IMUserLicense.h"
#import "IMOnboardingStatus.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMUserAccountApi : NSObject

+ (void)calendarHeatmapFromDate:(nullable NSString *)fromDate
                         toDate:(nullable NSString *)toDate
                           type:(nullable NSString *)type
                     completion:(void (^)(IMCalendarHeatmap *_Nullable heatmap,
                                           NSError *_Nullable error))completion;

+ (void)userLicenseWithCompletion:(void (^)(IMUserLicense *_Nullable license,
                                             NSError *_Nullable error))completion;
+ (void)setUserLicenseWithActivationKey:(NSString *)activationKey
                              licenseKey:(NSString *)licenseKey
                             completion:(void (^)(IMUserLicense *_Nullable license,
                                                   NSError *_Nullable error))completion;
+ (void)deleteUserLicenseWithCompletion:(void (^)(BOOL success,
                                                   NSError *_Nullable error))completion;

+ (void)userOnboardingWithCompletion:(void (^)(IMOnboardingStatus *_Nullable status,
                                                NSError *_Nullable error))completion;
+ (void)setUserOnboarding:(BOOL)onboarded
               completion:(void (^)(IMOnboardingStatus *_Nullable status,
                                     NSError *_Nullable error))completion;
+ (void)deleteUserOnboardingWithCompletion:(void (^)(BOOL success,
                                                      NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
