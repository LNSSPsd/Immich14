#import "IMPrefs.h"
#import "IMAssetApi.h"
#import "common.h"
#include <stdlib.h>

static NSString *const kKeyWifiOnlyUpload = @"IMPrefsWifiOnlyUpload";
static NSString *const kKeyThumbnailQuality = @"IMPrefsThumbnailQuality";
static NSString *const kKeyAllowInsecureTLS = @"IMPrefsAllowInsecureTLS";
static NSString *const kKeyBackupEnabled = @"IMPrefsBackupEnabled";
static NSString *const kKeyLockedPhotosBiometricEnabled = @"IMPrefsLockedPhotosBiometricEnabled";

NSNotificationName const IMPrefsBackupEnabledDidChangeNotification = @"IMPrefsBackupEnabledDidChangeNotification";

#if IM_TROLLSTORE
static NSString *IMPrefsSharedStateDirectory(void) {
	const char *sharedPath = getenv("IM_BACKUP_SUPPORT_PATH");
	NSString *support = (sharedPath && sharedPath[0] != '\0')
	    ? [NSString stringWithUTF8String:sharedPath]
	    : nil;
	if (support.length == 0) {
		support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
	                                             NSUserDomainMask,
	                                             YES).firstObject;
	}
	if (support.length == 0) {
		support = NSTemporaryDirectory();
	}
	[[NSFileManager defaultManager] createDirectoryAtPath:support
	                          withIntermediateDirectories:YES
	                                           attributes:nil
	                                                error:nil];
	return support;
}

static NSString *IMPrefsSharedStateFilePath(void) {
	return [IMPrefsSharedStateDirectory() stringByAppendingPathComponent:@"immich-shared-prefs.plist"];
}
#endif

@interface IMPrefs ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *backing;
@property (nonatomic) dispatch_queue_t queue;
- (void)applyDefaultValuesLocked;
@end

@implementation IMPrefs

+ (instancetype)shared {
	static IMPrefs *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMPrefs alloc] initInternal];
	});
	return shared;
}

- (instancetype)initInternal {
	self = [super init];
	if (self) {
		_queue = dispatch_queue_create(IM_PREFS_QUEUE, DISPATCH_QUEUE_SERIAL);
		NSString *bundleId = [NSBundle mainBundle].bundleIdentifier;
		NSDictionary *std = bundleId
		    ? [[NSUserDefaults standardUserDefaults] persistentDomainForName:bundleId]
		    : nil;
		_backing = [NSMutableDictionary dictionaryWithDictionary:std ?: @{}];
#if IM_TROLLSTORE
		NSDictionary *shared = [NSDictionary dictionaryWithContentsOfFile:IMPrefsSharedStateFilePath()];
		if (shared) {
			[_backing addEntriesFromDictionary:shared];
		}
#endif
		[self applyDefaultValuesLocked];
	}
	return self;
}

- (void)applyDefaultValuesLocked {
	NSDictionary<NSString *, id> *defaultValues = @{
		kKeyWifiOnlyUpload: @YES,
		kKeyThumbnailQuality: IMAssetMediaSizeThumbnail,
		kKeyAllowInsecureTLS: @NO,
		kKeyBackupEnabled: @NO,
		kKeyLockedPhotosBiometricEnabled: @NO,
	};
	[defaultValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
		if (self.backing[key] == nil) {
			self.backing[key] = value;
		}
	}];
}

#pragma mark - Generic interface

- (nullable id)objectForKey:(NSString *)key {
	__block id value = nil;
	dispatch_sync(self.queue, ^{
		value = self.backing[key];
	});
	return value;
}

- (void)setObject:(nullable id)value forKey:(NSString *)key {
	dispatch_sync(self.queue, ^{
		if (value) {
			self.backing[key] = value;
		} else {
			[self.backing removeObjectForKey:key];
		}
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		if (value) {
			[defaults setObject:value forKey:key];
		} else {
			[defaults removeObjectForKey:key];
		}
#if IM_TROLLSTORE
		[self.backing writeToFile:IMPrefsSharedStateFilePath() atomically:YES];
#endif
	});
}

- (BOOL)boolForKey:(NSString *)key {
	return [[self objectForKey:key] boolValue];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
	[self setObject:@(value) forKey:key];
}

- (nullable NSString *)stringForKey:(NSString *)key {
	id value = [self objectForKey:key];
	return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (void)setString:(nullable NSString *)value forKey:(NSString *)key {
	[self setObject:value forKey:key];
}

- (BOOL)synchronize {
	return [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)reloadFromPersistence {
	dispatch_sync(self.queue, ^{
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		(void)[defaults synchronize];
		NSString *bundleId = [NSBundle mainBundle].bundleIdentifier;
		NSDictionary *persisted = bundleId ? [defaults persistentDomainForName:bundleId] : nil;
		self.backing = [NSMutableDictionary dictionaryWithDictionary:persisted ?: @{}];
#if IM_TROLLSTORE
		NSDictionary *shared = [NSDictionary dictionaryWithContentsOfFile:IMPrefsSharedStateFilePath()];
		if (shared) {
			[self.backing addEntriesFromDictionary:shared];
		}
#endif
		[self applyDefaultValuesLocked];
	});
}

#pragma mark - Typed settings

- (BOOL)wifiOnlyUpload {
	return [self boolForKey:kKeyWifiOnlyUpload];
}

- (void)setWifiOnlyUpload:(BOOL)wifiOnlyUpload {
	[self setBool:wifiOnlyUpload forKey:kKeyWifiOnlyUpload];
}

- (NSString *)thumbnailQuality {
	return [self stringForKey:kKeyThumbnailQuality] ?: IMAssetMediaSizeThumbnail;
}

- (void)setThumbnailQuality:(NSString *)thumbnailQuality {
	[self setString:thumbnailQuality forKey:kKeyThumbnailQuality];
}

- (BOOL)allowInsecureTLS {
	return [self boolForKey:kKeyAllowInsecureTLS];
}

- (void)setAllowInsecureTLS:(BOOL)allowInsecureTLS {
	[self setBool:allowInsecureTLS forKey:kKeyAllowInsecureTLS];
}

- (BOOL)backupEnabled {
	return [self boolForKey:kKeyBackupEnabled];
}

- (void)setBackupEnabled:(BOOL)backupEnabled {
	BOOL changed = self.backupEnabled != backupEnabled;
	[self setBool:backupEnabled forKey:kKeyBackupEnabled];
	if (changed) {
		[[NSNotificationCenter defaultCenter] postNotificationName:IMPrefsBackupEnabledDidChangeNotification
		                                                    object:self
		                                                  userInfo:@{ @"enabled": @(backupEnabled) }];
	}
}

- (BOOL)lockedPhotosBiometricEnabled {
	return [self boolForKey:kKeyLockedPhotosBiometricEnabled];
}

- (void)setLockedPhotosBiometricEnabled:(BOOL)lockedPhotosBiometricEnabled {
	[self setBool:lockedPhotosBiometricEnabled forKey:kKeyLockedPhotosBiometricEnabled];
}

@end

#pragma mark - C helpers

BOOL IMPrefsGetBool(const char *key) {
	if (!key) {
		return NO;
	}
	return [IMPrefs.shared boolForKey:[NSString stringWithUTF8String:key]];
}

void IMPrefsSetBool(const char *key, BOOL value) {
	if (!key) {
		return;
	}
	[IMPrefs.shared setBool:value forKey:[NSString stringWithUTF8String:key]];
}

BOOL IMPrefsSynchronize(void) {
	return [IMPrefs.shared synchronize];
}
