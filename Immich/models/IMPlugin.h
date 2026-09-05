#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPluginMethod : NSObject

@property (nonatomic, copy, readonly) NSString *methodDescription;
@property (nonatomic, readonly, getter=hasHostFunctions) BOOL hostFunctions;
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSDictionary *schema;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSArray<NSString *> *types;
@property (nonatomic, copy, readonly) NSArray<NSString *> *uiHints;

+ (nullable instancetype)methodWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMPluginMethod *> *)methodsWithResponseArray:(NSArray *)array;

@end

@interface IMPlugin : NSObject

@property (nonatomic, copy, readonly) NSString *pluginId;
@property (nonatomic, copy, readonly) NSString *author;
@property (nonatomic, copy, readonly) NSString *createdAt;
@property (nonatomic, copy, readonly) NSString *pluginDescription;
@property (nonatomic, copy, readonly) NSArray<IMPluginMethod *> *methods;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *updatedAt;
@property (nonatomic, copy, readonly) NSString *version;

+ (nullable instancetype)pluginWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMPlugin *> *)pluginsWithResponseArray:(NSArray *)array;

@end

@interface IMPluginTemplateStep : NSObject

@property (nonatomic, copy, readonly) NSString *method;
@property (nonatomic, copy, readonly, nullable) NSDictionary *config;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

+ (nullable instancetype)stepWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMPluginTemplateStep *> *)stepsWithResponseArray:(NSArray *)array;

@end

@interface IMPluginTemplate : NSObject

@property (nonatomic, copy, readonly) NSString *templateDescription;
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, readonly) NSArray<IMPluginTemplateStep *> *steps;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *trigger;
@property (nonatomic, copy, readonly) NSArray<NSString *> *uiHints;

+ (nullable instancetype)templateWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMPluginTemplate *> *)templatesWithResponseArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
