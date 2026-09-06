#import "IMActivity.h"
#import "common.h"

static id IMActivityValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMActivityUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) {
		return NO;
	}
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
	if (!uuid) {
		return NO;
	}
	NSString *canonical = uuid.UUIDString.lowercaseString;
	return canonical.length == 36 && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMActivityUserIsValid(NSDictionary *user) {
	if (![user isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSArray<NSString *> *requiredKeys = @[
		@"avatarColor", @"email", @"id", @"name", @"profileChangedAt", @"profileImagePath"
	];
	for (NSString *key in requiredKeys) {
		if (user[key] == nil || user[key] == [NSNull null]) {
			return NO;
		}
	}
	if (!IMActivityUUIDv4(user[@"id"]) ||
	    ![user[@"name"] isKindOfClass:[NSString class]] ||
	    ![user[@"email"] isKindOfClass:[NSString class]] ||
	    ![user[@"profileImagePath"] isKindOfClass:[NSString class]] ||
	    ![user[@"profileChangedAt"] isKindOfClass:[NSString class]] ||
	    !IMDateFromServerTimestamp(user[@"profileChangedAt"]) ||
	    ![@[ @"primary", @"pink", @"red", @"yellow", @"blue", @"green", @"purple", @"orange", @"gray", @"amber" ]
	      containsObject:user[@"avatarColor"]]) {
		return NO;
	}
	return YES;
}

@interface IMActivity ()
@property (nonatomic, copy) NSString *activityId;
@property (nonatomic, copy, nullable) NSString *assetId;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy, nullable) NSString *comment;
@property (nonatomic, strong) IMUser *user;
@property (nonatomic, strong) NSDate *createdAt;
@end

@implementation IMActivity

+ (nullable instancetype)activityWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	if (dictionary[@"id"] == nil || dictionary[@"assetId"] == nil ||
	    dictionary[@"createdAt"] == nil || dictionary[@"type"] == nil ||
	    dictionary[@"user"] == nil) {
		return nil;
	}
	id value = IMActivityValueOrNil(dictionary[@"id"]);
	if (!IMActivityUUIDv4(value)) {
		return nil;
	}
	id userValue = IMActivityValueOrNil(dictionary[@"user"]);
	if (!IMActivityUserIsValid(userValue)) {
		return nil;
	}
	IMUser *user = [[IMUser alloc] initWithDictionary:userValue];
	IMActivity *activity = [[IMActivity alloc] init];
	activity.activityId = value;
	value = IMActivityValueOrNil(dictionary[@"assetId"]);
	if (value != nil && !IMActivityUUIDv4(value)) {
		return nil;
	}
	activity.assetId = [value isKindOfClass:[NSString class]] ? [value copy] : nil;
	value = IMActivityValueOrNil(dictionary[@"type"]);
	if (![value isKindOfClass:[NSString class]] ||
	    !([value isEqualToString:@"comment"] || [value isEqualToString:@"like"])) {
		return nil;
	}
	activity.type = [value copy];
	value = IMActivityValueOrNil(dictionary[@"comment"]);
	if (value != nil && ![value isKindOfClass:[NSString class]]) {
		return nil;
	}
	activity.comment = [value isKindOfClass:[NSString class]] ? [value copy] : nil;
	value = IMActivityValueOrNil(dictionary[@"createdAt"]);
	if (![value isKindOfClass:[NSString class]]) {
		return nil;
	}
	activity.createdAt = IMDateFromServerTimestamp(value);
	if (!activity.createdAt) {
		return nil;
	}
	activity.user = user;
	return activity;
}

+ (NSArray<IMActivity *> *)activitiesWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMActivity *> *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMActivity *activity = [self activityWithDictionary:value];
		if (activity) {
			[result addObject:activity];
		}
	}
	return result;
}

- (BOOL)isLike {
	return [self.type isEqualToString:@"like"];
}

- (BOOL)isComment {
	return [self.type isEqualToString:@"comment"];
}

@end
