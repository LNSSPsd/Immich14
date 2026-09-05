#import <Foundation/Foundation.h>
#import "IMMaintenanceAuth.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMMaintenanceApi : NSObject

+ (nullable NSURLSessionTask *)loginWithToken:(nullable NSString *)token
                                    completion:(void (^)(IMMaintenanceAuth *_Nullable auth,
                                                         NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)loginWithRequest:(IMMaintenanceLoginRequest *)request
                                      completion:(void (^)(IMMaintenanceAuth *_Nullable auth,
                                                           NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
