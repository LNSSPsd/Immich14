#import "IMSystemConfig.h"
#include <math.h>
#include <string.h>

static NSArray<NSString *> *IMSystemConfigRequiredNames(void) {
	static NSArray<NSString *> *names;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		names = @[
			@"backup", @"ffmpeg", @"image", @"integrityChecks", @"job", @"library",
			@"logging", @"machineLearning", @"map", @"metadata", @"newVersionCheck",
			@"nightlyTasks", @"notifications", @"oauth", @"passwordLogin",
			@"reverseGeocoding", @"server", @"storageTemplate", @"templates", @"theme",
			@"trash", @"user"
		];
	});
	return names;
}

static BOOL IMSystemConfigJSONDictionary(NSDictionary *dictionary) {
	return [dictionary isKindOfClass:[NSDictionary class]] &&
	       [NSJSONSerialization isValidJSONObject:dictionary];
}

static id IMSystemConfigImmutableJSONValue(id value) {
	if ([value isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)value count]];
		[(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
			id immutable = IMSystemConfigImmutableJSONValue(object);
			if (immutable && key) result[key] = immutable;
		}];
		return [result copy];
	}
	if ([value isKindOfClass:[NSArray class]]) {
		NSMutableArray *result = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
		for (id object in (NSArray *)value) {
			id immutable = IMSystemConfigImmutableJSONValue(object);
			if (!immutable) return nil;
			[result addObject:immutable];
		}
		return [result copy];
	}
	if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
	    [value isKindOfClass:[NSNull class]]) {
		return [value copy];
	}
	return nil;
}

static NSDictionary *IMSystemConfigSection(NSDictionary *dictionary, NSString *name) {
	id value = dictionary[name];
	return [value isKindOfClass:[NSDictionary class]] ? (NSDictionary *)value : @{};
}

static BOOL IMSystemConfigBoolean(NSDictionary *dictionary, NSString *name) {
	id value = dictionary[name];
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)
	    ? [(NSNumber *)value boolValue] : NO;
}

static NSInteger IMSystemConfigInteger(NSDictionary *dictionary, NSString *name) {
	id value = dictionary[name];
	if (![value isKindOfClass:[NSNumber class]]) return 0;
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) return 0;
	double number = [(NSNumber *)value doubleValue];
	if (!isfinite(number) || floor(number) != number) return 0;
	return [(NSNumber *)value integerValue];
}

static NSString *IMSystemConfigString(NSDictionary *dictionary, NSString *name) {
	id value = dictionary[name];
	return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

@interface IMSystemConfig ()
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, id> *rawDictionary;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSDictionary *> *sections;
@property (nonatomic, readwrite) BOOL mapEnabled;
@property (nonatomic, readwrite) BOOL reverseGeocodingEnabled;
@property (nonatomic, readwrite) BOOL machineLearningEnabled;
@property (nonatomic, readwrite) BOOL libraryWatchEnabled;
@property (nonatomic, readwrite) BOOL newVersionCheckEnabled;
@property (nonatomic, readwrite) BOOL passwordLoginEnabled;
@property (nonatomic, readwrite) BOOL serverPublicUsers;
@property (nonatomic, readwrite) BOOL trashEnabled;
@property (nonatomic, readwrite) NSInteger trashDays;
@property (nonatomic, readwrite) BOOL storageTemplateEnabled;
@property (nonatomic, readwrite) BOOL storageHashVerificationEnabled;
@property (nonatomic, copy, readwrite) NSString *externalDomain;
@property (nonatomic, copy, readwrite) NSString *loginPageMessage;
@property (nonatomic, copy, readwrite) NSString *storageTemplate;
@end

@implementation IMSystemConfig

+ (NSArray<NSString *> *)requiredSectionNames {
	return IMSystemConfigRequiredNames();
}

+ (nullable instancetype)configWithDictionary:(NSDictionary *)dictionary {
	return [[self alloc] initWithDictionary:dictionary];
}

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary {
	if (!IMSystemConfigJSONDictionary(dictionary)) return nil;
	for (NSString *name in IMSystemConfigRequiredNames()) {
		if (![dictionary[name] isKindOfClass:[NSDictionary class]]) return nil;
	}
	self = [super init];
	if (!self) return nil;
	NSDictionary *immutableDictionary = IMSystemConfigImmutableJSONValue(dictionary);
	if (![immutableDictionary isKindOfClass:[NSDictionary class]]) return nil;
	_rawDictionary = [immutableDictionary copy];
	NSMutableDictionary<NSString *, NSDictionary *> *sectionCopy = [NSMutableDictionary dictionaryWithCapacity:IMSystemConfigRequiredNames().count];
	for (NSString *name in IMSystemConfigRequiredNames()) sectionCopy[name] = [_rawDictionary[name] copy];
	_sections = [sectionCopy copy];

	NSDictionary *map = IMSystemConfigSection(_rawDictionary, @"map");
	_mapEnabled = IMSystemConfigBoolean(map, @"enabled");
	NSDictionary *reverse = IMSystemConfigSection(_rawDictionary, @"reverseGeocoding");
	_reverseGeocodingEnabled = IMSystemConfigBoolean(reverse, @"enabled");
	NSDictionary *machineLearning = IMSystemConfigSection(_rawDictionary, @"machineLearning");
	_machineLearningEnabled = IMSystemConfigBoolean(machineLearning, @"enabled");
	NSDictionary *library = IMSystemConfigSection(_rawDictionary, @"library");
	NSDictionary *watch = IMSystemConfigSection(library, @"watch");
	_libraryWatchEnabled = IMSystemConfigBoolean(watch, @"enabled");
	NSDictionary *newVersion = IMSystemConfigSection(_rawDictionary, @"newVersionCheck");
	_newVersionCheckEnabled = IMSystemConfigBoolean(newVersion, @"enabled");
	NSDictionary *password = IMSystemConfigSection(_rawDictionary, @"passwordLogin");
	_passwordLoginEnabled = IMSystemConfigBoolean(password, @"enabled");
	NSDictionary *trash = IMSystemConfigSection(_rawDictionary, @"trash");
	_trashEnabled = IMSystemConfigBoolean(trash, @"enabled");
	_trashDays = MAX(0, IMSystemConfigInteger(trash, @"days"));
	NSDictionary *storage = IMSystemConfigSection(_rawDictionary, @"storageTemplate");
	_storageTemplateEnabled = IMSystemConfigBoolean(storage, @"enabled");
	_storageHashVerificationEnabled = IMSystemConfigBoolean(storage, @"hashVerificationEnabled");
	_storageTemplate = [IMSystemConfigString(storage, @"template") copy];
	NSDictionary *server = IMSystemConfigSection(_rawDictionary, @"server");
	_serverPublicUsers = IMSystemConfigBoolean(server, @"publicUsers");
	_externalDomain = [IMSystemConfigString(server, @"externalDomain") copy];
	_loginPageMessage = [IMSystemConfigString(server, @"loginPageMessage") copy];
	return self;
}

- (instancetype)init {
	return [self initWithDictionary:@{}];
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
	return [self.rawDictionary copy] ?: @{};
}

@end
