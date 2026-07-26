#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbum : NSObject

@property (nonatomic, copy, readonly) NSString *albumId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) NSInteger assetCount;
@property (nonatomic, copy, readonly, nullable) NSString *thumbnailAssetId;
@property (nonatomic, copy, readonly, nullable) NSString *order;

+ (nullable instancetype)albumWithDictionary:(NSDictionary *)dict;
+ (NSArray<IMAlbum *> *)albumsWithArray:(NSArray *)array;

- (instancetype)albumByAdjustingAssetCount:(NSInteger)delta;

@end

NS_ASSUME_NONNULL_END
