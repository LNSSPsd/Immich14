#import "IMPlugin.h"
#include <string.h>

static id IMPluginNullable(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMPluginString(id value, BOOL allowEmpty) {
	value = IMPluginNullable(value);
	return [value isKindOfClass:[NSString class]] && (allowEmpty || [(NSString *)value length] > 0);
}

static BOOL IMPluginBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMPluginStringArray(id value, BOOL allowEmptyValues) {
	if (![value isKindOfClass:[NSArray class]]) return NO;
	for (id item in (NSArray *)value) {
		if (!IMPluginString(item, allowEmptyValues)) return NO;
	}
	return YES;
}

static BOOL IMPluginJSONDictionary(id value) {
	return [value isKindOfClass:[NSDictionary class]] && [NSJSONSerialization isValidJSONObject:value];
}

static BOOL IMPluginUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = [(NSString *)value lowercaseString];
	return [raw isEqualToString:canonical] && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMPluginTrigger(id value) {
	return [value isKindOfClass:[NSString class]] &&
	       ([(NSString *)value isEqualToString:@"AssetCreate"] ||
	        [(NSString *)value isEqualToString:@"AssetMetadataExtraction"]);
}

@interface IMPluginMethod ()
@property (nonatomic, copy) NSString *methodDescription;
@property (nonatomic, getter=hasHostFunctions) BOOL hostFunctions;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSDictionary *schema;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<NSString *> *types;
@property (nonatomic, copy) NSArray<NSString *> *uiHints;
@end

@interface IMPlugin ()
@property (nonatomic, copy) NSString *pluginId;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *pluginDescription;
@property (nonatomic, copy) NSArray<IMPluginMethod *> *methods;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *updatedAt;
@property (nonatomic, copy) NSString *version;
@end

@interface IMPluginTemplateStep ()
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy, nullable) NSDictionary *config;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@end

@interface IMPluginTemplate ()
@property (nonatomic, copy) NSString *templateDescription;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSArray<IMPluginTemplateStep *> *steps;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *trigger;
@property (nonatomic, copy) NSArray<NSString *> *uiHints;
@end

@implementation IMPluginMethod

+ (nullable instancetype)methodWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id description = IMPluginNullable(dictionary[@"description"]);
	id hostFunctions = IMPluginNullable(dictionary[@"hostFunctions"]);
	id key = IMPluginNullable(dictionary[@"key"]);
	id name = IMPluginNullable(dictionary[@"name"]);
	id title = IMPluginNullable(dictionary[@"title"]);
	id types = IMPluginNullable(dictionary[@"types"]);
	id uiHints = IMPluginNullable(dictionary[@"uiHints"]);
	if (!IMPluginString(description, YES) || !IMPluginBoolean(hostFunctions) ||
	    !IMPluginString(key, NO) || !IMPluginString(name, NO) || !IMPluginString(title, YES) ||
	    !IMPluginStringArray(types, NO) || !IMPluginStringArray(uiHints, YES)) return nil;
	id schema = IMPluginNullable(dictionary[@"schema"]);
	if (schema != nil && !IMPluginJSONDictionary(schema)) return nil;
	IMPluginMethod *result = [[self alloc] init];
	result.methodDescription = [description copy];
	result.hostFunctions = [hostFunctions boolValue];
	result.key = [key copy];
	result.name = [name copy];
	result.schema = [schema copy];
	result.title = [title copy];
	result.types = [types copy];
	result.uiHints = [uiHints copy];
	return result;
}

+ (NSArray<IMPluginMethod *> *)methodsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMPluginMethod *method = [value isKindOfClass:[NSDictionary class]] ? [self methodWithResponseDictionary:value] : nil;
		if (method) [result addObject:method];
	}
	return [result copy];
}

@end

@implementation IMPlugin

+ (nullable instancetype)pluginWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id identifier = IMPluginNullable(dictionary[@"id"]);
	id author = IMPluginNullable(dictionary[@"author"]);
	id createdAt = IMPluginNullable(dictionary[@"createdAt"]);
	id description = IMPluginNullable(dictionary[@"description"]);
	id methods = IMPluginNullable(dictionary[@"methods"]);
	id name = IMPluginNullable(dictionary[@"name"]);
	id title = IMPluginNullable(dictionary[@"title"]);
	id updatedAt = IMPluginNullable(dictionary[@"updatedAt"]);
	id version = IMPluginNullable(dictionary[@"version"]);
	if (!IMPluginUUIDv4(identifier) || !IMPluginString(author, YES) || !IMPluginString(createdAt, NO) ||
	    !IMPluginString(description, YES) || ![methods isKindOfClass:[NSArray class]] ||
	    !IMPluginString(name, NO) || !IMPluginString(title, YES) || !IMPluginString(updatedAt, NO) ||
	    !IMPluginString(version, NO)) return nil;
	NSMutableArray<IMPluginMethod *> *parsed = [NSMutableArray arrayWithCapacity:[(NSArray *)methods count]];
	for (id value in (NSArray *)methods) {
		if (![value isKindOfClass:[NSDictionary class]]) return nil;
		IMPluginMethod *method = [IMPluginMethod methodWithResponseDictionary:value];
		if (!method) return nil;
		[parsed addObject:method];
	}
	IMPlugin *result = [[self alloc] init];
	result.pluginId = [identifier copy];
	result.author = [author copy];
	result.createdAt = [createdAt copy];
	result.pluginDescription = [description copy];
	result.methods = [parsed copy];
	result.name = [name copy];
	result.title = [title copy];
	result.updatedAt = [updatedAt copy];
	result.version = [version copy];
	return result;
}

+ (NSArray<IMPlugin *> *)pluginsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMPlugin *plugin = [value isKindOfClass:[NSDictionary class]] ? [self pluginWithResponseDictionary:value] : nil;
		if (plugin) [result addObject:plugin];
	}
	return [result copy];
}

@end

@implementation IMPluginTemplateStep

+ (nullable instancetype)stepWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id method = IMPluginNullable(dictionary[@"method"]);
	id config = IMPluginNullable(dictionary[@"config"]);
	id enabled = IMPluginNullable(dictionary[@"enabled"]);
	if (!IMPluginString(method, NO) || (config != nil && !IMPluginJSONDictionary(config)) ||
	    (enabled != nil && !IMPluginBoolean(enabled))) return nil;
	IMPluginTemplateStep *result = [[self alloc] init];
	result.method = [method copy];
	result.config = [config copy];
	result.enabled = enabled == nil ? YES : [enabled boolValue];
	return result;
}

+ (NSArray<IMPluginTemplateStep *> *)stepsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMPluginTemplateStep *step = [value isKindOfClass:[NSDictionary class]] ? [self stepWithResponseDictionary:value] : nil;
		if (step) [result addObject:step];
	}
	return [result copy];
}

@end

@implementation IMPluginTemplate

+ (nullable instancetype)templateWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id description = IMPluginNullable(dictionary[@"description"]);
	id key = IMPluginNullable(dictionary[@"key"]);
	id steps = IMPluginNullable(dictionary[@"steps"]);
	id title = IMPluginNullable(dictionary[@"title"]);
	id trigger = IMPluginNullable(dictionary[@"trigger"]);
	id uiHints = IMPluginNullable(dictionary[@"uiHints"]);
	if (!IMPluginString(description, YES) || !IMPluginString(key, NO) || ![steps isKindOfClass:[NSArray class]] ||
	    !IMPluginString(title, YES) || !IMPluginTrigger(trigger) || !IMPluginStringArray(uiHints, YES)) return nil;
	NSMutableArray<IMPluginTemplateStep *> *parsed = [NSMutableArray arrayWithCapacity:[(NSArray *)steps count]];
	for (id value in (NSArray *)steps) {
		if (![value isKindOfClass:[NSDictionary class]]) return nil;
		IMPluginTemplateStep *step = [IMPluginTemplateStep stepWithResponseDictionary:value];
		if (!step) return nil;
		[parsed addObject:step];
	}
	IMPluginTemplate *result = [[self alloc] init];
	result.templateDescription = [description copy];
	result.key = [key copy];
	result.steps = [parsed copy];
	result.title = [title copy];
	result.trigger = [trigger copy];
	result.uiHints = [uiHints copy];
	return result;
}

+ (NSArray<IMPluginTemplate *> *)templatesWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMPluginTemplate *template = [value isKindOfClass:[NSDictionary class]] ? [self templateWithResponseDictionary:value] : nil;
		if (template) [result addObject:template];
	}
	return [result copy];
}

@end
