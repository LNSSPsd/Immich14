#import "IMPrefs.h"
#import "IMAssetApi.h"

static NSString *const kKeyWifiOnlyUpload = @"IMPrefsWifiOnlyUpload";
static NSString *const kKeyThumbnailQuality = @"IMPrefsThumbnailQuality";
static NSString *const kKeyAllowInsecureTLS = @"IMPrefsAllowInsecureTLS";

@interface IMPrefs ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *backing;
@property (nonatomic) dispatch_queue_t queue;
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
		NSDictionary *std = [NSUserDefaults standardUserDefaults].dictionaryRepresentation;
		_backing = [NSMutableDictionary dictionaryWithDictionary:std ?: @{}];

		NSDictionary<NSString *, id> *defaultValues = @{
			kKeyWifiOnlyUpload: @YES,
			kKeyThumbnailQuality: IMAssetMediaSizeThumbnail,
			kKeyAllowInsecureTLS: @NO,
		};
		[defaultValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
			if (self.backing[key] == nil) {
				self.backing[key] = value;
			}
		}];
	}
	return self;
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
	});
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if (value) {
		[defaults setObject:value forKey:key];
	} else {
		[defaults removeObjectForKey:key];
	}
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
