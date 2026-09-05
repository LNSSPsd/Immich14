#import "IMAdminNotificationApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMAdminNotificationError(NSString *message, NSInteger code) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:code
	                        userInfo:@{ NSLocalizedDescriptionKey: message ?: _(@"The administrator notification request failed.") }];
}

static BOOL IMAdminNotificationTemplateNameIsValid(NSString *name) {
	if (![name isKindOfClass:[NSString class]] || name.length == 0) return NO;
	for (NSUInteger index = 0; index < name.length; index++) {
		unichar character = [name characterAtIndex:index];
		if (character == '/' || character == '\\' || [[NSCharacterSet controlCharacterSet] characterIsMember:character]) return NO;
	}
	return YES;
}

static NSString *IMAdminNotificationPathComponent(NSString *value) {
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
	    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed];
}

static void IMAdminNotificationCompleteOnMain(void (^completion)(id _Nullable value, NSError *_Nullable error),
	                                             id _Nullable value,
	                                             NSError *_Nullable error) {
	dispatch_async(dispatch_get_main_queue(), ^{ completion(value, error); });
}

@implementation IMAdminNotificationApi

+ (nullable NSURLSessionTask *)createNotification:(IMNotificationCreate *)request
	                                        completion:(void (^)(IMNotification *_Nullable, NSError *_Nullable))completion {
	if (![request isKindOfClass:[IMNotificationCreate class]]) {
		IMAdminNotificationCompleteOnMain(completion, nil, IMAdminNotificationError(_(@"A valid notification request is required."), 1));
		return nil;
	}
	return [[IMApiClient shared] POST:@"/admin/notifications"
	                              body:request.requestDictionary
	                        completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMNotification *notification = [IMNotification responseWithDictionary:json];
		completion(notification, notification ? nil : IMAdminNotificationError(_(@"The server returned an invalid notification."), 2));
	}];
}

+ (nullable NSURLSessionTask *)createNotificationForUserId:(NSString *)userId
	                                                     title:(NSString *)title
	                                              description:(NSString *)description
	                                                     level:(NSString *)level
	                                                      type:(NSString *)type
	                                                    readAt:(NSString *)readAt
	                                                      data:(NSDictionary<NSString *,id> *)data
	                                                completion:(void (^)(IMNotification *_Nullable, NSError *_Nullable))completion {
	IMNotificationCreate *request = [IMNotificationCreate requestWithUserId:userId
	                                                                      title:title
	                                                               description:description
	                                                                      level:level
	                                                                       type:type
	                                                                     readAt:readAt
	                                                                       data:data];
	if (!request) {
		IMAdminNotificationCompleteOnMain(completion, nil, IMAdminNotificationError(_(@"Enter a valid user ID and notification payload."), 1));
		return nil;
	}
	return [self createNotification:request completion:completion];
}

+ (nullable NSURLSessionTask *)renderTemplateNamed:(NSString *)name
	                                     customTemplate:(NSString *)customTemplate
	                                         completion:(void (^)(IMNotificationTemplateResponse *_Nullable, NSError *_Nullable))completion {
	IMNotificationTemplateRequest *request = [IMNotificationTemplateRequest requestWithTemplate:customTemplate ?: @""];
	if (!request) {
		IMAdminNotificationCompleteOnMain(completion, nil, IMAdminNotificationError(_(@"A template body is required."), 1));
		return nil;
	}
	return [self renderTemplateNamed:name request:request completion:completion];
}

+ (nullable NSURLSessionTask *)renderTemplateNamed:(NSString *)name
	                                           request:(IMNotificationTemplateRequest *)request
	                                         completion:(void (^)(IMNotificationTemplateResponse *_Nullable, NSError *_Nullable))completion {
	if (!IMAdminNotificationTemplateNameIsValid(name)) {
		IMAdminNotificationCompleteOnMain(completion, nil, IMAdminNotificationError(_(@"A valid email template name is required."), 1));
		return nil;
	}
	if (![request isKindOfClass:[IMNotificationTemplateRequest class]]) {
		IMAdminNotificationCompleteOnMain(completion, nil, IMAdminNotificationError(_(@"A valid template request is required."), 1));
		return nil;
	}
	NSString *encodedName = IMAdminNotificationPathComponent(name);
	if (encodedName.length == 0) {
		IMAdminNotificationCompleteOnMain(completion, nil, IMAdminNotificationError(_(@"The email template name cannot be encoded."), 1));
		return nil;
	}
	NSString *path = [NSString stringWithFormat:@"/admin/notifications/templates/%@", encodedName];
	return [[IMApiClient shared] POST:path
	                              body:request.requestDictionary
	                        completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		IMNotificationTemplateResponse *response = [IMNotificationTemplateResponse responseWithDictionary:json];
		completion(response, response ? nil : IMAdminNotificationError(_(@"The server returned an invalid template response."), 2));
	}];
}

@end
