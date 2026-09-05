#import "IMAdminUserPreferences.h"
#import "IMApiClient.h"
#import "common.h"
#include <math.h>
#include <string.h>

static BOOL IMAdminPreferencesBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMAdminPreferencesInteger(id value, NSInteger minimum, NSInteger maximum, NSInteger *outValue) {
	if (![value isKindOfClass:[NSNumber class]] || IMAdminPreferencesBoolean(value)) return NO;
	double numeric = [(NSNumber *)value doubleValue];
	if (!isfinite(numeric) || floor(numeric) != numeric || numeric < (double)minimum ||
	    numeric > (double)maximum || numeric < -9007199254740991.0 || numeric > 9007199254740991.0) {
		return NO;
	}
	if (outValue) *outValue = [(NSNumber *)value integerValue];
	return YES;
}

static BOOL IMAdminPreferencesString(id value) {
	return [value isKindOfClass:[NSString class]];
}

static BOOL IMAdminPreferencesEnum(id value, NSArray<NSString *> *allowed) {
	return [value isKindOfClass:[NSString class]] && [allowed containsObject:value];
}

static NSDictionary *IMAdminPreferencesSection(NSDictionary *dictionary, NSString *key) {
	id value = dictionary[key];
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static BOOL IMAdminPreferencesRequiredBool(NSDictionary *section, NSString *key, BOOL *outValue) {
	id value = section[key];
	if (!IMAdminPreferencesBoolean(value)) return NO;
	if (outValue) *outValue = [value boolValue];
	return YES;
}

static BOOL IMAdminPreferencesRequiredInteger(NSDictionary *section, NSString *key, NSInteger minimum, NSInteger maximum, NSInteger *outValue) {
	return IMAdminPreferencesInteger(section[key], minimum, maximum, outValue);
}

static BOOL IMAdminPreferencesRequiredString(NSDictionary *section, NSString *key, NSString **outValue) {
	id value = section[key];
	if (!IMAdminPreferencesString(value)) return NO;
	if (outValue) *outValue = value;
	return YES;
}

static NSError *IMAdminPreferencesValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"Enter valid user preferences.") }];
}

static BOOL IMAdminPreferencesValidateSection(NSDictionary *section,
	                                             NSString *sectionName,
	                                             NSDictionary<NSString *, NSString *> *types,
	                                             NSError **error) {
	if (![section isKindOfClass:[NSDictionary class]]) {
		if (error) *error = IMAdminPreferencesValidationError([NSString stringWithFormat:_(@"The %@ preference section is invalid."), sectionName]);
		return NO;
	}
	NSSet<NSString *> *allowed = [NSSet setWithArray:types.allKeys];
	for (id rawKey in section) {
		if (![rawKey isKindOfClass:[NSString class]] || ![allowed containsObject:rawKey]) {
			if (![rawKey isKindOfClass:[NSString class]] ||
			    ![NSJSONSerialization isValidJSONObject:@{ rawKey: section[rawKey] ?: [NSNull null] }]) {
				if (error) *error = IMAdminPreferencesValidationError(_(@"The preference contains an invalid unknown field."));
				return NO;
			}
			continue;
		}
		NSString *kind = types[rawKey];
		id value = section[rawKey];
		BOOL valid = NO;
		if ([kind isEqualToString:@"bool"]) valid = IMAdminPreferencesBoolean(value);
		else if ([kind isEqualToString:@"string"]) valid = IMAdminPreferencesString(value);
		else if ([kind isEqualToString:@"order"]) valid = IMAdminPreferencesEnum(value, @[ @"asc", @"desc" ]);
		else if ([kind isEqualToString:@"color"]) valid = IMAdminPreferencesEnum(value, @[ @"primary", @"pink", @"red", @"yellow", @"blue", @"green", @"purple", @"orange", @"gray", @"amber" ]);
		else if ([kind isEqualToString:@"positiveInt"]) valid = IMAdminPreferencesInteger(value, 1, 9007199254740991LL, NULL);
		if (!valid) {
			if (error) *error = IMAdminPreferencesValidationError([NSString stringWithFormat:_(@"The %@ preference value is invalid."), rawKey]);
			return NO;
		}
	}
	return YES;
}

@interface IMAdminUserPreferences ()
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, id> *rawDictionary;
@property (nonatomic, copy, readwrite) NSString *defaultAlbumAssetOrder;
@property (nonatomic, readwrite) BOOL gCastEnabled;
@property (nonatomic, readwrite) NSInteger archiveSize;
@property (nonatomic, readwrite) BOOL includeEmbeddedVideos;
@property (nonatomic, readwrite) BOOL emailAlbumInvite;
@property (nonatomic, readwrite) BOOL emailAlbumUpdate;
@property (nonatomic, readwrite) BOOL emailEnabled;
@property (nonatomic, readwrite) BOOL foldersEnabled;
@property (nonatomic, readwrite) BOOL foldersSidebarWeb;
@property (nonatomic, readwrite) NSInteger memoriesDuration;
@property (nonatomic, readwrite) BOOL memoriesEnabled;
@property (nonatomic, readwrite) BOOL peopleEnabled;
@property (nonatomic, readwrite) NSInteger peopleMinimumFaces;
@property (nonatomic, readwrite) BOOL peopleSidebarWeb;
@property (nonatomic, copy, readwrite) NSString *hideBuyButtonUntil;
@property (nonatomic, readwrite) BOOL showSupportBadge;
@property (nonatomic, readwrite) BOOL ratingsEnabled;
@property (nonatomic, readwrite) BOOL recentlyAddedSidebarWeb;
@property (nonatomic, readwrite) BOOL sharedLinksEnabled;
@property (nonatomic, readwrite) BOOL sharedLinksSidebarWeb;
@property (nonatomic, readwrite) BOOL tagsEnabled;
@property (nonatomic, readwrite) BOOL tagsSidebarWeb;
@end

@implementation IMAdminUserPreferences

+ (nullable instancetype)preferencesWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	NSDictionary *albums = IMAdminPreferencesSection(dictionary, @"albums");
	NSDictionary *cast = IMAdminPreferencesSection(dictionary, @"cast");
	NSDictionary *download = IMAdminPreferencesSection(dictionary, @"download");
	NSDictionary *email = IMAdminPreferencesSection(dictionary, @"emailNotifications");
	NSDictionary *folders = IMAdminPreferencesSection(dictionary, @"folders");
	NSDictionary *memories = IMAdminPreferencesSection(dictionary, @"memories");
	NSDictionary *people = IMAdminPreferencesSection(dictionary, @"people");
	NSDictionary *purchase = IMAdminPreferencesSection(dictionary, @"purchase");
	NSDictionary *ratings = IMAdminPreferencesSection(dictionary, @"ratings");
	NSDictionary *recentlyAdded = IMAdminPreferencesSection(dictionary, @"recentlyAdded");
	NSDictionary *sharedLinks = IMAdminPreferencesSection(dictionary, @"sharedLinks");
	NSDictionary *tags = IMAdminPreferencesSection(dictionary, @"tags");
	if (!albums || !cast || !download || !email || !folders || !memories || !people || !purchase ||
	    !ratings || !recentlyAdded || !sharedLinks || !tags) return nil;

	IMAdminUserPreferences *result = [[self alloc] init];
	NSString *order = nil;
	NSInteger archiveSize = 0, memoriesDuration = 0, minimumFaces = 0;
	BOOL value = NO;
	BOOL emailAlbumInvite = NO, emailAlbumUpdate = NO, emailEnabled = NO;
	BOOL foldersEnabled = NO, foldersSidebarWeb = NO, memoriesEnabled = NO;
	BOOL peopleEnabled = NO, peopleSidebarWeb = NO, showSupportBadge = NO;
	BOOL ratingsEnabled = NO, recentlyAddedSidebarWeb = NO;
	BOOL sharedLinksEnabled = NO, sharedLinksSidebarWeb = NO, tagsEnabled = NO, tagsSidebarWeb = NO;
	NSString *hideBuyButtonUntil = nil;
	if (!IMAdminPreferencesRequiredString(albums, @"defaultAssetOrder", &order) ||
	    !IMAdminPreferencesEnum(order, @[ @"asc", @"desc" ]) ||
	    !IMAdminPreferencesRequiredBool(cast, @"gCastEnabled", &value)) return nil;
	result.defaultAlbumAssetOrder = [order copy];
	result.gCastEnabled = value;
	if (!IMAdminPreferencesRequiredInteger(download, @"archiveSize", -9007199254740991LL, 9007199254740991LL, &archiveSize) ||
	    !IMAdminPreferencesRequiredBool(download, @"includeEmbeddedVideos", &value)) return nil;
	result.archiveSize = archiveSize;
	result.includeEmbeddedVideos = value;
	if (!IMAdminPreferencesRequiredBool(email, @"albumInvite", &emailAlbumInvite) ||
	    !IMAdminPreferencesRequiredBool(email, @"albumUpdate", &emailAlbumUpdate) ||
	    !IMAdminPreferencesRequiredBool(email, @"enabled", &emailEnabled) ||
	    !IMAdminPreferencesRequiredBool(folders, @"enabled", &foldersEnabled) ||
	    !IMAdminPreferencesRequiredBool(folders, @"sidebarWeb", &foldersSidebarWeb) ||
	    !IMAdminPreferencesRequiredInteger(memories, @"duration", -9007199254740991LL, 9007199254740991LL, &memoriesDuration) ||
	    !IMAdminPreferencesRequiredBool(memories, @"enabled", &memoriesEnabled) ||
	    !IMAdminPreferencesRequiredBool(people, @"enabled", &peopleEnabled) ||
	    !IMAdminPreferencesRequiredBool(people, @"sidebarWeb", &peopleSidebarWeb) ||
	    !IMAdminPreferencesRequiredBool(purchase, @"showSupportBadge", &showSupportBadge) ||
	    !IMAdminPreferencesRequiredBool(ratings, @"enabled", &ratingsEnabled) ||
	    !IMAdminPreferencesRequiredBool(recentlyAdded, @"sidebarWeb", &recentlyAddedSidebarWeb) ||
	    !IMAdminPreferencesRequiredBool(sharedLinks, @"enabled", &sharedLinksEnabled) ||
	    !IMAdminPreferencesRequiredBool(sharedLinks, @"sidebarWeb", &sharedLinksSidebarWeb) ||
	    !IMAdminPreferencesRequiredBool(tags, @"enabled", &tagsEnabled) ||
	    !IMAdminPreferencesRequiredBool(tags, @"sidebarWeb", &tagsSidebarWeb) ||
	    !IMAdminPreferencesRequiredString(purchase, @"hideBuyButtonUntil", &hideBuyButtonUntil)) return nil;
	result.emailAlbumInvite = emailAlbumInvite;
	result.emailAlbumUpdate = emailAlbumUpdate;
	result.emailEnabled = emailEnabled;
	result.foldersEnabled = foldersEnabled;
	result.foldersSidebarWeb = foldersSidebarWeb;
	result.memoriesEnabled = memoriesEnabled;
	result.peopleEnabled = peopleEnabled;
	result.peopleSidebarWeb = peopleSidebarWeb;
	result.showSupportBadge = showSupportBadge;
	result.ratingsEnabled = ratingsEnabled;
	result.recentlyAddedSidebarWeb = recentlyAddedSidebarWeb;
	result.sharedLinksEnabled = sharedLinksEnabled;
	result.sharedLinksSidebarWeb = sharedLinksSidebarWeb;
	result.tagsEnabled = tagsEnabled;
	result.tagsSidebarWeb = tagsSidebarWeb;
	result.hideBuyButtonUntil = [hideBuyButtonUntil copy];
	result.memoriesDuration = memoriesDuration;
	if ([people objectForKey:@"minimumFaces"] != nil &&
	    !IMAdminPreferencesRequiredInteger(people, @"minimumFaces", 1, 9007199254740991LL, &minimumFaces)) return nil;
	result.peopleMinimumFaces = minimumFaces;
	result.rawDictionary = [dictionary copy];
	return result;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
	return self.rawDictionary ?: @{};
}

+ (BOOL)validateUpdateDictionary:(NSDictionary *)dictionary error:(NSError **)error {
	if (error) *error = nil;
	if (![dictionary isKindOfClass:[NSDictionary class]] || dictionary.count == 0) {
		if (error) *error = IMAdminPreferencesValidationError(_(@"Choose at least one preference to update."));
		return NO;
	}
	NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *schemas = @{
		@"albums": @{ @"defaultAssetOrder": @"order" },
		@"avatar": @{ @"color": @"color" },
		@"cast": @{ @"gCastEnabled": @"bool" },
		@"download": @{ @"archiveSize": @"positiveInt", @"includeEmbeddedVideos": @"bool" },
		@"emailNotifications": @{ @"albumInvite": @"bool", @"albumUpdate": @"bool", @"enabled": @"bool" },
		@"folders": @{ @"enabled": @"bool", @"sidebarWeb": @"bool" },
		@"memories": @{ @"duration": @"positiveInt", @"enabled": @"bool" },
		@"people": @{ @"enabled": @"bool", @"minimumFaces": @"positiveInt", @"sidebarWeb": @"bool" },
		@"purchase": @{ @"hideBuyButtonUntil": @"string", @"showSupportBadge": @"bool" },
		@"ratings": @{ @"enabled": @"bool" },
		@"recentlyAdded": @{ @"sidebarWeb": @"bool" },
		@"sharedLinks": @{ @"enabled": @"bool", @"sidebarWeb": @"bool" },
		@"tags": @{ @"enabled": @"bool", @"sidebarWeb": @"bool" }
	};
	for (id rawKey in dictionary) {
		if (![rawKey isKindOfClass:[NSString class]] || !schemas[rawKey]) {
			if (error) *error = IMAdminPreferencesValidationError(_(@"The preference contains an unknown section."));
			return NO;
		}
		id sectionValue = dictionary[rawKey];
		if (!IMAdminPreferencesValidateSection(sectionValue, rawKey, schemas[rawKey], error)) return NO;
	}
	if (![NSJSONSerialization isValidJSONObject:dictionary]) {
		if (error) *error = IMAdminPreferencesValidationError(_(@"The preference values cannot be encoded as JSON."));
		return NO;
	}
	return YES;
}

@end
