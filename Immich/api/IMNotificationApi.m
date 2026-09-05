#import "IMNotificationApi.h"
#import "IMApiClient.h"
#import "common.h"

NSNotificationName const IMNotificationsDidChangeNotification = @"IMNotificationsDidChangeNotification";

static NSArray<IMNotification *> *sCachedNotifications;

static NSError *IMNotificationMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid notifications response.")}];
}

static NSString *IMNotificationTimestamp(BOOL read) {
	if (!read) {
		return nil;
	}
	static NSISO8601DateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSISO8601DateFormatter alloc] init];
		formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	});
	return [formatter stringFromDate:[NSDate date]];
}

static void IMPostNotificationChange(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:IMNotificationsDidChangeNotification object:nil];
	});
}

@implementation IMNotificationApi

+ (NSURLSessionTask *)notificationsWithUnreadOnly:(BOOL)unreadOnly completion:(void (^)(NSArray<IMNotification *> *, NSError *))completion {
	NSDictionary *query = unreadOnly ? @{ @"unread": @"true" } : nil;
	return [[IMApiClient shared] GET:@"/notifications" query:query completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSArray class]]) {
			completion(nil, IMNotificationMalformedResponse());
			return;
		}
		NSArray<IMNotification *> *notifications = [IMNotification notificationsWithArray:json];
		if (notifications.count != [(NSArray *)json count]) {
			completion(nil, IMNotificationMalformedResponse());
			return;
		}
		if (!unreadOnly) {
			sCachedNotifications = notifications;
		}
		completion(notifications, nil);
		IMPostNotificationChange();
	}];
}

+ (NSArray<IMNotification *> *)cachedNotifications {
	return sCachedNotifications;
}

+ (NSInteger)cachedUnreadCount {
	NSInteger count = 0;
	for (IMNotification *notification in sCachedNotifications) {
		if (!notification.isRead) {
			count += 1;
		}
	}
	return count;
}

+ (void)notificationWithId:(NSString *)notificationId
                 completion:(void (^)(IMNotification *_Nullable notification, NSError *_Nullable error))completion {
	if (![notificationId isKindOfClass:[NSString class]] || notificationId.length == 0 ||
	    [notificationId rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid notification identifier.")}]);
		return;
	}
	NSMutableCharacterSet *allowed = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
	[allowed addCharactersInString:@"-._~"];
	NSString *escaped = [notificationId stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: notificationId;
	NSString *path = [NSString stringWithFormat:@"/notifications/%@", escaped];
	[[IMApiClient shared] GET:path query:nil completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, IMNotificationMalformedResponse());
			return;
		}
		IMNotification *notification = [[IMNotification alloc] initWithDictionary:json];
		if (!notification || notification.notificationId.length == 0) {
			completion(nil, IMNotificationMalformedResponse());
			return;
		}
		completion(notification, nil);
	}];
}

+ (void)setNotificationId:(NSString *)notificationId
	                  read:(BOOL)read
	            completion:(void (^)(IMNotification *, NSError *))completion {
	if (notificationId.length == 0) {
		completion(nil, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid notification identifier.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/notifications/%@", notificationId];
	id timestamp = IMNotificationTimestamp(read);
	NSDictionary *body = timestamp ? @{ @"readAt": timestamp } : @{ @"readAt": [NSNull null] };
	[[IMApiClient shared] PUT:path body:body completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, IMNotificationMalformedResponse());
			return;
		}
		IMNotification *updated = [[IMNotification alloc] initWithDictionary:json];
		if (updated.notificationId.length == 0) {
			completion(nil, IMNotificationMalformedResponse());
			return;
		}
		if (updated && sCachedNotifications) {
			NSMutableArray<IMNotification *> *copy = [sCachedNotifications mutableCopy];
			NSUInteger index = [copy indexOfObjectPassingTest:^BOOL(IMNotification *item, NSUInteger idx, BOOL *stop) {
				return [item.notificationId isEqualToString:updated.notificationId];
			}];
			if (index != NSNotFound) {
				copy[index] = updated;
				sCachedNotifications = [copy copy];
			}
		}
		if (updated) IMPostNotificationChange();
		completion(updated, error);
	}];
}

+ (void)setAllNotificationsRead:(BOOL)read completion:(void (^)(BOOL, NSError *))completion {
	NSArray<NSString *> *ids = [sCachedNotifications valueForKey:@"notificationId"] ?: @[];
	if (ids.count == 0) {
		completion(YES, nil);
		return;
	}
	id timestamp = IMNotificationTimestamp(read);
	NSMutableDictionary *body = [@{ @"ids": ids } mutableCopy];
	body[@"readAt"] = timestamp ?: [NSNull null];
	[[IMApiClient shared] PUT:@"/notifications" body:body completion:^(id json, NSError *error) {
		if (!error && sCachedNotifications) {
			[self notificationsWithUnreadOnly:NO completion:^(NSArray<IMNotification *> *items, NSError *refreshError) {
				completion(refreshError == nil, refreshError);
			}];
			return;
		}
		completion(error == nil, error);
	}];
}

+ (void)deleteNotificationId:(NSString *)notificationId completion:(void (^)(BOOL, NSError *))completion {
	if (notificationId.length == 0) {
		completion(NO, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Invalid notification identifier.")}]);
		return;
	}
	NSString *path = [NSString stringWithFormat:@"/notifications/%@", notificationId];
	[[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) {
		if (!error && sCachedNotifications) {
			NSMutableArray<IMNotification *> *copy = [sCachedNotifications mutableCopy];
			NSIndexSet *indexes = [copy indexesOfObjectsPassingTest:^BOOL(IMNotification *item, NSUInteger idx, BOOL *stop) {
				return [item.notificationId isEqualToString:notificationId];
			}];
			if (indexes.count) {
				[copy removeObjectsAtIndexes:indexes];
				sCachedNotifications = [copy copy];
			}
			IMPostNotificationChange();
		}
		completion(error == nil, error);
	}];
}

+ (void)deleteNotificationIds:(NSArray<NSString *> *)notificationIds completion:(void (^)(BOOL, NSError *))completion {
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	for (id value in notificationIds) {
		if ([value isKindOfClass:[NSString class]] && [value length] > 0) [ids addObject:value];
	}
	if (ids.count == 0) {
		completion(YES, nil);
		return;
	}
	[[IMApiClient shared] DELETE:@"/notifications" body:@{ @"ids": ids } completion:^(id json, NSError *error) {
		if (!error && sCachedNotifications) {
			NSSet<NSString *> *idSet = [NSSet setWithArray:ids];
			NSMutableArray<IMNotification *> *copy = [NSMutableArray array];
			for (IMNotification *item in sCachedNotifications) if (![idSet containsObject:item.notificationId]) [copy addObject:item];
			sCachedNotifications = [copy copy];
			IMPostNotificationChange();
		}
		completion(error == nil, error);
	}];
}

@end
