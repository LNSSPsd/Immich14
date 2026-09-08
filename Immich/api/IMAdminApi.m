#import "IMAdminApi.h"
#import "IMApiClient.h"
#import "IMAdminUserPreferences.h"
#import "common.h"
#import <math.h>
#include <limits.h>
#include <string.h>

static NSError *IMAdminMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid administrator response.")}];
}

static NSError *IMAdminValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The administrator request is invalid.")}];
}

static BOOL IMAdminUserIdIsValid(id value) {
	if (![value isKindOfClass:[NSString class]]) return NO;
	return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

static BOOL IMAdminPreferencesUserIdIsValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
	static NSRegularExpression *expression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:
		    @"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
		                                                         options:0
		                                                           error:NULL];
	});
	return [expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] != nil;
}

static BOOL IMAdminPreferencesDateOnly(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 10) return NO;
	static NSRegularExpression *expression;
	static NSDateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$" options:0 error:NULL];
		formatter = [[NSDateFormatter alloc] init];
		formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
		formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		formatter.dateFormat = @"yyyy-MM-dd";
		formatter.lenient = NO;
	});
	if ([expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] == nil) return NO;
	NSDate *date = [formatter dateFromString:value];
	return date != nil && [[formatter stringFromDate:date] isEqualToString:value];
}

static NSString *IMAdminPathComponent(NSString *value) {
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
	    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static BOOL IMAdminBooleanValue(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMAdminQuotaValue(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	if (IMAdminBooleanValue(value)) return NO;
	double numeric = [(NSNumber *)value doubleValue];
	return isfinite(numeric) && floor(numeric) == numeric && numeric >= 0.0 &&
	       numeric <= 9007199254740991.0 && numeric <= (double)LLONG_MAX;
}

static BOOL IMAdminEmailIsValid(NSString *email) {
	if (![email isKindOfClass:[NSString class]] || email.length == 0) return NO;
	static NSRegularExpression *expression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:
		    @"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
		                                                         options:0
		                                                           error:NULL];
	});
	NSRange range = NSMakeRange(0, email.length);
	return [expression firstMatchInString:email options:0 range:range] != nil;
}

static BOOL IMAdminNullableStringValue(id value) {
	return [value isKindOfClass:[NSNull class]] || [value isKindOfClass:[NSString class]];
}

static BOOL IMAdminAvatarColorValue(id value) {
	if ([value isKindOfClass:[NSNull class]]) return YES;
	if (![value isKindOfClass:[NSString class]]) return NO;
	static NSSet<NSString *> *colors;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		colors = [NSSet setWithArray:@[ @"primary", @"pink", @"red", @"yellow", @"blue", @"green", @"purple", @"orange", @"gray", @"amber" ]];
	});
	return [colors containsObject:value];
}

static BOOL IMAdminPinCodeValue(id value) {
	if ([value isKindOfClass:[NSNull class]]) return YES;
	if (![value isKindOfClass:[NSString class]]) return NO;
	static NSRegularExpression *expression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]{6}$" options:0 error:NULL];
	});
	return [expression firstMatchInString:value options:0 range:NSMakeRange(0, [(NSString *)value length])] != nil;
}

static BOOL IMAdminUpdateFieldsAreValid(NSDictionary *fields) {
	if (![fields isKindOfClass:[NSDictionary class]] || fields.count == 0) return NO;
	NSSet<NSString *> *allowed = [NSSet setWithArray:@[
		@"avatarColor", @"email", @"isAdmin", @"name", @"password", @"pinCode",
		@"quotaSizeInBytes", @"shouldChangePassword", @"storageLabel"
	]];
	for (id rawKey in fields) {
		if (![rawKey isKindOfClass:[NSString class]] || ![allowed containsObject:rawKey]) return NO;
		id value = fields[rawKey];
		NSString *key = (NSString *)rawKey;
		if ([key isEqualToString:@"avatarColor"]) {
			if (!IMAdminAvatarColorValue(value)) return NO;
		} else if ([key isEqualToString:@"email"]) {
			if (!IMAdminEmailIsValid(value)) return NO;
		} else if ([key isEqualToString:@"isAdmin"] || [key isEqualToString:@"shouldChangePassword"]) {
			if (!IMAdminBooleanValue(value)) return NO;
		} else if ([key isEqualToString:@"name"]) {
			if (![value isKindOfClass:[NSString class]]) return NO;
		} else if ([key isEqualToString:@"password"]) {
			if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) return NO;
		} else if ([key isEqualToString:@"pinCode"]) {
			if (!IMAdminPinCodeValue(value)) return NO;
		} else if ([key isEqualToString:@"quotaSizeInBytes"]) {
			if (![value isKindOfClass:[NSNull class]] && !IMAdminQuotaValue(value)) return NO;
		} else if ([key isEqualToString:@"storageLabel"]) {
			if (!IMAdminNullableStringValue(value)) return NO;
		}
	}
	return [NSJSONSerialization isValidJSONObject:fields];
}

static BOOL IMAdminUsersResponseIsValid(NSArray *values) {
	if (![values isKindOfClass:[NSArray class]]) {
		return NO;
	}
	for (id value in values) {
		if (![IMAdminUser userWithCompatibleResponseDictionary:value]) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMAdminSessionResponseIsValid(id value) {
	if (![value isKindOfClass:[NSDictionary class]]) return NO;
	NSDictionary *session = (NSDictionary *)value;
	for (NSString *key in @[ @"id", @"deviceOS", @"deviceType", @"createdAt", @"updatedAt" ]) {
		if (![session[key] isKindOfClass:[NSString class]] || [session[key] length] == 0) return NO;
	}
	for (NSString *key in @[ @"current", @"isPendingSyncReset" ]) {
		if (!IMAdminBooleanValue(session[key])) return NO;
	}
	id appVersion = session[@"appVersion"];
	if (![appVersion isKindOfClass:[NSNull class]] && ![appVersion isKindOfClass:[NSString class]]) return NO;
	id expiresAt = session[@"expiresAt"];
	if (expiresAt != nil && ![expiresAt isKindOfClass:[NSNull class]] && ![expiresAt isKindOfClass:[NSString class]]) return NO;
	return YES;
}

static IMAdminUser *IMAdminParseUser(id json) {
	return [IMAdminUser userWithCompatibleResponseDictionary:json];
}

@implementation IMAdminApi
+ (void)usersIncludingDeleted:(BOOL)includingDeleted completion:(void (^)(NSArray<IMAdminUser *> *, NSError *))completion {
	NSDictionary *query = includingDeleted ? @{ @"withDeleted": @"true" } : nil;
	[[IMApiClient shared] GET:@"/admin/users" query:query completion:^(id json, NSError *error) {
		if (error || !IMAdminUsersResponseIsValid(json)) {
			completion(nil, error ?: IMAdminMalformedResponse());
			return;
		}
		NSArray<IMAdminUser *> *users = [IMAdminUser usersWithArray:json];
		completion(users.count == [(NSArray *)json count] ? users : nil,
		           users.count == [(NSArray *)json count] ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)createUserWithEmail:(NSString *)email name:(NSString *)name password:(NSString *)password isAdmin:(BOOL)isAdmin completion:(void (^)(IMAdminUser *, NSError *))completion {
	[self createUserWithEmail:email
	                     name:name
	                 password:password
	                  isAdmin:isAdmin
	         quotaSizeInBytes:nil
	               completion:completion];
}

+ (void)createUserWithEmail:(NSString *)email
	                     name:(NSString *)name
	                 password:(NSString *)password
	                  isAdmin:(BOOL)isAdmin
	         quotaSizeInBytes:(NSNumber *)quotaSizeInBytes
	               completion:(void (^)(IMAdminUser *, NSError *))completion {
	if (!IMAdminEmailIsValid(email) || ![name isKindOfClass:[NSString class]] || name.length == 0 ||
	    ![password isKindOfClass:[NSString class]] || password.length == 0) {
		completion(nil, IMAdminValidationError(_(@"Enter a valid email, name, and password.")));
		return;
	}
	if (quotaSizeInBytes && !IMAdminQuotaValue(quotaSizeInBytes)) {
		completion(nil, IMAdminValidationError(_(@"Quota must be a non-negative number of bytes.")));
		return;
	}
	NSMutableDictionary *body = [@{
		@"email": email ?: @"",
		@"name": name ?: @"",
		@"password": password ?: @"",
		@"isAdmin": @(isAdmin),
		@"notify": @NO,
		@"shouldChangePassword": @NO
	} mutableCopy];
	if (quotaSizeInBytes) body[@"quotaSizeInBytes"] = quotaSizeInBytes;
	[[IMApiClient shared] POST:@"/admin/users" body:body completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMAdminUser *user = IMAdminParseUser(json);
		completion(user, user ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)userWithId:(NSString *)userId completion:(void (^)(IMAdminUser *, NSError *))completion {
	if (!IMAdminUserIdIsValid(userId)) {
		completion(nil, IMAdminValidationError(_(@"A user ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@", IMAdminPathComponent(userId)];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMAdminUser *user = IMAdminParseUser(json);
		completion(user, user ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)updateUserId:(NSString *)userId isAdmin:(BOOL)isAdmin completion:(void (^)(IMAdminUser *, NSError *))completion {
	[self updateUserId:userId fields:@{ @"isAdmin": @(isAdmin) } completion:completion];
}

+ (void)updateUserId:(NSString *)userId
              fields:(NSDictionary<NSString *,id> *)fields
          completion:(void (^)(IMAdminUser *, NSError *))completion {
	if (!IMAdminUserIdIsValid(userId)) {
		completion(nil, IMAdminValidationError(_(@"A user ID is required.")));
		return;
	}
	if (!IMAdminUpdateFieldsAreValid(fields)) {
		completion(nil, IMAdminValidationError(_(@"Enter valid user update fields.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@", IMAdminPathComponent(userId)];
	[[IMApiClient shared] PUT:path body:fields completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMAdminUser *user = IMAdminParseUser(json);
		completion(user, user ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)deleteUserId:(NSString *)userId force:(BOOL)force completion:(void (^)(BOOL, NSError *))completion {
	if (!IMAdminUserIdIsValid(userId)) {
		completion(NO, IMAdminValidationError(_(@"A user ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@", IMAdminPathComponent(userId)];
	[[IMApiClient shared] DELETE:path body:@{ @"force": @(force) } completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
			return;
		}
		if (json != nil && !IMAdminParseUser(json)) {
			completion(NO, IMAdminMalformedResponse());
			return;
		}
		completion(YES, nil);
	}];
}

+ (void)restoreUserId:(NSString *)userId completion:(void (^)(IMAdminUser *, NSError *))completion {
	if (!IMAdminUserIdIsValid(userId)) {
		completion(nil, IMAdminValidationError(_(@"A user ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@/restore", IMAdminPathComponent(userId)];
	[[IMApiClient shared] POST:path body:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMAdminUser *user = IMAdminParseUser(json);
		completion(user, user ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)statisticsForUserId:(NSString *)userId
                 isFavorite:(NSNumber *)isFavorite
                  isTrashed:(NSNumber *)isTrashed
                 visibility:(NSString *)visibility
                 completion:(void (^)(IMAdminUserStatistics *, NSError *))completion {
	if (!IMAdminUserIdIsValid(userId)) {
		completion(nil, IMAdminValidationError(_(@"A user ID is required.")));
		return;
	}
	if ((isFavorite && !IMAdminBooleanValue(isFavorite)) || (isTrashed && !IMAdminBooleanValue(isTrashed))) {
		completion(nil, IMAdminValidationError(_(@"Favorite and trash filters must be boolean.")));
		return;
	}
	if (visibility && ![visibility isKindOfClass:[NSString class]]) {
		completion(nil, IMAdminValidationError(_(@"Choose a valid asset visibility.")));
		return;
	}
	NSSet<NSString *> *visibilities = [NSSet setWithArray:@[ @"archive", @"timeline", @"hidden", @"locked" ]];
	if (visibility.length > 0 && ![visibilities containsObject:visibility]) {
		completion(nil, IMAdminValidationError(_(@"Choose a valid asset visibility.")));
		return;
	}
	NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
	if (isFavorite) query[@"isFavorite"] = [isFavorite boolValue] ? @"true" : @"false";
	if (isTrashed) query[@"isTrashed"] = [isTrashed boolValue] ? @"true" : @"false";
	if (visibility.length > 0) query[@"visibility"] = visibility;
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@/statistics", IMAdminPathComponent(userId)];
	[[IMApiClient shared] GET:path query:query.count > 0 ? query : nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMAdminUserStatistics *statistics = [IMAdminUserStatistics statisticsWithDictionary:json];
		completion(statistics, statistics ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)sessionsForUserId:(NSString *)userId completion:(void (^)(NSArray<IMSessionInfo *> *, NSError *))completion {
	if (!IMAdminUserIdIsValid(userId)) {
		completion(nil, IMAdminValidationError(_(@"A user ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@/sessions", IMAdminPathComponent(userId)];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMAdminMalformedResponse());
			return;
		}
		for (id value in (NSArray *)json) {
			if (!IMAdminSessionResponseIsValid(value)) {
				completion(nil, IMAdminMalformedResponse());
				return;
			}
		}
		NSArray<IMSessionInfo *> *sessions = [IMSessionInfo sessionsWithArray:json];
		completion(sessions.count == [(NSArray *)json count] ? sessions : nil,
		           sessions.count == [(NSArray *)json count] ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)preferencesForUserId:(NSString *)userId
                   completion:(void (^)(IMAdminUserPreferences *, NSError *))completion {
	if (!IMAdminPreferencesUserIdIsValid(userId)) {
		completion(nil, IMAdminValidationError(_(@"A valid user ID is required.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@/preferences", IMAdminPathComponent(userId)];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMAdminUserPreferences *preferences = [IMAdminUserPreferences preferencesWithDictionary:json];
		completion(preferences, preferences ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)updatePreferencesForUserId:(NSString *)userId
                             values:(NSDictionary<NSString *, id> *)values
                         completion:(void (^)(IMAdminUserPreferences *, NSError *))completion {
	if (!IMAdminPreferencesUserIdIsValid(userId)) {
		completion(nil, IMAdminValidationError(_(@"A valid user ID is required.")));
		return;
	}
	NSError *validationError = nil;
	if (![IMAdminUserPreferences validateUpdateDictionary:values error:&validationError]) {
		completion(nil, validationError ?: IMAdminValidationError(_(@"Enter valid user preferences.")));
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@/preferences", IMAdminPathComponent(userId)];
	[[IMApiClient shared] PUT:path body:values completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMAdminUserPreferences *preferences = [IMAdminUserPreferences preferencesWithDictionary:json];
		completion(preferences, preferences ? nil : IMAdminMalformedResponse());
	}];
}

+ (void)calendarHeatmapForUserId:(NSString *)userId
                        fromDate:(NSString *)fromDate
                          toDate:(NSString *)toDate
                            type:(NSString *)type
                      completion:(void (^)(IMCalendarHeatmap *, NSError *))completion {
	if (!IMAdminPreferencesUserIdIsValid(userId)) {
		completion(nil, IMAdminValidationError(_(@"A valid user ID is required.")));
		return;
	}
	NSString *kind = type.length ? type : @"Upload";
	BOOL validType = [kind isEqualToString:@"Upload"] || [kind isEqualToString:@"Taken"];
	BOOL validFrom = !fromDate || IMAdminPreferencesDateOnly(fromDate);
	BOOL validTo = !toDate || IMAdminPreferencesDateOnly(toDate);
	if (!validType || !validFrom || !validTo) {
		completion(nil, IMAdminValidationError(_(@"Use valid UTC dates and choose Upload or Taken activity.")));
		return;
	}
	if (fromDate.length && toDate.length) {
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
		formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		formatter.dateFormat = @"yyyy-MM-dd";
		formatter.lenient = NO;
		NSDate *from = [formatter dateFromString:fromDate];
		NSDate *to = [formatter dateFromString:toDate];
		if (!from || !to || [from compare:to] == NSOrderedDescending) {
			completion(nil, IMAdminValidationError(_(@"The activity start date must be before the end date.")));
			return;
		}
	}
	NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"type" value:kind]];
	if (fromDate.length) [items addObject:[NSURLQueryItem queryItemWithName:@"from" value:fromDate]];
	if (toDate.length) [items addObject:[NSURLQueryItem queryItemWithName:@"to" value:toDate]];
	NSString *path = [NSString stringWithFormat:@"/admin/users/%@/calendar-heatmap", IMAdminPathComponent(userId)];
	[[IMApiClient shared] GET:path queryItems:items completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMCalendarHeatmap *heatmap = [IMCalendarHeatmap responseWithDictionary:json];
		completion(heatmap, heatmap ? nil : IMAdminMalformedResponse());
	}];
}
@end
