#import "IMMaintenanceAuth.h"

@interface IMMaintenanceLoginRequest ()
@property (nonatomic, copy, nullable) NSString *token;
@end

@interface IMMaintenanceAuth ()
@property (nonatomic, copy) NSString *username;
@end

@implementation IMMaintenanceLoginRequest

+ (nullable instancetype)requestWithToken:(NSString *)token {
	if (token != nil && ![token isKindOfClass:[NSString class]]) return nil;
	IMMaintenanceLoginRequest *result = [[self alloc] init];
	if (token != nil) result.token = [token copy];
	return result;
}

+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id value = dictionary[@"token"];
	if (value != nil && ![value isKindOfClass:[NSString class]]) return nil;
	return [self requestWithToken:[value isKindOfClass:[NSString class]] ? value : nil];
}

- (NSDictionary<NSString *,id> *)requestDictionary {
	return self.token != nil ? @{ @"token": self.token } : @{};
}

@end

@implementation IMMaintenanceAuth

+ (nullable instancetype)authWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id username = dictionary[@"username"];
	if (![username isKindOfClass:[NSString class]] || [(NSString *)username length] == 0) return nil;
	IMMaintenanceAuth *result = [[self alloc] init];
	result.username = [username copy];
	return result;
}

@end
