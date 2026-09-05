#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSearchPlace : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) double latitude;
@property (nonatomic, readonly) double longitude;
@property (nonatomic, copy, readonly, nullable) NSString *admin1Name;
@property (nonatomic, copy, readonly, nullable) NSString *admin2Name;

+ (nullable instancetype)placeWithResponseDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
