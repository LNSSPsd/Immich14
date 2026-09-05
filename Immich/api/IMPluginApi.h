#import <Foundation/Foundation.h>
#import "IMPlugin.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMPluginApi : NSObject

+ (void)pluginsWithDescription:(nullable NSString *)pluginDescription
                        enabled:(nullable NSNumber *)enabled
                             id:(nullable NSString *)pluginId
                           name:(nullable NSString *)name
                          title:(nullable NSString *)title
                        version:(nullable NSString *)version
                     completion:(void (^)(NSArray<IMPlugin *> *_Nullable plugins,
                                          NSError *_Nullable error))completion;
+ (void)pluginsWithCompletion:(void (^)(NSArray<IMPlugin *> *_Nullable plugins,
                                        NSError *_Nullable error))completion;

+ (void)pluginWithId:(NSString *)pluginId
          completion:(void (^)(IMPlugin *_Nullable plugin,
                               NSError *_Nullable error))completion;

+ (void)pluginMethodsWithDescription:(nullable NSString *)methodDescription
                             enabled:(nullable NSNumber *)enabled
                                  id:(nullable NSString *)methodId
                                name:(nullable NSString *)name
                          pluginName:(nullable NSString *)pluginName
                       pluginVersion:(nullable NSString *)pluginVersion
                               title:(nullable NSString *)title
                             trigger:(nullable NSString *)trigger
                                type:(nullable NSString *)type
                          completion:(void (^)(NSArray<IMPluginMethod *> *_Nullable methods,
                                               NSError *_Nullable error))completion;
+ (void)pluginMethodsWithCompletion:(void (^)(NSArray<IMPluginMethod *> *_Nullable methods,
                                              NSError *_Nullable error))completion;

+ (void)pluginTemplatesWithCompletion:(void (^)(NSArray<IMPluginTemplate *> *_Nullable templates,
                                                NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
