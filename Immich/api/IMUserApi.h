#import <Foundation/Foundation.h>
#import "IMUser.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMUserApi : NSObject

+ (void)currentUserWithCompletion:(void (^)(IMUser *_Nullable user, NSError *_Nullable error))completion;
+ (void)userWithId:(NSString *)userId
        completion:(void (^)(IMUser *_Nullable user, NSError *_Nullable error))completion;
+ (nullable IMUser *)cachedUser;
+ (void)updateCurrentUserWithFields:(NSDictionary<NSString *, id> *)fields
                         completion:(void (^)(IMUser *_Nullable user, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)profileImageDataForUserId:(NSString *)userId
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)uploadProfileImageData:(NSData *)data
                                             filename:(NSString *)filename
                                           completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)deleteProfileImageWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;

+ (void)clearCachedUser;

@end

NS_ASSUME_NONNULL_END
