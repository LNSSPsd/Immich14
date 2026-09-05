#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMapMarker : NSObject

@property (nonatomic, copy, readonly) NSString *assetId;
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;
@property (nonatomic, copy, readonly, nullable) NSString *city;
@property (nonatomic, copy, readonly, nullable) NSString *state;
@property (nonatomic, copy, readonly, nullable) NSString *country;

+ (nullable instancetype)markerWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
