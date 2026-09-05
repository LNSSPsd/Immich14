#import "IMPluginApi.h"
#import "IMApiClient.h"
#import "common.h"
#include <string.h>

static NSError *IMPluginAPIError(NSString *message, NSInteger code) {
	return [NSError errorWithDomain:IMApiErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSError *IMPluginMalformedResponse(void) {
	return IMPluginAPIError(_(@"The server returned an invalid plugin response."), 2);
}

static BOOL IMPluginAPIUUIDv4(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = value.lowercaseString;
	return [raw isEqualToString:canonical] && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMPluginAPIStringFilter(NSString *value) {
	if (value == nil) return YES;
	if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
	for (NSUInteger i = 0; i < value.length; i++) if ([[NSCharacterSet controlCharacterSet] characterIsMember:[value characterAtIndex:i]]) return NO;
	return YES;
}

static BOOL IMPluginAPIBoolean(NSNumber *value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = value.objCType;
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static NSDictionary *IMPluginAPIQuery(NSString *description,
	                                    NSNumber *enabled,
	                                    NSString *identifier,
	                                    NSString *name,
	                                    NSString *title,
	                                    NSString *version) {
	NSMutableDictionary *query = [NSMutableDictionary dictionary];
	if (description) query[@"description"] = description;
	if (enabled) query[@"enabled"] = enabled.boolValue ? @"true" : @"false";
	if (identifier) query[@"id"] = identifier;
	if (name) query[@"name"] = name;
	if (title) query[@"title"] = title;
	if (version) query[@"version"] = version;
	return query.count ? [query copy] : nil;
}

static void IMPluginCompleteOnMain(void (^completion)(id _Nullable value, NSError *_Nullable error), id value, NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(value, error); });
}

@implementation IMPluginApi

+ (void)pluginsWithDescription:(NSString *)pluginDescription
                        enabled:(NSNumber *)enabled
                             id:(NSString *)pluginId
                           name:(NSString *)name
                          title:(NSString *)title
                        version:(NSString *)version
                     completion:(void (^)(NSArray<IMPlugin *> *, NSError *))completion {
	if (!IMPluginAPIStringFilter(pluginDescription) || !IMPluginAPIStringFilter(name) ||
	    !IMPluginAPIStringFilter(title) || !IMPluginAPIStringFilter(version) ||
	    (enabled != nil && !IMPluginAPIBoolean(enabled)) ||
	    (pluginId != nil && !IMPluginAPIUUIDv4(pluginId))) {
		IMPluginCompleteOnMain(completion, nil, IMPluginAPIError(_(@"Plugin filters are invalid."), 1));
		return;
	}
	NSDictionary *query = IMPluginAPIQuery(pluginDescription, enabled, pluginId, name, title, version);
	[[IMApiClient shared] GET:@"/plugins" query:query completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSArray class]]) { completion(nil, IMPluginMalformedResponse()); return; }
		NSMutableArray<IMPlugin *> *plugins = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (id value in (NSArray *)json) {
			IMPlugin *plugin = [value isKindOfClass:[NSDictionary class]] ? [IMPlugin pluginWithResponseDictionary:value] : nil;
			if (!plugin) { completion(nil, IMPluginMalformedResponse()); return; }
			[plugins addObject:plugin];
		}
		completion([plugins copy], nil);
	}];
}

+ (void)pluginsWithCompletion:(void (^)(NSArray<IMPlugin *> *, NSError *))completion {
	[self pluginsWithDescription:nil enabled:nil id:nil name:nil title:nil version:nil completion:completion];
}

+ (void)pluginWithId:(NSString *)pluginId completion:(void (^)(IMPlugin *, NSError *))completion {
	if (!IMPluginAPIUUIDv4(pluginId)) {
		IMPluginCompleteOnMain(completion, nil, IMPluginAPIError(_(@"A valid plugin identifier is required."), 1));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/plugins/%@", [pluginId stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMPlugin *plugin = [IMPlugin pluginWithResponseDictionary:json];
		completion(plugin, plugin ? nil : IMPluginMalformedResponse());
	}];
}

+ (void)pluginMethodsWithDescription:(NSString *)methodDescription
                             enabled:(NSNumber *)enabled
                                  id:(NSString *)methodId
                                name:(NSString *)name
                          pluginName:(NSString *)pluginName
                       pluginVersion:(NSString *)pluginVersion
                               title:(NSString *)title
                             trigger:(NSString *)trigger
                                type:(NSString *)type
                          completion:(void (^)(NSArray<IMPluginMethod *> *, NSError *))completion {
	if (!IMPluginAPIStringFilter(methodDescription) || !IMPluginAPIStringFilter(name) ||
	    !IMPluginAPIStringFilter(pluginName) || !IMPluginAPIStringFilter(pluginVersion) ||
	    !IMPluginAPIStringFilter(title) || !IMPluginAPIStringFilter(trigger) || !IMPluginAPIStringFilter(type) ||
	    (enabled != nil && !IMPluginAPIBoolean(enabled)) ||
	    (methodId != nil && !IMPluginAPIUUIDv4(methodId))) {
		IMPluginCompleteOnMain(completion, nil, IMPluginAPIError(_(@"Plugin method filters are invalid."), 1));
		return;
	}
	NSMutableDictionary *query = [IMPluginAPIQuery(methodDescription, enabled, methodId, name, title, nil) mutableCopy] ?: [NSMutableDictionary dictionary];
	if (pluginName) query[@"pluginName"] = pluginName;
	if (pluginVersion) query[@"pluginVersion"] = pluginVersion;
	if (trigger) query[@"trigger"] = trigger;
	if (type) query[@"type"] = type;
	[[IMApiClient shared] GET:@"/plugins/methods" query:query.count ? query : nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSArray class]]) { completion(nil, IMPluginMalformedResponse()); return; }
		NSMutableArray<IMPluginMethod *> *methods = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (id value in (NSArray *)json) {
			IMPluginMethod *method = [value isKindOfClass:[NSDictionary class]] ? [IMPluginMethod methodWithResponseDictionary:value] : nil;
			if (!method) { completion(nil, IMPluginMalformedResponse()); return; }
			[methods addObject:method];
		}
		completion([methods copy], nil);
	}];
}

+ (void)pluginMethodsWithCompletion:(void (^)(NSArray<IMPluginMethod *> *, NSError *))completion {
	[self pluginMethodsWithDescription:nil enabled:nil id:nil name:nil pluginName:nil pluginVersion:nil title:nil trigger:nil type:nil completion:completion];
}

+ (void)pluginTemplatesWithCompletion:(void (^)(NSArray<IMPluginTemplate *> *, NSError *))completion {
	[[IMApiClient shared] GET:@"/plugins/templates" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSArray class]]) { completion(nil, IMPluginMalformedResponse()); return; }
		NSMutableArray<IMPluginTemplate *> *templates = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (id value in (NSArray *)json) {
			IMPluginTemplate *template = [value isKindOfClass:[NSDictionary class]] ? [IMPluginTemplate templateWithResponseDictionary:value] : nil;
			if (!template) { completion(nil, IMPluginMalformedResponse()); return; }
			[templates addObject:template];
		}
		completion([templates copy], nil);
	}];
}

@end
