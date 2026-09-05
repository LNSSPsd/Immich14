#import "IMSystemMetadataApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMSystemMetadataError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The server returned invalid system metadata.") }];
}

@implementation IMSystemMetadataApi

+ (void)adminOnboardingWithCompletion:(void (^)(IMAdminOnboardingStatus *, NSError *))completion {
	[[IMApiClient shared] GET:@"/system-metadata/admin-onboarding" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMAdminOnboardingStatus *status = [IMAdminOnboardingStatus statusWithDictionary:json];
		completion(status, status ? nil : IMSystemMetadataError(_(@"The server returned invalid onboarding status.")));
	}];
}

+ (void)setAdminOnboarded:(BOOL)onboarded completion:(void (^)(BOOL, NSError *))completion {
	[[IMApiClient shared] POST:@"/system-metadata/admin-onboarding"
	                       body:@{ @"isOnboarded": @(onboarded) }
	                 completion:^(id json, NSError *error) {
		(void)json;
		completion(error == nil, error);
	}];
}

+ (void)reverseGeocodingStateWithCompletion:(void (^)(IMReverseGeocodingState *, NSError *))completion {
	[[IMApiClient shared] GET:@"/system-metadata/reverse-geocoding-state" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMReverseGeocodingState *state = [IMReverseGeocodingState stateWithDictionary:json];
		completion(state, state ? nil : IMSystemMetadataError(_(@"The server returned invalid reverse-geocoding status.")));
	}];
}

+ (void)versionCheckStateWithCompletion:(void (^)(IMVersionCheckState *, NSError *))completion {
	[[IMApiClient shared] GET:@"/system-metadata/version-check-state" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMVersionCheckState *state = [IMVersionCheckState stateWithDictionary:json];
		completion(state, state ? nil : IMSystemMetadataError(_(@"The server returned invalid version-check status.")));
	}];
}

@end
