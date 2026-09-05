#import "IMActivity.h"
#import "common.h"

static id IMActivityValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
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
	id value = IMActivityValueOrNil(dictionary[@"id"]);
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
		return nil;
	}
	id userValue = IMActivityValueOrNil(dictionary[@"user"]);
	if (![userValue isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	IMUser *user = [[IMUser alloc] initWithDictionary:userValue];
	if (user.userId.length == 0) {
		return nil;
	}
	IMActivity *activity = [[IMActivity alloc] init];
	activity.activityId = value;
	value = IMActivityValueOrNil(dictionary[@"assetId"]);
	activity.assetId = [value isKindOfClass:[NSString class]] ? value : nil;
	value = IMActivityValueOrNil(dictionary[@"type"]);
	activity.type = [value isKindOfClass:[NSString class]] ? value : @"comment";
	value = IMActivityValueOrNil(dictionary[@"comment"]);
	activity.comment = [value isKindOfClass:[NSString class]] ? value : nil;
	value = IMActivityValueOrNil(dictionary[@"createdAt"]);
	activity.createdAt = [value isKindOfClass:[NSString class]]
	    ? (IMDateFromServerTimestamp(value) ?: [NSDate date])
	    : [NSDate date];
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
