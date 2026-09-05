#import <Foundation/Foundation.h>
#import "IMAlbumMember.h"

NS_ASSUME_NONNULL_BEGIN
@interface IMAlbumSharingApi : NSObject
+ (void)membersForAlbumId:(NSString *)albumId completion:(void (^)(NSArray<IMAlbumMember *> *_Nullable members, NSError *_Nullable error))completion;
+ (void)availableUsersWithCompletion:(void (^)(NSArray<IMAlbumMember *> *_Nullable users, NSError *_Nullable error))completion;
+ (void)addUserId:(NSString *)userId role:(NSString *)role albumId:(NSString *)albumId completion:(void (^)(NSError *_Nullable error))completion;
+ (void)updateUserId:(NSString *)userId role:(NSString *)role albumId:(NSString *)albumId completion:(void (^)(NSError *_Nullable error))completion;
+ (void)removeUserId:(NSString *)userId albumId:(NSString *)albumId completion:(void (^)(NSError *_Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
