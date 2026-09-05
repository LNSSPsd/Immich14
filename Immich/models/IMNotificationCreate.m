#import "IMNotificationCreate.h"
#import "common.h"

static id IMNotificationCreateNullable(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMNotificationCreateUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = [(NSString *)value lowercaseString];
	return [raw isEqualToString:canonical] && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMNotificationCreateDate(id value) {
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
	return [expression firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)] != nil &&
	       IMDateFromServerTimestamp(raw) != nil;
}

static BOOL IMNotificationCreateLevel(id value) {
	return [value isKindOfClass:[NSString class]] &&
	       ([(NSString *)value isEqualToString:@"success"] || [(NSString *)value isEqualToString:@"error"] ||
	        [(NSString *)value isEqualToString:@"warning"] || [(NSString *)value isEqualToString:@"info"]);
}

static BOOL IMNotificationCreateType(id value) {
	return [value isKindOfClass:[NSString class]] &&
	       ([(NSString *)value isEqualToString:@"JobFailed"] || [(NSString *)value isEqualToString:@"BackupFailed"] ||
	        [(NSString *)value isEqualToString:@"SystemMessage"] || [(NSString *)value isEqualToString:@"AlbumInvite"] ||
	        [(NSString *)value isEqualToString:@"AlbumUpdate"] || [(NSString *)value isEqualToString:@"Custom"]);
}

static BOOL IMNotificationCreateJSONDictionary(id value) {
	return [value isKindOfClass:[NSDictionary class]] && [NSJSONSerialization isValidJSONObject:value];
}

@interface IMNotificationCreate ()
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *notificationDescription;
@property (nonatomic, copy, nullable) NSString *level;
@property (nonatomic, copy, nullable) NSString *type;
@property (nonatomic, copy, nullable) NSString *readAt;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *data;
@end

@implementation IMNotificationCreate

+ (nullable instancetype)requestWithUserId:(NSString *)userId
	                                     title:(NSString *)title
	                              description:(NSString *)description
	                                     level:(NSString *)level
	                                      type:(NSString *)type
	                                    readAt:(NSString *)readAt
	                                      data:(NSDictionary<NSString *,id> *)data {
	if (!IMNotificationCreateUUIDv4(userId) || ![title isKindOfClass:[NSString class]]) return nil;
	if (description != nil && ![description isKindOfClass:[NSString class]]) return nil;
	if (level != nil && !IMNotificationCreateLevel(level)) return nil;
	if (type != nil && !IMNotificationCreateType(type)) return nil;
	if (readAt != nil && !IMNotificationCreateDate(readAt)) return nil;
	if (data != nil && !IMNotificationCreateJSONDictionary(data)) return nil;
	IMNotificationCreate *result = [[self alloc] init];
	result.userId = [userId copy];
	result.title = [title copy];
	result.notificationDescription = [description copy];
	result.level = [level copy];
	result.type = [type copy];
	result.readAt = [readAt copy];
	result.data = [data copy];
	return result;
}

+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id userId = IMNotificationCreateNullable(dictionary[@"userId"]);
	id title = IMNotificationCreateNullable(dictionary[@"title"]);
	id description = IMNotificationCreateNullable(dictionary[@"description"]);
	id level = IMNotificationCreateNullable(dictionary[@"level"]);
	id type = IMNotificationCreateNullable(dictionary[@"type"]);
	id readAt = IMNotificationCreateNullable(dictionary[@"readAt"]);
	id data = IMNotificationCreateNullable(dictionary[@"data"]);
	if (dictionary[@"description"] != nil && ![dictionary[@"description"] isKindOfClass:[NSNull class]] &&
	    ![description isKindOfClass:[NSString class]]) return nil;
	if (dictionary[@"readAt"] != nil && ![dictionary[@"readAt"] isKindOfClass:[NSNull class]] &&
	    ![readAt isKindOfClass:[NSString class]]) return nil;
	if (dictionary[@"level"] != nil && ![level isKindOfClass:[NSString class]]) return nil;
	if (dictionary[@"type"] != nil && ![type isKindOfClass:[NSString class]]) return nil;
	if (dictionary[@"data"] != nil && ![data isKindOfClass:[NSDictionary class]]) return nil;
	return [self requestWithUserId:userId title:title description:description level:level type:type readAt:readAt data:data];
}

- (NSDictionary<NSString *,id> *)requestDictionary {
	NSMutableDictionary<NSString *, id> *body = [@{ @"userId": self.userId, @"title": self.title } mutableCopy];
	if (self.notificationDescription != nil) body[@"description"] = self.notificationDescription;
	if (self.level != nil) body[@"level"] = self.level;
	if (self.type != nil) body[@"type"] = self.type;
	if (self.readAt != nil) body[@"readAt"] = self.readAt;
	if (self.data != nil) body[@"data"] = self.data;
	return [body copy];
}

@end
