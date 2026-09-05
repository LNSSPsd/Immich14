#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMapReverseGeocode : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *city;
@property (nonatomic, copy, readonly, nullable) NSString *state;
@property (nonatomic, copy, readonly, nullable) NSString *country;

+ (nullable instancetype)resultWithDictionary:(NSDictionary *)dictionary;

- (NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
