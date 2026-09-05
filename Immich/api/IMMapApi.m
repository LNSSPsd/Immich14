#import "IMMapApi.h"
#import "IMApiClient.h"
#import "common.h"
#import <math.h>

static NSError *IMMapMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid map response.")}];
}

static NSError *IMMapValidationError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:1
	                        userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The map request is invalid.")}];
}

@implementation IMMapApi

+ (void)markersWithCompletion:(void (^)(NSArray<IMMapMarker *> *_Nullable markers,
                                         NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/map/markers"
	                     query:@{ @"withPartners": @"true", @"withSharedAlbums": @"true" }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		if (error || ![json isKindOfClass:[NSArray class]]) {
			completion(nil, error ?: IMMapMalformedResponse());
			return;
		}
		NSMutableArray<IMMapMarker *> *markers = [NSMutableArray array];
		for (NSDictionary *dictionary in (NSArray *)json) {
			IMMapMarker *marker = [IMMapMarker markerWithDictionary:dictionary];
			if (!marker) {
				completion(nil, IMMapMalformedResponse());
				return;
			}
			[markers addObject:marker];
		}
		completion(markers, nil);
	}];
}

+ (void)reverseGeocodeLatitude:(double)latitude
	                    longitude:(double)longitude
	                   completion:(void (^)(NSArray<IMMapReverseGeocode *> *_Nullable results,
	                                          NSError *_Nullable error))completion {
	if (!isfinite(latitude) || !isfinite(longitude) || latitude < -90.0 || latitude > 90.0 ||
	    longitude < -180.0 || longitude > 180.0) {
		NSError *error = IMMapValidationError(_(@"Enter a latitude between -90 and 90 and a longitude between -180 and 180."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return;
	}
	NSDictionary<NSString *, NSString *> *query = @{
		@"lat": [NSString stringWithFormat:@"%.17g", latitude],
		@"lon": [NSString stringWithFormat:@"%.17g", longitude],
	};
	[[IMApiClient shared] GET:@"/map/reverse-geocode"
	                     query:query
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSArray class]]) {
			    completion(nil, error ?: IMMapMalformedResponse());
			    return;
		    }
		    NSMutableArray<IMMapReverseGeocode *> *results = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		    for (id raw in (NSArray *)json) {
			    IMMapReverseGeocode *result = [IMMapReverseGeocode resultWithDictionary:raw];
			    if (!result) {
				    completion(nil, IMMapMalformedResponse());
				    return;
			    }
			    [results addObject:result];
		    }
		    completion(results, nil);
	    }];
}

@end
