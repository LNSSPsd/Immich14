#import <Foundation/Foundation.h>
#import "IMUserPreferences.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const IMUserPreferencesDidChangeNotification;

@interface IMUserPreferencesApi : NSObject

+ (void)preferencesWithCompletion:(void (^)(IMUserPreferences *_Nullable preferences,
                                             NSError *_Nullable error))completion;
+ (nullable IMUserPreferences *)cachedPreferences;

+ (void)updateSection:(NSString *)section
                values:(NSDictionary<NSString *, id> *)values
            completion:(void (^)(IMUserPreferences *_Nullable preferences,
                                  NSError *_Nullable error))completion;

+ (void)clearCachedPreferences;

@end

NS_ASSUME_NONNULL_END
