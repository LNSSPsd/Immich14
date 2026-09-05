#import "IMAdminUtilityApi.h"
#import "IMApiClient.h"
#import "common.h"
#include <math.h>
#include <string.h>

static NSError *IMAdminUtilityError(NSString *message, NSInteger code) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:code
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The server rejected this administrator action.")}];
}

static NSError *IMAdminUtilityMalformedResponse(void) {
	return IMAdminUtilityError(_(@"The server returned an invalid administrator response."), 2);
}

static BOOL IMAdminUtilityBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMAdminUtilityInteger(id value, NSInteger minimum, NSInteger maximum) {
	if (![value isKindOfClass:[NSNumber class]] || IMAdminUtilityBoolean(value)) return NO;
	double number = [(NSNumber *)value doubleValue];
	return isfinite(number) && floor(number) == number && number >= (double)minimum && number <= (double)maximum;
}

static BOOL IMAdminUtilityString(id value) {
	return [value isKindOfClass:[NSString class]];
}

static BOOL IMAdminUtilitySMTPIsValid(NSDictionary *smtp) {
	if (![smtp isKindOfClass:[NSDictionary class]] || ![NSJSONSerialization isValidJSONObject:smtp]) return NO;
	if (!IMAdminUtilityBoolean(smtp[@"enabled"]) || !IMAdminUtilityString(smtp[@"from"]) ||
	    !IMAdminUtilityString(smtp[@"replyTo"])) return NO;
	id transportValue = smtp[@"transport"];
	if (![transportValue isKindOfClass:[NSDictionary class]]) return NO;
	NSDictionary *transport = transportValue;
	return IMAdminUtilityBoolean(transport[@"ignoreCert"]) && IMAdminUtilityString(transport[@"host"]) &&
	       IMAdminUtilityInteger(transport[@"port"], 0, 65535) && IMAdminUtilityBoolean(transport[@"secure"]) &&
	       IMAdminUtilityString(transport[@"username"]) && IMAdminUtilityString(transport[@"password"]);
}

static void IMAdminUtilityCompleteOnMain(void (^completion)(id _Nullable value, NSError *_Nullable error),
	                                       id _Nullable value,
	                                       NSError *_Nullable error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(value, error); });
}

@implementation IMAdminUtilityApi

+ (void)unlinkAllOAuthAccountsWithCompletion:(void (^)(BOOL, NSError *))completion {
	[[IMApiClient shared] POST:@"/admin/auth/unlink-all" body:nil completion:^(id json, NSError *error) {
		(void)json;
		completion(error == nil, error);
	}];
}

+ (void)detectPriorInstallWithCompletion:(void (^)(IMMaintenanceDetectInstall *, NSError *))completion {
	[[IMApiClient shared] GET:@"/admin/maintenance/detect-install" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMMaintenanceDetectInstall *result = [IMMaintenanceDetectInstall responseWithDictionary:json];
		completion(result, result ? nil : IMAdminUtilityMalformedResponse());
	}];
}

+ (void)sendTestEmailWithSMTPConfiguration:(NSDictionary<NSString *,id> *)smtp
	                                completion:(void (^)(IMTestEmailResponse *, NSError *))completion {
	if (!IMAdminUtilitySMTPIsValid(smtp)) {
		IMAdminUtilityCompleteOnMain(completion, nil, IMAdminUtilityError(_(@"Enter a complete SMTP configuration before sending a test email."), 1));
		return;
	}
	[[IMApiClient shared] POST:@"/admin/notifications/test-email" body:smtp completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMTestEmailResponse *response = [IMTestEmailResponse responseWithDictionary:json];
		completion(response, response ? nil : IMAdminUtilityMalformedResponse());
	}];
}

@end
