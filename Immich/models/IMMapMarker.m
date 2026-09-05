#import "IMMapMarker.h"
#include <math.h>

static id IMMapValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMMapUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString;
	NSString *raw = [(NSString *)value lowercaseString];
	NSString *normalized = [canonical lowercaseString];
	return [raw isEqualToString:normalized] && [normalized characterAtIndex:14] == '4' &&
	       ([normalized characterAtIndex:19] == '8' || [normalized characterAtIndex:19] == '9' ||
	        [normalized characterAtIndex:19] == 'a' || [normalized characterAtIndex:19] == 'b');
}

@interface IMMapMarker ()
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic) double latitude;
@property (nonatomic) double longitude;
@property (nonatomic, copy, nullable) NSString *city;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *country;
@end

@implementation IMMapMarker

+ (nullable instancetype)markerWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id assetId = IMMapValueOrNil(dictionary[@"id"]);
	id latitude = IMMapValueOrNil(dictionary[@"lat"]);
	id longitude = IMMapValueOrNil(dictionary[@"lon"]);
	if (!IMMapUUIDv4(assetId) ||
	    ![latitude isKindOfClass:[NSNumber class]] || ![longitude isKindOfClass:[NSNumber class]] ||
	    !isfinite([(NSNumber *)latitude doubleValue]) || !isfinite([(NSNumber *)longitude doubleValue]) ||
	    [(NSNumber *)latitude doubleValue] < -90.0 || [(NSNumber *)latitude doubleValue] > 90.0 ||
	    [(NSNumber *)longitude doubleValue] < -180.0 || [(NSNumber *)longitude doubleValue] > 180.0) {
		return nil;
	}
	IMMapMarker *marker = [[IMMapMarker alloc] init];
	marker.assetId = assetId;
	marker.latitude = [latitude doubleValue];
	marker.longitude = [longitude doubleValue];
	id city = IMMapValueOrNil(dictionary[@"city"]);
	id state = IMMapValueOrNil(dictionary[@"state"]);
	id country = IMMapValueOrNil(dictionary[@"country"]);
	marker.city = [city isKindOfClass:[NSString class]] && [city length] > 0 ? city : nil;
	marker.state = [state isKindOfClass:[NSString class]] && [state length] > 0 ? state : nil;
	marker.country = [country isKindOfClass:[NSString class]] && [country length] > 0 ? country : nil;
	return marker;
}

@end
