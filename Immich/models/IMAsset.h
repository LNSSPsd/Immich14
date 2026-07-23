#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAsset : NSObject

@property (nonatomic, copy, readonly) NSString *assetId;
@property (nonatomic, copy, readonly) NSString *fileCreatedAt; 
@property (nonatomic, readonly, getter=isFavorite) BOOL favorite;
@property (nonatomic, readonly, getter=isImage) BOOL image; 
@property (nonatomic, readonly) NSInteger durationMs; 
@property (nonatomic, readonly) double ratio; 

+ (NSArray<IMAsset *> *)assetsFromTimeBucketJSON:(NSDictionary *)json;

+ (instancetype)assetWithId:(NSString *)assetId
              fileCreatedAt:(NSString *)fileCreatedAt
                   favorite:(BOOL)favorite
                      image:(BOOL)image
                 durationMs:(NSInteger)durationMs
                      ratio:(double)ratio;

@end

NS_ASSUME_NONNULL_END
