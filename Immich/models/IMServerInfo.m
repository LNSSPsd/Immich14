#import "IMServerInfo.h"
#import "common.h"
#include <math.h>

static id IMServerInfoValue(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static NSString *IMServerInfoOptionalString(id value) {
	value = IMServerInfoValue(value);
	return [value isKindOfClass:[NSString class]] ? value : nil;
}

static BOOL IMServerInfoRequiredString(id value) {
	return [value isKindOfClass:[NSString class]] && [value length] > 0;
}

static BOOL IMServerInfoRequiredBool(id value) {
	return [value isKindOfClass:[NSNumber class]] &&
	       isfinite([value doubleValue]) &&
	       ([value doubleValue] == 0.0 || [value doubleValue] == 1.0);
}

static BOOL IMServerInfoRequiredInteger(id value) {
	return [value isKindOfClass:[NSNumber class]] &&
	       isfinite([value doubleValue]) &&
	       floor([value doubleValue]) == [value doubleValue];
}

static NSArray<NSString *> *IMServerInfoStringArray(id value) {
	if (![value isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	for (id item in (NSArray *)value) {
		if (![item isKindOfClass:[NSString class]]) return nil;
		[result addObject:item];
	}
	return result.copy;
}

@interface IMServerAbout ()
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *versionURL;
@property (nonatomic) BOOL licensed;
@property (nonatomic, copy, nullable) NSString *build;
@property (nonatomic, copy, nullable) NSString *buildImage;
@property (nonatomic, copy, nullable) NSString *buildImageURL;
@property (nonatomic, copy, nullable) NSString *buildURL;
@property (nonatomic, copy, nullable) NSString *repository;
@property (nonatomic, copy, nullable) NSString *repositoryURL;
@property (nonatomic, copy, nullable) NSString *sourceCommit;
@property (nonatomic, copy, nullable) NSString *sourceRef;
@property (nonatomic, copy, nullable) NSString *sourceURL;
@property (nonatomic, copy, nullable) NSString *nodeJSVersion;
@property (nonatomic, copy, nullable) NSString *ffmpegVersion;
@property (nonatomic, copy, nullable) NSString *exiftoolVersion;
@property (nonatomic, copy, nullable) NSString *imagemagickVersion;
@property (nonatomic, copy, nullable) NSString *libvipsVersion;
@end

@implementation IMServerAbout
+ (nullable instancetype)aboutWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    !IMServerInfoRequiredBool(dictionary[@"licensed"]) ||
	    !IMServerInfoRequiredString(dictionary[@"version"]) ||
	    !IMServerInfoRequiredString(dictionary[@"versionUrl"])) return nil;
	IMServerAbout *about = [[self alloc] init];
	about.version = dictionary[@"version"];
	about.versionURL = dictionary[@"versionUrl"];
	about.licensed = [dictionary[@"licensed"] boolValue];
	about.build = IMServerInfoOptionalString(dictionary[@"build"]);
	about.buildImage = IMServerInfoOptionalString(dictionary[@"buildImage"]);
	about.buildImageURL = IMServerInfoOptionalString(dictionary[@"buildImageUrl"]);
	about.buildURL = IMServerInfoOptionalString(dictionary[@"buildUrl"]);
	about.repository = IMServerInfoOptionalString(dictionary[@"repository"]);
	about.repositoryURL = IMServerInfoOptionalString(dictionary[@"repositoryUrl"]);
	about.sourceCommit = IMServerInfoOptionalString(dictionary[@"sourceCommit"]);
	about.sourceRef = IMServerInfoOptionalString(dictionary[@"sourceRef"]);
	about.sourceURL = IMServerInfoOptionalString(dictionary[@"sourceUrl"]);
	about.nodeJSVersion = IMServerInfoOptionalString(dictionary[@"nodejs"]);
	about.ffmpegVersion = IMServerInfoOptionalString(dictionary[@"ffmpeg"]);
	about.exiftoolVersion = IMServerInfoOptionalString(dictionary[@"exiftool"]);
	about.imagemagickVersion = IMServerInfoOptionalString(dictionary[@"imagemagick"]);
	about.libvipsVersion = IMServerInfoOptionalString(dictionary[@"libvips"]);
	return about;
}
@end

@interface IMServerFeatures ()
@property (nonatomic) BOOL configFile;
@property (nonatomic) BOOL duplicateDetection;
@property (nonatomic) BOOL email;
@property (nonatomic) BOOL facialRecognition;
@property (nonatomic) BOOL importFaces;
@property (nonatomic) BOOL map;
@property (nonatomic) BOOL oauth;
@property (nonatomic) BOOL oauthAutoLaunch;
@property (nonatomic) BOOL ocr;
@property (nonatomic) BOOL passwordLogin;
@property (nonatomic) BOOL realtimeTranscoding;
@property (nonatomic) BOOL reverseGeocoding;
@property (nonatomic) BOOL search;
@property (nonatomic) BOOL sidecar;
@property (nonatomic) BOOL smartSearch;
@property (nonatomic) BOOL trash;
@end

@implementation IMServerFeatures
+ (nullable instancetype)featuresWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	NSArray<NSString *> *keys = @[@"configFile", @"duplicateDetection", @"email", @"facialRecognition",
		@"importFaces", @"map", @"oauth", @"oauthAutoLaunch", @"ocr", @"passwordLogin",
		@"realtimeTranscoding", @"reverseGeocoding", @"search", @"sidecar", @"smartSearch", @"trash"];
	for (NSString *key in keys) if (!IMServerInfoRequiredBool(dictionary[key])) return nil;
	IMServerFeatures *features = [[self alloc] init];
	features.configFile = [dictionary[@"configFile"] boolValue];
	features.duplicateDetection = [dictionary[@"duplicateDetection"] boolValue];
	features.email = [dictionary[@"email"] boolValue];
	features.facialRecognition = [dictionary[@"facialRecognition"] boolValue];
	features.importFaces = [dictionary[@"importFaces"] boolValue];
	features.map = [dictionary[@"map"] boolValue];
	features.oauth = [dictionary[@"oauth"] boolValue];
	features.oauthAutoLaunch = [dictionary[@"oauthAutoLaunch"] boolValue];
	features.ocr = [dictionary[@"ocr"] boolValue];
	features.passwordLogin = [dictionary[@"passwordLogin"] boolValue];
	features.realtimeTranscoding = [dictionary[@"realtimeTranscoding"] boolValue];
	features.reverseGeocoding = [dictionary[@"reverseGeocoding"] boolValue];
	features.search = [dictionary[@"search"] boolValue];
	features.sidecar = [dictionary[@"sidecar"] boolValue];
	features.smartSearch = [dictionary[@"smartSearch"] boolValue];
	features.trash = [dictionary[@"trash"] boolValue];
	return features;
}
@end

@interface IMServerConfig ()
@property (nonatomic, copy) NSString *externalDomain;
@property (nonatomic) BOOL initialized;
@property (nonatomic) BOOL onboarded;
@property (nonatomic, copy) NSString *loginPageMessage;
@property (nonatomic) BOOL maintenanceMode;
@property (nonatomic, copy) NSString *mapDarkStyleURL;
@property (nonatomic, copy) NSString *mapLightStyleURL;
@property (nonatomic) NSInteger minFaces;
@property (nonatomic, copy) NSString *oauthButtonText;
@property (nonatomic) BOOL publicUsers;
@property (nonatomic) NSInteger trashDays;
@property (nonatomic) NSInteger userDeleteDelay;
@end

@implementation IMServerConfig
+ (nullable instancetype)configWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	NSArray<NSString *> *strings = @[@"externalDomain", @"loginPageMessage", @"mapDarkStyleUrl", @"mapLightStyleUrl", @"oauthButtonText"];
	NSArray<NSString *> *booleans = @[@"isInitialized", @"isOnboarded", @"maintenanceMode", @"publicUsers"];
	NSArray<NSString *> *integers = @[@"minFaces", @"trashDays", @"userDeleteDelay"];
	for (NSString *key in strings) if (!IMServerInfoRequiredString(dictionary[key]) && ![dictionary[key] isEqual:@""]) return nil;
	for (NSString *key in booleans) if (!IMServerInfoRequiredBool(dictionary[key])) return nil;
	for (NSString *key in integers) if (!IMServerInfoRequiredInteger(dictionary[key])) return nil;
	IMServerConfig *config = [[self alloc] init];
	config.externalDomain = dictionary[@"externalDomain"];
	config.loginPageMessage = dictionary[@"loginPageMessage"];
	config.mapDarkStyleURL = dictionary[@"mapDarkStyleUrl"];
	config.mapLightStyleURL = dictionary[@"mapLightStyleUrl"];
	config.oauthButtonText = dictionary[@"oauthButtonText"];
	config.initialized = [dictionary[@"isInitialized"] boolValue];
	config.onboarded = [dictionary[@"isOnboarded"] boolValue];
	config.maintenanceMode = [dictionary[@"maintenanceMode"] boolValue];
	config.publicUsers = [dictionary[@"publicUsers"] boolValue];
	config.minFaces = [dictionary[@"minFaces"] integerValue];
	config.trashDays = [dictionary[@"trashDays"] integerValue];
	config.userDeleteDelay = [dictionary[@"userDeleteDelay"] integerValue];
	return config;
}
@end

@interface IMServerMediaTypes ()
@property (nonatomic, copy) NSArray<NSString *> *image;
@property (nonatomic, copy) NSArray<NSString *> *video;
@property (nonatomic, copy) NSArray<NSString *> *sidecar;
@end

@implementation IMServerMediaTypes
+ (nullable instancetype)mediaTypesWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	NSArray *image = IMServerInfoStringArray(dictionary[@"image"]);
	NSArray *video = IMServerInfoStringArray(dictionary[@"video"]);
	NSArray *sidecar = IMServerInfoStringArray(dictionary[@"sidecar"]);
	if (!image || !video || !sidecar) return nil;
	IMServerMediaTypes *types = [[self alloc] init];
	types.image = image; types.video = video; types.sidecar = sidecar;
	return types;
}
@end

@interface IMServerVersionCheck ()
@property (nonatomic, copy, nullable) NSString *checkedAt;
@property (nonatomic, copy, nullable) NSString *releaseVersion;
@end

@implementation IMServerVersionCheck
+ (nullable instancetype)versionCheckWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	for (NSString *key in @[@"checkedAt", @"releaseVersion"]) {
		id value = IMServerInfoValue(dictionary[key]);
		if (value && ![value isKindOfClass:[NSString class]]) return nil;
	}
	IMServerVersionCheck *result = [[self alloc] init];
	result.checkedAt = IMServerInfoOptionalString(dictionary[@"checkedAt"]);
	result.releaseVersion = IMServerInfoOptionalString(dictionary[@"releaseVersion"]);
	return result;
}
@end

@interface IMServerVersionHistoryEntry ()
@property (nonatomic, copy) NSString *entryId;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *createdAt;
@end

@implementation IMServerVersionHistoryEntry
+ (nullable instancetype)entryWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    !IMServerInfoRequiredString(dictionary[@"id"]) ||
	    !IMServerInfoRequiredString(dictionary[@"version"]) ||
	    !IMServerInfoRequiredString(dictionary[@"createdAt"]) ||
	    !IMDateFromServerTimestamp(dictionary[@"createdAt"])) return nil;
	IMServerVersionHistoryEntry *entry = [[self alloc] init];
	entry.entryId = dictionary[@"id"];
	entry.version = dictionary[@"version"];
	entry.createdAt = dictionary[@"createdAt"];
	return entry;
}
@end
