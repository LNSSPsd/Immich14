#import "IMServerApi.h"
#import "IMApiClient.h"
#import "IMMaintenanceApi.h"
#import "common.h"
#include <math.h>
#include <string.h>

static NSError *IMServerMalformedResponse(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The server returned an invalid server response.")}];
}

static NSError *IMServerLicenseInputError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"Enter a valid Immich license key and activation key.")}];
}

static void IMServerLicenseFailObject(void (^completion)(IMUserLicense *_Nullable, NSError *_Nullable), NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
}

static BOOL IMServerLicenseKeyIsValid(id value) {
	if (![value isKindOfClass:[NSString class]]) return NO;
	NSString *key = (NSString *)value;
	static NSRegularExpression *regex;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"^IM(SV|CL)(-[0-9A-Za-z]{4}){8}$" options:0 error:nil];
	});
	return [regex firstMatchInString:key options:0 range:NSMakeRange(0, key.length)] != nil;
}

static BOOL IMServerNumber(id value) {
	return [value isKindOfClass:[NSNumber class]];
}

static BOOL IMServerVersionInteger(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) return NO;
	double number = [(NSNumber *)value doubleValue];
	return isfinite(number) && floor(number) == number && number >= 0.0 && number <= 9007199254740991.0;
}

static BOOL IMServerStorageResponseIsValid(NSDictionary *dict) {
	if (![dict isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	for (NSString *key in @[ @"diskAvailable", @"diskSize", @"diskUse" ]) {
		if (![dict[key] isKindOfClass:[NSString class]]) {
			return NO;
		}
	}
	for (NSString *key in @[ @"diskAvailableRaw", @"diskSizeRaw", @"diskUseRaw", @"diskUsagePercentage" ]) {
		if (!IMServerNumber(dict[key])) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMServerStatsResponseIsValid(NSDictionary *dict) {
	if (![dict isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	for (NSString *key in @[ @"photos", @"videos", @"usage", @"usagePhotos", @"usageVideos" ]) {
		if (!IMServerNumber(dict[key])) {
			return NO;
		}
	}
	id rawUsers = dict[@"usageByUser"];
	if (![rawUsers isKindOfClass:[NSArray class]]) {
		return NO;
	}
	for (id raw in (NSArray *)rawUsers) {
		if (![raw isKindOfClass:[NSDictionary class]]) {
			return NO;
		}
		NSDictionary *user = (NSDictionary *)raw;
		for (NSString *key in @[ @"userId", @"userName" ]) {
			if (![user[key] isKindOfClass:[NSString class]]) {
				return NO;
			}
		}
		for (NSString *key in @[ @"photos", @"videos", @"usage", @"usagePhotos", @"usageVideos" ]) {
			if (!IMServerNumber(user[key])) {
				return NO;
			}
		}
		id quota = user[@"quotaSizeInBytes"];
		if (quota != [NSNull null] && !IMServerNumber(quota)) {
			return NO;
		}
	}
	return YES;
}

@implementation IMServerApi

static NSString *sCachedServerVersion;
static IMServerStorage *sCachedServerStorage;

+ (void)serverVersionWithCompletion:(void (^)(NSString *_Nullable versionString, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/server/version"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error ?: IMServerMalformedResponse(_(@"The server returned an invalid version response.")));
			    return;
		    }
		    NSDictionary *dict = (NSDictionary *)json;
		    id major = dict[@"major"], minor = dict[@"minor"], patch = dict[@"patch"];
		    id prerelease = dict[@"prerelease"];
		    if (!IMServerVersionInteger(major) || !IMServerVersionInteger(minor) ||
		        !IMServerVersionInteger(patch) || prerelease == nil ||
		        (prerelease != [NSNull null] && !IMServerVersionInteger(prerelease))) {
			    completion(nil, IMServerMalformedResponse(_(@"The server returned an invalid version response.")));
			    return;
		    }
		    NSString *version = [NSString stringWithFormat:@"v%ld.%ld.%ld", (long)[major integerValue], (long)[minor integerValue],
		                                                    (long)[patch integerValue]];
		    if (prerelease != [NSNull null]) {
			    version = [version stringByAppendingFormat:@"-rc.%ld", (long)[prerelease integerValue]];
		    }
		    sCachedServerVersion = version;
		    completion(version, nil);
	    }];
}

+ (nullable NSString *)cachedServerVersion {
	return sCachedServerVersion;
}

+ (void)serverStorageWithCompletion:(void (^)(IMServerStorage *_Nullable storage, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/server/storage"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || !IMServerStorageResponseIsValid(json)) {
			    completion(nil, error ?: IMServerMalformedResponse(_(@"The server returned an invalid storage response.")));
			    return;
		    }
		    IMServerStorage *storage = [IMServerStorage storageWithDictionary:(NSDictionary *)json];
		    if (!storage) {
			    completion(nil, IMServerMalformedResponse(_(@"The server returned an invalid storage response.")));
			    return;
		    }
		    sCachedServerStorage = storage;
		    completion(storage, nil);
	    }];
}

+ (nullable IMServerStorage *)cachedServerStorage {
	return sCachedServerStorage;
}

+ (void)serverAboutWithCompletion:(void (^)(IMServerAbout *_Nullable, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/about" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMServerAbout *about = [IMServerAbout aboutWithDictionary:json];
		completion(about, about ? nil : IMServerMalformedResponse(_(@"The server returned invalid server information.")));
	}];
}

+ (void)serverFeaturesWithCompletion:(void (^)(IMServerFeatures *_Nullable, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/features" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMServerFeatures *features = [IMServerFeatures featuresWithDictionary:json];
		completion(features, features ? nil : IMServerMalformedResponse(_(@"The server returned invalid feature information.")));
	}];
}

+ (void)serverConfigWithCompletion:(void (^)(IMServerConfig *_Nullable, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/config" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMServerConfig *config = [IMServerConfig configWithDictionary:json];
		completion(config, config ? nil : IMServerMalformedResponse(_(@"The server returned invalid configuration information.")));
	}];
}

+ (void)supportedMediaTypesWithCompletion:(void (^)(IMServerMediaTypes *_Nullable, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/media-types" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMServerMediaTypes *types = [IMServerMediaTypes mediaTypesWithDictionary:json];
		completion(types, types ? nil : IMServerMalformedResponse(_(@"The server returned invalid media-type information.")));
	}];
}

+ (void)serverVersionCheckWithCompletion:(void (^)(IMServerVersionCheck *_Nullable, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/version-check" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMServerVersionCheck *state = [IMServerVersionCheck versionCheckWithDictionary:json];
		completion(state, state ? nil : IMServerMalformedResponse(_(@"The server returned invalid version-check information.")));
	}];
}

+ (void)serverVersionHistoryWithCompletion:(void (^)(NSArray<IMServerVersionHistoryEntry *> *_Nullable, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/version-history" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMServerMalformedResponse(_(@"The server returned invalid version history.")));
			return;
		}
		NSMutableArray<IMServerVersionHistoryEntry *> *history = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (id value in (NSArray *)json) {
			IMServerVersionHistoryEntry *entry = [IMServerVersionHistoryEntry entryWithDictionary:value];
			if (!entry) {
				completion(nil, IMServerMalformedResponse(_(@"The server returned invalid version history.")));
				return;
			}
			[history addObject:entry];
		}
		completion(history.copy, nil);
	}];
}

+ (void)pingWithCompletion:(void (^)(BOOL, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/ping" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(NO, error); return; }
		if (![json isKindOfClass:[NSDictionary class]] || ![json[@"res"] isKindOfClass:[NSString class]] || [json[@"res"] length] == 0) {
			completion(NO, IMServerMalformedResponse(_(@"The server returned an invalid ping response.")));
			return;
		}
		completion(YES, nil);
	}];
}

+ (void)serverApkLinksWithCompletion:(void (^)(IMServerApkLinks *_Nullable, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/apk-links" query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMServerApkLinks *links = [IMServerApkLinks linksWithDictionary:json];
		completion(links, links ? nil : IMServerMalformedResponse(_(@"The server returned invalid Android download links.")));
	}];
}

+ (void)serverLicenseWithCompletion:(void (^)(IMUserLicense *_Nullable, NSError *_Nullable))completion {
	[[IMApiClient shared] GET:@"/server/license" query:nil completion:^(id json, NSError *error) {
		if (error) {
			if ([IMApiClient HTTPStatusForError:error] == 404) {
				completion(nil, nil);
			} else {
				completion(nil, error);
			}
			return;
		}
		IMUserLicense *license = [IMUserLicense licenseWithDictionary:json];
		completion(license, license ? nil : IMServerMalformedResponse(_(@"The server returned an invalid product license response.")));
	}];
}

+ (void)setServerLicenseWithActivationKey:(NSString *)activationKey
	                            licenseKey:(NSString *)licenseKey
	                            completion:(void (^)(IMUserLicense *_Nullable, NSError *_Nullable))completion {
	NSString *activation = [activationKey isKindOfClass:[NSString class]]
	    ? [activationKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
	NSString *license = [licenseKey isKindOfClass:[NSString class]]
	    ? [licenseKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
	if (activation.length == 0 || !IMServerLicenseKeyIsValid(license)) {
		IMServerLicenseFailObject(completion, IMServerLicenseInputError(nil));
		return;
	}
	[[IMApiClient shared] PUT:@"/server/license"
	                       body:@{ @"activationKey": activation, @"licenseKey": license }
	                 completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMUserLicense *result = [IMUserLicense licenseWithDictionary:json];
		completion(result, result ? nil : IMServerMalformedResponse(_(@"The server returned an invalid product license response.")));
	}];
}

+ (void)deleteServerLicenseWithCompletion:(void (^)(BOOL, NSError *_Nullable))completion {
	[[IMApiClient shared] DELETE:@"/server/license" body:nil completion:^(id json, NSError *error) {
		if (error) {
			if ([IMApiClient HTTPStatusForError:error] == 404) {
				completion(YES, nil);
			} else {
				completion(NO, error);
			}
			return;
		}
		if (json != nil) {
			completion(NO, IMServerMalformedResponse(_(@"The server returned an unexpected product license response.")));
			return;
		}
		completion(YES, nil);
	}];
}

+ (void)serverStatisticsWithCompletion:(void (^)(IMServerStats *, NSError *))completion {
	[[IMApiClient shared] GET:@"/server/statistics" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (!IMServerStatsResponseIsValid(json)) {
			completion(nil, IMServerMalformedResponse(_(@"The server returned invalid statistics.")));
			return;
		}
		IMServerStats *stats = [[IMServerStats alloc] initWithDictionary:json];
		completion(stats, stats ? nil : IMServerMalformedResponse(_(@"The server returned invalid statistics.")));
	}];
}

+ (void)maintenanceStatusWithCompletion:(void (^)(NSDictionary *, NSError *))completion {
	[[IMApiClient shared] GET:@"/admin/maintenance/status" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned invalid maintenance status.")}]);
			return;
		}
		completion(json, nil);
	}];
}

+ (void)setMaintenanceAction:(NSString *)action
       restoreBackupFilename:(NSString *)filename
                   completion:(void (^)(BOOL, NSError *))completion {
	if (action.length == 0) {
		completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: _(@"A maintenance action is required.")}]);
		return;
	}
	NSMutableDictionary *body = [@{ @"action": action } mutableCopy];
	if (filename.length) body[@"restoreBackupFilename"] = filename;
	[[IMApiClient shared] POST:@"/admin/maintenance" body:body completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (void)maintenanceLoginWithToken:(NSString *)token
                        completion:(void (^)(IMMaintenanceAuth *_Nullable, NSError *_Nullable))completion {
	[IMMaintenanceApi loginWithToken:token completion:completion];
}

+ (void)clearCached {
	sCachedServerVersion = nil;
	sCachedServerStorage = nil;
}

@end
