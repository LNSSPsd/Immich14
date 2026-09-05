#import "IMUserAccountApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMUserAccountError(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:code
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The server returned an invalid account response.")}];
}

static void IMUserAccountFailObject(void (^completion)(id, NSError *), NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
}

static void IMUserAccountFailBool(void (^completion)(BOOL, NSError *), NSError *error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error); });
}

static BOOL IMUserAccountDateOnly(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 10) return NO;
	static NSRegularExpression *regex;
	static NSDateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$" options:0 error:nil];
		formatter = [[NSDateFormatter alloc] init];
		formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
		formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		formatter.dateFormat = @"yyyy-MM-dd";
		formatter.lenient = NO;
	});
	if ([regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] == nil) return NO;
	NSDate *date = [formatter dateFromString:value];
	return date != nil && [[formatter stringFromDate:date] isEqualToString:value];
}

static BOOL IMUserAccountLicenseKey(NSString *value) {
	if (![value isKindOfClass:[NSString class]]) return NO;
	static NSRegularExpression *regex;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"^IM(SV|CL)(-[0-9A-Za-z]{4}){8}$" options:0 error:nil];
	});
	return [regex firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] != nil;
}

static IMUserLicense *IMUserAccountParseLicense(id json) {
	return [json isKindOfClass:[NSDictionary class]] ? [IMUserLicense licenseWithDictionary:json] : nil;
}

static IMOnboardingStatus *IMUserAccountParseOnboarding(id json) {
	return [json isKindOfClass:[NSDictionary class]] ? [IMOnboardingStatus statusWithDictionary:json] : nil;
}

@implementation IMUserAccountApi

+ (void)calendarHeatmapFromDate:(NSString *)fromDate
                         toDate:(NSString *)toDate
                           type:(NSString *)type
                     completion:(void (^)(IMCalendarHeatmap *, NSError *))completion {
	BOOL invalidFrom = fromDate != nil && (![fromDate isKindOfClass:[NSString class]] || !IMUserAccountDateOnly(fromDate));
	BOOL invalidTo = toDate != nil && (![toDate isKindOfClass:[NSString class]] || !IMUserAccountDateOnly(toDate));
	BOOL invalidType = type != nil && ![type isKindOfClass:[NSString class]];
	NSString *kind = ([type isKindOfClass:[NSString class]] && type.length) ? type : @"Upload";
	if (invalidFrom || invalidTo || invalidType ||
	    (![kind isEqualToString:@"Upload"] && ![kind isEqualToString:@"Taken"])) {
		IMUserAccountFailObject(completion, IMUserAccountError(1, _(@"Use valid UTC dates and choose Upload or Taken activity.")));
		return;
	}
	if (fromDate.length && toDate.length) {
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
		formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		formatter.dateFormat = @"yyyy-MM-dd";
		NSDate *from = [formatter dateFromString:fromDate];
		NSDate *to = [formatter dateFromString:toDate];
		if (!from || !to || [from compare:to] == NSOrderedDescending) {
			IMUserAccountFailObject(completion, IMUserAccountError(1, _(@"The activity start date must be before the end date.")));
			return;
		}
	}
	NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"type" value:kind]];
	if (fromDate.length) [items addObject:[NSURLQueryItem queryItemWithName:@"from" value:fromDate]];
	if (toDate.length) [items addObject:[NSURLQueryItem queryItemWithName:@"to" value:toDate]];
	[[IMApiClient shared] GET:@"/users/me/calendar-heatmap"
	               queryItems:items
	               completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMCalendarHeatmap *heatmap = [IMCalendarHeatmap responseWithDictionary:json];
		completion(heatmap, heatmap ? nil : IMUserAccountError(2, _(@"The server returned an invalid activity heatmap.")));
	}];
}

+ (void)userLicenseWithCompletion:(void (^)(IMUserLicense *, NSError *))completion {
	[[IMApiClient shared] GET:@"/users/me/license" query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMUserLicense *license = IMUserAccountParseLicense(json);
		completion(license, license ? nil : IMUserAccountError(2, _(@"The server returned an invalid license response.")));
	}];
}

+ (void)setUserLicenseWithActivationKey:(NSString *)activationKey
                              licenseKey:(NSString *)licenseKey
                             completion:(void (^)(IMUserLicense *, NSError *))completion {
	NSString *activation = [activationKey isKindOfClass:[NSString class]]
	    ? [activationKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
	NSString *license = [licenseKey isKindOfClass:[NSString class]]
	    ? [licenseKey stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
	if (activation.length == 0 || !IMUserAccountLicenseKey(license)) {
		IMUserAccountFailObject(completion, IMUserAccountError(1, _(@"Enter an activation key and a valid Immich license key.")));
		return;
	}
	[[IMApiClient shared] PUT:@"/users/me/license"
	                       body:@{ @"activationKey": activation, @"licenseKey": license }
	                 completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMUserLicense *result = IMUserAccountParseLicense(json);
		completion(result, result ? nil : IMUserAccountError(2, _(@"The server returned an invalid license response.")));
	}];
}

+ (void)deleteUserLicenseWithCompletion:(void (^)(BOOL, NSError *))completion {
	[[IMApiClient shared] DELETE:@"/users/me/license" body:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (json != nil) {
			completion(NO, IMUserAccountError(2, _(@"The server returned an unexpected license response.")));
			return;
		}
		completion(YES, nil);
	}];
}

+ (void)userOnboardingWithCompletion:(void (^)(IMOnboardingStatus *, NSError *))completion {
	[[IMApiClient shared] GET:@"/users/me/onboarding" query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMOnboardingStatus *status = IMUserAccountParseOnboarding(json);
		completion(status, status ? nil : IMUserAccountError(2, _(@"The server returned an invalid onboarding response.")));
	}];
}

+ (void)setUserOnboarding:(BOOL)onboarded
               completion:(void (^)(IMOnboardingStatus *, NSError *))completion {
	[[IMApiClient shared] PUT:@"/users/me/onboarding"
	                       body:@{ @"isOnboarded": @(onboarded) }
	                 completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMOnboardingStatus *status = IMUserAccountParseOnboarding(json);
		completion(status, status ? nil : IMUserAccountError(2, _(@"The server returned an invalid onboarding response.")));
	}];
}

+ (void)deleteUserOnboardingWithCompletion:(void (^)(BOOL, NSError *))completion {
	[[IMApiClient shared] DELETE:@"/users/me/onboarding" body:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (json != nil) {
			completion(NO, IMUserAccountError(2, _(@"The server returned an unexpected onboarding response.")));
			return;
		}
		completion(YES, nil);
	}];
}

@end
