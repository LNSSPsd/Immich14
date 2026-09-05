#import "IMSystemConfigApi.h"
#import "IMApiClient.h"
#import "common.h"

static IMSystemConfig *sCachedSystemConfig;

static NSError *IMSystemConfigMalformedError(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid system configuration.")}];
}

static NSError *IMSystemConfigValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The system configuration request is invalid.")}];
}

static void IMSystemConfigCompleteOnMain(void (^completion)(IMSystemConfig *_Nullable, NSError *_Nullable),
	                                      IMSystemConfig * _Nullable config,
	                                      NSError * _Nullable error) {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(config, error);
	});
}

static IMSystemConfig *IMSystemConfigParse(id json, NSError **outError) {
	IMSystemConfig *config = [IMSystemConfig configWithDictionary:json];
	if (!config && outError) *outError = IMSystemConfigMalformedError();
	return config;
}

@implementation IMSystemConfigApi

+ (void)configWithCompletion:(void (^)(IMSystemConfig *, NSError *))completion {
	[[IMApiClient shared] GET:@"/system-config" query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		NSError *parseError = nil;
		IMSystemConfig *config = IMSystemConfigParse(json, &parseError);
		if (!config) {
			completion(nil, parseError ?: IMSystemConfigMalformedError());
			return;
		}
		sCachedSystemConfig = config;
		completion(config, nil);
	}];
}

+ (void)defaultsWithCompletion:(void (^)(IMSystemConfig *, NSError *))completion {
	[[IMApiClient shared] GET:@"/system-config/defaults" query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		NSError *parseError = nil;
		IMSystemConfig *config = IMSystemConfigParse(json, &parseError);
		completion(config, config ? nil : (parseError ?: IMSystemConfigMalformedError()));
	}];
}

+ (void)storageTemplateOptionsWithCompletion:(void (^)(IMSystemConfigStorageTemplateOptions *, NSError *))completion {
	[[IMApiClient shared] GET:@"/system-config/storage-template-options" query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMSystemConfigStorageTemplateOptions *options = [IMSystemConfigStorageTemplateOptions optionsWithDictionary:json];
		completion(options, options ? nil : IMSystemConfigMalformedError());
	}];
}

+ (void)updateConfig:(IMSystemConfig *)config
	          completion:(void (^)(IMSystemConfig *, NSError *))completion {
	if (![config isKindOfClass:[IMSystemConfig class]]) {
		IMSystemConfigCompleteOnMain(completion, nil, IMSystemConfigValidationError(_(@"A complete system configuration is required.")));
		return;
	}
	NSDictionary *body = [config dictionaryRepresentation];
	IMSystemConfig *validated = [IMSystemConfig configWithDictionary:body];
	if (!validated) {
		IMSystemConfigCompleteOnMain(completion, nil, IMSystemConfigValidationError(_(@"The system configuration is incomplete or contains invalid JSON.")));
		return;
	}
	[[IMApiClient shared] PUT:@"/system-config" body:body completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		NSError *parseError = nil;
		IMSystemConfig *result = IMSystemConfigParse(json, &parseError);
		if (!result) {
			completion(nil, parseError ?: IMSystemConfigMalformedError());
			return;
		}
		sCachedSystemConfig = result;
		completion(result, nil);
	}];
}

+ (void)updateSection:(NSString *)section
               values:(NSDictionary<NSString *, id> *)values
           completion:(void (^)(IMSystemConfig *, NSError *))completion {
	if (![section isKindOfClass:[NSString class]] || section.length == 0 ||
	    ![[IMSystemConfig requiredSectionNames] containsObject:section]) {
		IMSystemConfigCompleteOnMain(completion, nil, IMSystemConfigValidationError(_(@"Choose a valid system configuration section.")));
		return;
	}
	if (![values isKindOfClass:[NSDictionary class]] || values.count == 0 ||
	    ![NSJSONSerialization isValidJSONObject:values]) {
		IMSystemConfigCompleteOnMain(completion, nil, IMSystemConfigValidationError(_(@"The system configuration value is invalid.")));
		return;
	}
	IMSystemConfig *current = sCachedSystemConfig;
	if (!current) {
		IMSystemConfigCompleteOnMain(completion, nil, IMSystemConfigValidationError(_(@"Load the current system configuration before editing it.")));
		return;
	}
	id rawSection = current.rawDictionary[section];
	if (![rawSection isKindOfClass:[NSDictionary class]]) {
		IMSystemConfigCompleteOnMain(completion, nil, IMSystemConfigMalformedError());
		return;
	}
	NSMutableDictionary *body = [current.rawDictionary mutableCopy];
	NSMutableDictionary *sectionBody = [rawSection mutableCopy];
	[sectionBody addEntriesFromDictionary:values];
	body[section] = sectionBody;
	IMSystemConfig *candidate = [IMSystemConfig configWithDictionary:body];
	if (!candidate) {
		IMSystemConfigCompleteOnMain(completion, nil, IMSystemConfigValidationError(_(@"The edited system configuration is invalid.")));
		return;
	}
	[self updateConfig:candidate completion:completion];
}

+ (void)updateSection:(NSString *)section
                  key:(NSString *)key
                value:(id)value
            completion:(void (^)(IMSystemConfig *, NSError *))completion {
	if (![key isKindOfClass:[NSString class]] || key.length == 0 || value == nil) {
		IMSystemConfigCompleteOnMain(completion, nil, IMSystemConfigValidationError(_(@"The system configuration value is invalid.")));
		return;
	}
	[self updateSection:section values:@{key: value} completion:completion];
}

+ (IMSystemConfig *)cachedConfig {
	return sCachedSystemConfig;
}

+ (void)clearCachedConfig {
	sCachedSystemConfig = nil;
}

@end
