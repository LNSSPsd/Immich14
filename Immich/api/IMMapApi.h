#import <Foundation/Foundation.h>
#import "IMMapMarker.h"
#import "IMMapReverseGeocode.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMMapApi : NSObject

+ (void)markersWithCompletion:(void (^)(NSArray<IMMapMarker *> *_Nullable markers,
                                         NSError *_Nullable error))completion;

+ (void)reverseGeocodeLatitude:(double)latitude
	                    longitude:(double)longitude
	                   completion:(void (^)(NSArray<IMMapReverseGeocode *> *_Nullable results,
                                          NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
