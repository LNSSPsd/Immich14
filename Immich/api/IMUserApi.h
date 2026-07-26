#import <Foundation/Foundation.h>
#import "IMUser.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMUserApi : NSObject

+ (void)currentUserWithCompletion:(void (^)(IMUser *_Nullable user, NSError *_Nullable error))completion;
+ (nullable IMUser *)cachedUser;

+ (void)clearCachedUser;

@end

NS_ASSUME_NONNULL_END
