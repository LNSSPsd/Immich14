#import <Foundation/Foundation.h>
#import "IMPartner.h"

NS_ASSUME_NONNULL_BEGIN
@interface IMPartnerApi : NSObject
+ (void)partnersWithDirection:(NSString *)direction completion:(void (^)(NSArray<IMPartner *> *_Nullable partners, NSError *_Nullable error))completion;
+ (void)usersWithCompletion:(void (^)(NSArray<IMPartner *> *_Nullable users, NSError *_Nullable error))completion;
+ (void)createPartnerWithUserId:(NSString *)userId completion:(void (^)(IMPartner *_Nullable partner, NSError *_Nullable error))completion;
+ (void)updatePartnerId:(NSString *)partnerId inTimeline:(BOOL)inTimeline completion:(void (^)(IMPartner *_Nullable partner, NSError *_Nullable error))completion;
+ (void)removePartnerId:(NSString *)partnerId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
