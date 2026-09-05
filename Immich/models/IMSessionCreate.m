#import "IMSessionCreate.h"
#include <math.h>
#include <string.h>

static BOOL IMSessionCreateBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMSessionCreateDuration(id value) {
	if (![value isKindOfClass:[NSNumber class]] || IMSessionCreateBoolean(value)) return NO;
	double number = [(NSNumber *)value doubleValue];
	return isfinite(number) && floor(number) == number && number >= 1.0 && number <= 9007199254740991.0;
}

static BOOL IMSessionCreateOptionalString(id value) {
	if (value == nil) return YES;
	if (![value isKindOfClass:[NSString class]]) return NO;
	return [(NSString *)value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

@interface IMSessionCreateRequest ()
@property (nonatomic, copy, nullable) NSString *deviceOS;
@property (nonatomic, copy, nullable) NSString *deviceType;
@property (nonatomic, strong, nullable) NSNumber *duration;
@end

@implementation IMSessionCreateRequest

+ (nullable instancetype)requestWithDeviceOS:(NSString *)deviceOS
                                   deviceType:(NSString *)deviceType
                                    duration:(NSNumber *)duration {
	if (!IMSessionCreateOptionalString(deviceOS) || !IMSessionCreateOptionalString(deviceType) ||
	    (duration != nil && !IMSessionCreateDuration(duration))) return nil;
	IMSessionCreateRequest *result = [[self alloc] init];
	result.deviceOS = [deviceOS copy];
	result.deviceType = [deviceType copy];
	result.duration = [duration copy];
	return result;
}

+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id deviceOS = dictionary[@"deviceOS"];
	id deviceType = dictionary[@"deviceType"];
	id duration = dictionary[@"duration"];
	if ((deviceOS != nil && ![deviceOS isKindOfClass:[NSString class]]) ||
	    (deviceType != nil && ![deviceType isKindOfClass:[NSString class]]) ||
	    (duration != nil && !IMSessionCreateDuration(duration))) return nil;
	return [self requestWithDeviceOS:deviceOS deviceType:deviceType duration:duration];
}

- (NSDictionary<NSString *,id> *)requestDictionary {
	NSMutableDictionary<NSString *, id> *body = [NSMutableDictionary dictionary];
	if (self.deviceOS != nil) body[@"deviceOS"] = self.deviceOS;
	if (self.deviceType != nil) body[@"deviceType"] = self.deviceType;
	if (self.duration != nil) body[@"duration"] = self.duration;
	return [body copy];
}

@end
