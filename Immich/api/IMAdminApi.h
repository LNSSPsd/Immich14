#import <Foundation/Foundation.h>
#import "IMAdminUser.h"
#import "IMAdminUserStatistics.h"
#import "IMAdminUserPreferences.h"
#import "IMCalendarHeatmap.h"
#import "IMSessionInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAdminApi : NSObject
+ (void)usersIncludingDeleted:(BOOL)includingDeleted completion:(void (^)(NSArray<IMAdminUser *> *_Nullable users, NSError *_Nullable error))completion;
+ (void)createUserWithEmail:(NSString *)email name:(NSString *)name password:(NSString *)password isAdmin:(BOOL)isAdmin completion:(void (^)(IMAdminUser *_Nullable user, NSError *_Nullable error))completion;
+ (void)userWithId:(NSString *)userId completion:(void (^)(IMAdminUser *_Nullable user, NSError *_Nullable error))completion;
+ (void)updateUserId:(NSString *)userId isAdmin:(BOOL)isAdmin completion:(void (^)(IMAdminUser *_Nullable user, NSError *_Nullable error))completion;
+ (void)updateUserId:(NSString *)userId
              fields:(NSDictionary<NSString *, id> *)fields
          completion:(void (^)(IMAdminUser *_Nullable user, NSError *_Nullable error))completion;
+ (void)deleteUserId:(NSString *)userId force:(BOOL)force completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)restoreUserId:(NSString *)userId completion:(void (^)(IMAdminUser *_Nullable user, NSError *_Nullable error))completion;

+ (void)statisticsForUserId:(NSString *)userId
                 isFavorite:(nullable NSNumber *)isFavorite
                  isTrashed:(nullable NSNumber *)isTrashed
                  visibility:(nullable NSString *)visibility
                 completion:(void (^)(IMAdminUserStatistics *_Nullable statistics,
                                       NSError *_Nullable error))completion;

+ (void)sessionsForUserId:(NSString *)userId
                completion:(void (^)(NSArray<IMSessionInfo *> *_Nullable sessions,
                                      NSError *_Nullable error))completion;

+ (void)preferencesForUserId:(NSString *)userId
                   completion:(void (^)(IMAdminUserPreferences *_Nullable preferences,
                                         NSError *_Nullable error))completion;

+ (void)updatePreferencesForUserId:(NSString *)userId
                             values:(NSDictionary<NSString *, id> *)values
                         completion:(void (^)(IMAdminUserPreferences *_Nullable preferences,
                                               NSError *_Nullable error))completion;

+ (void)calendarHeatmapForUserId:(NSString *)userId
                        fromDate:(nullable NSString *)fromDate
                          toDate:(nullable NSString *)toDate
                            type:(nullable NSString *)type
                      completion:(void (^)(IMCalendarHeatmap *_Nullable heatmap,
                                            NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
