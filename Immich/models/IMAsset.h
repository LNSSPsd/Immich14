#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAsset : NSObject

@property (nonatomic, copy, readonly) NSString *assetId;
@property (nonatomic, copy, readonly) NSString *fileCreatedAt; 
@property (nonatomic, readonly, getter=isFavorite) BOOL favorite;
@property (nonatomic, readonly, getter=isImage) BOOL image; 
@property (nonatomic, readonly) NSInteger durationMs; 
@property (nonatomic, readonly) double ratio; 
@property (nonatomic, copy, readonly, nullable) NSString *city; 
@property (nonatomic, copy, readonly, nullable) NSString *country;

+ (NSArray<IMAsset *> *)assetsFromTimeBucketJSON:(NSDictionary *)json;

+ (nullable instancetype)assetWithResponseDictionary:(NSDictionary *)dict;
+ (NSArray<IMAsset *> *)assetsWithResponseArray:(NSArray *)array;

+ (instancetype)assetWithId:(NSString *)assetId
              fileCreatedAt:(NSString *)fileCreatedAt
                   favorite:(BOOL)favorite
                      image:(BOOL)image
                 durationMs:(NSInteger)durationMs
                      ratio:(double)ratio
                       city:(nullable NSString *)city
                    country:(nullable NSString *)country;

@end

NS_ASSUME_NONNULL_END
