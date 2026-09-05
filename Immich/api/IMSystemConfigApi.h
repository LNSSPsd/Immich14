#import <Foundation/Foundation.h>
#import "IMSystemConfig.h"
#import "IMSystemConfigStorageTemplateOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSystemConfigApi : NSObject

+ (void)configWithCompletion:(void (^)(IMSystemConfig *_Nullable config,
                                        NSError *_Nullable error))completion;
+ (void)defaultsWithCompletion:(void (^)(IMSystemConfig *_Nullable config,
                                          NSError *_Nullable error))completion;
+ (void)storageTemplateOptionsWithCompletion:(void (^)(IMSystemConfigStorageTemplateOptions *_Nullable options,
                                                        NSError *_Nullable error))completion;

+ (void)updateConfig:(IMSystemConfig *)config
          completion:(void (^)(IMSystemConfig *_Nullable config,
                                NSError *_Nullable error))completion;

+ (void)updateSection:(NSString *)section
               values:(NSDictionary<NSString *, id> *)values
           completion:(void (^)(IMSystemConfig *_Nullable config,
                                 NSError *_Nullable error))completion;

+ (void)updateSection:(NSString *)section
                  key:(NSString *)key
                value:(id)value
            completion:(void (^)(IMSystemConfig *_Nullable config,
                                  NSError *_Nullable error))completion;

+ (nullable IMSystemConfig *)cachedConfig;
+ (void)clearCachedConfig;

@end

NS_ASSUME_NONNULL_END
