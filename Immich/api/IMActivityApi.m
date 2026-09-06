#import "IMActivityApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMActivityError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The server returned an invalid activity response.") }];
}

static NSError *IMActivityValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The activity request is invalid.") }];
}

static BOOL IMActivityUUIDv4(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length != 36) {
		return NO;
	}
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) {
		return NO;
	}
	NSString *canonical = uuid.UUIDString.lowercaseString;
	return canonical.length == 36 && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMActivityOptionalUUIDv4(id value) {
	if (value == nil) {
		return YES;
	}
	if (![value isKindOfClass:[NSString class]]) {
		return NO;
	}
	return [(NSString *)value length] == 0 || IMActivityUUIDv4(value);
}

@implementation IMActivityApi

+ (nullable NSURLSessionTask *)activitiesForAlbumId:(NSString *)albumId
                                             assetId:(NSString *)assetId
                                                type:(NSString *)type
                                               level:(NSString *)level
	                                         userId:(NSString *)userId
                                          completion:(void (^)(NSArray<IMActivity *> *_Nullable, NSError *_Nullable))completion {
	if (!IMActivityUUIDv4(albumId)) {
		completion(nil, IMActivityValidationError(_(@"A valid album ID is required to load activity.")));
		return nil;
	}
	if (assetId && !IMActivityOptionalUUIDv4(assetId)) {
		completion(nil, IMActivityValidationError(_(@"A valid asset ID is required to filter activity.")));
		return nil;
	}
	if (type && (![type isKindOfClass:[NSString class]] ||
	             (type.length && !([type isEqualToString:@"like"] || [type isEqualToString:@"comment"])))) {
		completion(nil, IMActivityValidationError(_(@"Choose a valid activity type.")));
		return nil;
	}
	if (level && (![level isKindOfClass:[NSString class]] ||
	              (level.length && !([level isEqualToString:@"album"] || [level isEqualToString:@"asset"])))) {
		completion(nil, IMActivityValidationError(_(@"Choose a valid activity level.")));
		return nil;
	}
	if (userId && !IMActivityOptionalUUIDv4(userId)) {
		completion(nil, IMActivityValidationError(_(@"A valid user ID is required to filter activity.")));
		return nil;
	}
	NSMutableDictionary<NSString *, NSString *> *query = [@{ @"albumId": albumId } mutableCopy];
	if (assetId.length) query[@"assetId"] = assetId;
	if (type.length) query[@"type"] = type;
	if (level.length) query[@"level"] = level;
	if (userId.length) query[@"userId"] = userId;
	return [[IMApiClient shared] GET:@"/activities"
	                            query:query
	                       completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMActivityError(nil));
			return;
		}
		NSArray<IMActivity *> *activities = [IMActivity activitiesWithArray:json];
		if (activities.count != [(NSArray *)json count]) {
			completion(nil, IMActivityError(nil));
			return;
		}
		completion(activities, nil);
	}];
}

+ (nullable NSURLSessionTask *)statisticsForAlbumId:(NSString *)albumId
                                             assetId:(NSString *)assetId
                                          completion:(void (^)(NSInteger, NSInteger, NSError *_Nullable))completion {
	if (!IMActivityUUIDv4(albumId)) {
		completion(0, 0, IMActivityValidationError(_(@"A valid album ID is required to load activity.")));
		return nil;
	}
	if (assetId && !IMActivityOptionalUUIDv4(assetId)) {
		completion(0, 0, IMActivityValidationError(_(@"A valid asset ID is required to load activity.")));
		return nil;
	}
	NSMutableDictionary<NSString *, NSString *> *query = [@{ @"albumId": albumId } mutableCopy];
	if (assetId.length) query[@"assetId"] = assetId;
	return [[IMApiClient shared] GET:@"/activities/statistics"
	                            query:query
	                       completion:^(id json, NSError *error) {
		if (error) {
			completion(0, 0, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]] ||
		    ![json[@"comments"] isKindOfClass:[NSNumber class]] ||
		    ![json[@"likes"] isKindOfClass:[NSNumber class]]) {
			completion(0, 0, IMActivityError(_(@"The server returned invalid activity statistics.")));
			return;
		}
		completion([json[@"comments"] integerValue], [json[@"likes"] integerValue], nil);
	}];
}

+ (nullable NSURLSessionTask *)createForAlbumId:(NSString *)albumId
                                         assetId:(NSString *)assetId
                                         type:(NSString *)type
                                         comment:(NSString *)comment
                                      completion:(void (^)(IMActivity *_Nullable, NSError *_Nullable))completion {
	if (!IMActivityUUIDv4(albumId) || ![type isKindOfClass:[NSString class]] ||
	    !([type isEqualToString:@"like"] || [type isEqualToString:@"comment"])) {
		completion(nil, IMActivityValidationError(_(@"Choose a valid activity type and album.")));
		return nil;
	}
	if (assetId && !IMActivityOptionalUUIDv4(assetId)) {
		completion(nil, IMActivityValidationError(_(@"A valid asset ID is required.")));
		return nil;
	}
	if (comment && ![comment isKindOfClass:[NSString class]]) {
		completion(nil, IMActivityValidationError(_(@"The comment must be text.")));
		return nil;
	}
	if ([type isEqualToString:@"comment"] && comment.length == 0) {
		completion(nil, IMActivityError(_(@"A comment cannot be empty.")));
		return nil;
	}
	NSMutableDictionary *body = [@{ @"albumId": albumId, @"type": type } mutableCopy];
	if (assetId.length) body[@"assetId"] = assetId;
	if (comment.length) body[@"comment"] = comment;
	return [[IMApiClient shared] POST:@"/activities"
	                             body:body
	                       completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMActivity *activity = [IMActivity activityWithDictionary:json];
		completion(activity, activity ? nil : IMActivityError(nil));
	}];
}

+ (nullable NSURLSessionTask *)deleteActivityId:(NSString *)activityId
                                      completion:(void (^)(BOOL, NSError *_Nullable))completion {
	if (!IMActivityUUIDv4(activityId)) {
		completion(NO, IMActivityValidationError(_(@"Invalid activity identifier.")));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/activities/%@", activityId];
	return [[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

@end
