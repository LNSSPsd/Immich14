#import "IMNotificationTemplate.h"

static BOOL IMNotificationTemplateString(id value) {
	return [value isKindOfClass:[NSString class]];
}

@interface IMNotificationTemplateRequest ()
@property (nonatomic, copy) NSString *template;
@end

@interface IMNotificationTemplateResponse ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *html;
@end

@implementation IMNotificationTemplateRequest

+ (nullable instancetype)requestWithTemplate:(NSString *)template {
	if (!IMNotificationTemplateString(template)) return nil;
	IMNotificationTemplateRequest *result = [[self alloc] init];
	result.template = [template copy];
	return result;
}

+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	return [self requestWithTemplate:dictionary[@"template"]];
}

- (NSDictionary<NSString *,id> *)requestDictionary {
	return @{ @"template": self.template };
}

@end

@implementation IMNotificationTemplateResponse

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    !IMNotificationTemplateString(dictionary[@"name"]) ||
	    !IMNotificationTemplateString(dictionary[@"html"])) return nil;
	IMNotificationTemplateResponse *result = [[self alloc] init];
	result.name = [dictionary[@"name"] copy];
	result.html = [dictionary[@"html"] copy];
	return result;
}

@end
