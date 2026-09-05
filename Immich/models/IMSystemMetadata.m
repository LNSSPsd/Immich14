#import "IMSystemMetadata.h"

static id IMSystemMetadataNullable(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMSystemMetadataOptionalString(id value) {
	value = IMSystemMetadataNullable(value);
	return value == nil || [value isKindOfClass:[NSString class]];
}

@interface IMAdminOnboardingStatus ()
@property (nonatomic, readwrite, getter=isOnboarded) BOOL onboarded;
@end

@implementation IMAdminOnboardingStatus
+ (nullable instancetype)statusWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id value = dictionary[@"isOnboarded"];
	if (![value isKindOfClass:[NSNumber class]]) return nil;
	IMAdminOnboardingStatus *status = [[self alloc] init];
	status.onboarded = [value boolValue];
	return status;
}
@end

@interface IMReverseGeocodingState ()
@property (nonatomic, copy, readwrite, nullable) NSString *lastImportFileName;
@property (nonatomic, copy, readwrite, nullable) NSString *lastUpdate;
@end

@implementation IMReverseGeocodingState
+ (nullable instancetype)stateWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    !IMSystemMetadataOptionalString(dictionary[@"lastImportFileName"]) ||
	    !IMSystemMetadataOptionalString(dictionary[@"lastUpdate"])) return nil;
	IMReverseGeocodingState *state = [[self alloc] init];
	state.lastImportFileName = [IMSystemMetadataNullable(dictionary[@"lastImportFileName"]) copy];
	state.lastUpdate = [IMSystemMetadataNullable(dictionary[@"lastUpdate"]) copy];
	return state;
}
@end

@interface IMVersionCheckState ()
@property (nonatomic, copy, readwrite, nullable) NSString *checkedAt;
@property (nonatomic, copy, readwrite, nullable) NSString *releaseVersion;
@end

@implementation IMVersionCheckState
+ (nullable instancetype)stateWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    !IMSystemMetadataOptionalString(dictionary[@"checkedAt"]) ||
	    !IMSystemMetadataOptionalString(dictionary[@"releaseVersion"])) return nil;
	IMVersionCheckState *state = [[self alloc] init];
	state.checkedAt = [IMSystemMetadataNullable(dictionary[@"checkedAt"]) copy];
	state.releaseVersion = [IMSystemMetadataNullable(dictionary[@"releaseVersion"]) copy];
	return state;
}
@end
