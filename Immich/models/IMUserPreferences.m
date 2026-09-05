#import "IMUserPreferences.h"

static NSDictionary *IMPreferencesSection(NSDictionary *dictionary, NSString *key) {
	id value = dictionary[key];
	return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static BOOL IMPreferencesBool(NSDictionary *dictionary, NSString *key, BOOL fallback) {
	id value = dictionary[key];
	return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

static NSInteger IMPreferencesInteger(NSDictionary *dictionary, NSString *key, NSInteger fallback) {
	id value = dictionary[key];
	return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : fallback;
}

static NSString *IMPreferencesString(NSDictionary *dictionary, NSString *key, NSString *fallback) {
	id value = dictionary[key];
	return [value isKindOfClass:[NSString class]] && [value length] ? value : fallback;
}

@interface IMUserPreferences ()
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, id> *rawDictionary;
@property (nonatomic, readwrite) BOOL emailEnabled;
@property (nonatomic, readwrite) BOOL emailAlbumInvite;
@property (nonatomic, readwrite) BOOL emailAlbumUpdate;
@property (nonatomic, readwrite) BOOL memoriesEnabled;
@property (nonatomic, readwrite) NSInteger memoriesDuration;
@property (nonatomic, readwrite) BOOL peopleEnabled;
@property (nonatomic, readwrite) NSInteger peopleMinimumFaces;
@property (nonatomic, readwrite) BOOL peopleSidebarWeb;
@property (nonatomic, readwrite) BOOL sharedLinksEnabled;
@property (nonatomic, readwrite) BOOL sharedLinksSidebarWeb;
@property (nonatomic, readwrite) BOOL tagsEnabled;
@property (nonatomic, readwrite) BOOL tagsSidebarWeb;
@property (nonatomic, readwrite) BOOL foldersEnabled;
@property (nonatomic, readwrite) BOOL foldersSidebarWeb;
@property (nonatomic, readwrite) BOOL ratingsEnabled;
@property (nonatomic, copy, readwrite) NSString *defaultAlbumAssetOrder;
@end

@implementation IMUserPreferences

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		_rawDictionary = [dictionary isKindOfClass:[NSDictionary class]] ? [dictionary copy] : @{};
		NSDictionary *email = IMPreferencesSection(_rawDictionary, @"emailNotifications");
		_emailEnabled = IMPreferencesBool(email, @"enabled", NO);
		_emailAlbumInvite = IMPreferencesBool(email, @"albumInvite", YES);
		_emailAlbumUpdate = IMPreferencesBool(email, @"albumUpdate", YES);

		NSDictionary *memories = IMPreferencesSection(_rawDictionary, @"memories");
		_memoriesEnabled = IMPreferencesBool(memories, @"enabled", YES);
		_memoriesDuration = MAX(1, IMPreferencesInteger(memories, @"duration", 5));
		NSDictionary *people = IMPreferencesSection(_rawDictionary, @"people");
		_peopleEnabled = IMPreferencesBool(people, @"enabled", YES);
		_peopleMinimumFaces = MAX(1, IMPreferencesInteger(people, @"minimumFaces", 3));
		_peopleSidebarWeb = IMPreferencesBool(people, @"sidebarWeb", YES);
		NSDictionary *sharedLinks = IMPreferencesSection(_rawDictionary, @"sharedLinks");
		_sharedLinksEnabled = IMPreferencesBool(sharedLinks, @"enabled", YES);
		_sharedLinksSidebarWeb = IMPreferencesBool(sharedLinks, @"sidebarWeb", YES);
		NSDictionary *tags = IMPreferencesSection(_rawDictionary, @"tags");
		_tagsEnabled = IMPreferencesBool(tags, @"enabled", YES);
		_tagsSidebarWeb = IMPreferencesBool(tags, @"sidebarWeb", YES);
		NSDictionary *folders = IMPreferencesSection(_rawDictionary, @"folders");
		_foldersEnabled = IMPreferencesBool(folders, @"enabled", YES);
		_foldersSidebarWeb = IMPreferencesBool(folders, @"sidebarWeb", YES);
		NSDictionary *ratings = IMPreferencesSection(_rawDictionary, @"ratings");
		_ratingsEnabled = IMPreferencesBool(ratings, @"enabled", YES);
		NSDictionary *albums = IMPreferencesSection(_rawDictionary, @"albums");
		_defaultAlbumAssetOrder = [IMPreferencesString(albums, @"defaultAssetOrder", @"desc") copy];
	}
	return self;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
	return self.rawDictionary ?: @{};
}

@end
