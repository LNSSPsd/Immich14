#import "IMUserPreferencesApi.h"
#import "IMApiClient.h"
#import "common.h"

NSNotificationName const IMUserPreferencesDidChangeNotification = @"IMUserPreferencesDidChangeNotification";

@implementation IMUserPreferencesApi

static IMUserPreferences *sCachedPreferences;

static NSError *IMUserPreferencesMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned invalid user preferences.")}];
}

+ (void)preferencesWithCompletion:(void (^)(IMUserPreferences *, NSError *))completion {
	[[IMApiClient shared] GET:@"/users/me/preferences"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error || ![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, error ?: IMUserPreferencesMalformedResponse());
			return;
		}
		IMUserPreferences *preferences = [[IMUserPreferences alloc] initWithDictionary:json];
		sCachedPreferences = preferences;
		[[NSNotificationCenter defaultCenter] postNotificationName:IMUserPreferencesDidChangeNotification object:preferences];
		completion(preferences, nil);
	}];
}

+ (IMUserPreferences *)cachedPreferences {
	return sCachedPreferences;
}

+ (void)updateSection:(NSString *)section
	            values:(NSDictionary<NSString *, id> *)values
	        completion:(void (^)(IMUserPreferences *, NSError *))completion {
	if (![section isKindOfClass:[NSString class]] || section.length == 0 ||
	    ![values isKindOfClass:[NSDictionary class]] || values.count == 0) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain
		                                    code:0
		                                userInfo:@{NSLocalizedDescriptionKey: _(@"A preference section and value are required.")}]);
		return;
	}
	NSMutableDictionary *sectionValues = [NSMutableDictionary dictionary];
	IMUserPreferences *cached = sCachedPreferences;
	id rawSection = cached.rawDictionary[section];
	if ([rawSection isKindOfClass:[NSDictionary class]]) [sectionValues addEntriesFromDictionary:rawSection];
	[sectionValues addEntriesFromDictionary:values];
	NSDictionary *body = @{ section: sectionValues };
	[[IMApiClient shared] PUT:@"/users/me/preferences"
	                      body:body
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error || ![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, error ?: IMUserPreferencesMalformedResponse());
			return;
		}
		IMUserPreferences *preferences = [[IMUserPreferences alloc] initWithDictionary:json];
		sCachedPreferences = preferences;
		[[NSNotificationCenter defaultCenter] postNotificationName:IMUserPreferencesDidChangeNotification object:preferences];
		completion(preferences, nil);
	}];
}

+ (void)clearCachedPreferences {
	sCachedPreferences = nil;
}

@end
