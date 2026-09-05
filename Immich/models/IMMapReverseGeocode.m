#import "IMMapReverseGeocode.h"

static BOOL IMMapReverseGeocodeNullableString(NSDictionary *dictionary, NSString *key, NSString **outValue) {
	if (!dictionary || ![dictionary.allKeys containsObject:key]) {
		return NO;
	}
	id raw = dictionary[key];
	if ([raw isKindOfClass:[NSNull class]]) {
		if (outValue) *outValue = nil;
		return YES;
	}
	if (![raw isKindOfClass:[NSString class]]) {
		return NO;
	}
	NSString *value = [(NSString *)raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (outValue) *outValue = value.length > 0 ? value : nil;
	return YES;
}

@interface IMMapReverseGeocode ()
@property (nonatomic, copy, nullable) NSString *city;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *country;
@end

@implementation IMMapReverseGeocode

+ (nullable instancetype)resultWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSString *city = nil, *state = nil, *country = nil;
	if (!IMMapReverseGeocodeNullableString(dictionary, @"city", &city) ||
	    !IMMapReverseGeocodeNullableString(dictionary, @"state", &state) ||
	    !IMMapReverseGeocodeNullableString(dictionary, @"country", &country)) {
		return nil;
	}
	IMMapReverseGeocode *result = [[self alloc] init];
	result.city = city;
	result.state = state;
	result.country = country;
	return result;
}

- (NSString *)displayName {
	NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:3];
	if (self.city.length > 0) [parts addObject:self.city];
	if (self.state.length > 0 && ![self.state isEqualToString:self.city]) [parts addObject:self.state];
	if (self.country.length > 0 && ![parts containsObject:self.country]) [parts addObject:self.country];
	return [parts componentsJoinedByString:@", "];
}

@end
