#import <Foundation/Foundation.h>
#import "IMSystemMetadata.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSystemMetadataApi : NSObject

+ (void)adminOnboardingWithCompletion:(void (^)(IMAdminOnboardingStatus *_Nullable status,
                                                  NSError *_Nullable error))completion;
+ (void)setAdminOnboarded:(BOOL)onboarded
                completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)reverseGeocodingStateWithCompletion:(void (^)(IMReverseGeocodingState *_Nullable state,
                                                       NSError *_Nullable error))completion;
+ (void)versionCheckStateWithCompletion:(void (^)(IMVersionCheckState *_Nullable state,
                                                   NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
