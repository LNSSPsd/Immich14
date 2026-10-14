#import "IMOnboardingStatus.h"
#import "common.h"
#include <string.h>

static BOOL IMOnboardingBool(id value, BOOL *outValue) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	if (!IMJSONIsBoolean(value)) return NO;
	if (outValue) *outValue = [(NSNumber *)value boolValue];
	return YES;
}

@interface IMOnboardingStatus ()
@property (nonatomic, readwrite, getter=isOnboarded) BOOL onboarded;
@end

@implementation IMOnboardingStatus

+ (nullable instancetype)statusWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	BOOL onboarded = NO;
	if (!IMOnboardingBool(dictionary[@"isOnboarded"], &onboarded)) return nil;
	IMOnboardingStatus *status = [[self alloc] init];
	status.onboarded = onboarded;
	return status;
}

@end
