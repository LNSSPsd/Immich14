#import "IMNotification.h"
#import "common.h"
#include <string.h>

static id IMNotificationValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMNotificationStrictUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = [(NSString *)value lowercaseString];
	if (![raw isEqualToString:canonical]) return NO;
	return [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMNotificationStrictDate(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) return NO;
	static NSRegularExpression *expression;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:
		    @"^\\d{4}-\\d{2}-\\d{2}T(?:[01]\\d|2[0-3]):[0-5]\\d(?::[0-5]\\d(?:\\.\\d+)?)?(?:Z|[+-](?:[01]\\d|2[0-3]):[0-5]\\d)$"
		                                                         options:0
		                                                           error:NULL];
	});
	NSString *raw = (NSString *)value;
	if ([expression firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)] == nil) return NO;
	return IMDateFromServerTimestamp(raw) != nil;
}

static BOOL IMNotificationStrictLevel(id value) {
	return [value isKindOfClass:[NSString class]] &&
	       ([(NSString *)value isEqualToString:@"success"] || [(NSString *)value isEqualToString:@"error"] ||
	        [(NSString *)value isEqualToString:@"warning"] || [(NSString *)value isEqualToString:@"info"]);
}

static BOOL IMNotificationStrictType(id value) {
	return [value isKindOfClass:[NSString class]] &&
	       ([(NSString *)value isEqualToString:@"JobFailed"] || [(NSString *)value isEqualToString:@"BackupFailed"] ||
	        [(NSString *)value isEqualToString:@"SystemMessage"] || [(NSString *)value isEqualToString:@"AlbumInvite"] ||
	        [(NSString *)value isEqualToString:@"AlbumUpdate"] || [(NSString *)value isEqualToString:@"Custom"]);
}

static BOOL IMNotificationStrictJSONDictionary(id value) {
	return [value isKindOfClass:[NSDictionary class]] && [NSJSONSerialization isValidJSONObject:value];
}

@interface IMNotification ()
@property (nonatomic, copy) NSString *notificationId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *notificationDescription;
@property (nonatomic, copy) NSString *level;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *readAt;
@property (nonatomic, copy) NSDictionary<NSString *, id> *data;
@end

@implementation IMNotification

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMNotificationValueOrNil(dictionary[@"id"]);
		_notificationId = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMNotificationValueOrNil(dictionary[@"title"]);
		_title = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMNotificationValueOrNil(dictionary[@"description"]);
		_notificationDescription = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMNotificationValueOrNil(dictionary[@"level"]);
		_level = [value isKindOfClass:[NSString class]] ? value : @"info";
		value = IMNotificationValueOrNil(dictionary[@"type"]);
		_type = [value isKindOfClass:[NSString class]] ? value : @"SystemMessage";
		value = IMNotificationValueOrNil(dictionary[@"createdAt"]);
		_createdAt = [value isKindOfClass:[NSString class]] ? (IMDateFromServerTimestamp(value) ?: [NSDate date]) : [NSDate date];
		value = IMNotificationValueOrNil(dictionary[@"readAt"]);
		_readAt = [value isKindOfClass:[NSString class]] ? IMDateFromServerTimestamp(value) : nil;
		value = IMNotificationValueOrNil(dictionary[@"data"]);
		_data = [value isKindOfClass:[NSDictionary class]] ? value : @{};
	}
	return self;
}

- (BOOL)isRead {
	return self.readAt != nil;
}

+ (NSArray<IMNotification *> *)notificationsWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMNotification *> *notifications = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		if ([value isKindOfClass:[NSDictionary class]]) {
			IMNotification *notification = [[self alloc] initWithDictionary:value];
			if (notification.notificationId.length > 0) {
				[notifications addObject:notification];
			}
		}
	}
	return notifications;
}

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id identifier = IMNotificationValueOrNil(dictionary[@"id"]);
	id createdAt = IMNotificationValueOrNil(dictionary[@"createdAt"]);
	id level = IMNotificationValueOrNil(dictionary[@"level"]);
	id type = IMNotificationValueOrNil(dictionary[@"type"]);
	id title = IMNotificationValueOrNil(dictionary[@"title"]);
	if (!IMNotificationStrictUUIDv4(identifier) || !IMNotificationStrictDate(createdAt) ||
	    !IMNotificationStrictLevel(level) || !IMNotificationStrictType(type) ||
	    ![title isKindOfClass:[NSString class]]) {
		return nil;
	}
	id description = IMNotificationValueOrNil(dictionary[@"description"]);
	if (description != nil && ![description isKindOfClass:[NSString class]]) return nil;
	id data = IMNotificationValueOrNil(dictionary[@"data"]);
	if (data != nil && !IMNotificationStrictJSONDictionary(data)) return nil;
	id readAt = IMNotificationValueOrNil(dictionary[@"readAt"]);
	if (readAt != nil && !IMNotificationStrictDate(readAt)) return nil;
	IMNotification *result = [[self alloc] init];
	result->_notificationId = [identifier copy];
	result->_title = [title copy];
	result->_notificationDescription = [description isKindOfClass:[NSString class]] ? [description copy] : @"";
	result->_level = [level copy];
	result->_type = [type copy];
	result->_createdAt = IMDateFromServerTimestamp(createdAt);
	result->_readAt = [readAt isKindOfClass:[NSString class]] ? IMDateFromServerTimestamp(readAt) : nil;
	result->_data = [data isKindOfClass:[NSDictionary class]] ? [data copy] : @{};
	return result;
}

@end
