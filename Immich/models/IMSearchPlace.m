#import "IMSearchPlace.h"
#include <math.h>

static id IMPlaceValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMSearchPlace ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic) double latitude;
@property (nonatomic) double longitude;
@property (nonatomic, copy, nullable) NSString *admin1Name;
@property (nonatomic, copy, nullable) NSString *admin2Name;
@end

@implementation IMSearchPlace

+ (nullable instancetype)placeWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id name = IMPlaceValueOrNil(dictionary[@"name"]);
	id latitude = IMPlaceValueOrNil(dictionary[@"latitude"]);
	id longitude = IMPlaceValueOrNil(dictionary[@"longitude"]);
	if (![name isKindOfClass:[NSString class]] || [(NSString *)name length] == 0 ||
	    ![latitude isKindOfClass:[NSNumber class]] || ![longitude isKindOfClass:[NSNumber class]]) {
		return nil;
	}
	double lat = [latitude doubleValue];
	double lon = [longitude doubleValue];
	if (!isfinite(lat) || !isfinite(lon) || lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) {
		return nil;
	}
	id admin1 = IMPlaceValueOrNil(dictionary[@"admin1name"]);
	id admin2 = IMPlaceValueOrNil(dictionary[@"admin2name"]);
	if (admin1 && ![admin1 isKindOfClass:[NSString class]]) return nil;
	if (admin2 && ![admin2 isKindOfClass:[NSString class]]) return nil;
	IMSearchPlace *place = [[self alloc] init];
	place.name = [name copy];
	place.latitude = lat;
	place.longitude = lon;
	place.admin1Name = [admin1 isKindOfClass:[NSString class]] && [admin1 length] > 0 ? [admin1 copy] : nil;
	place.admin2Name = [admin2 isKindOfClass:[NSString class]] && [admin2 length] > 0 ? [admin2 copy] : nil;
	return place;
}

@end
