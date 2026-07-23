#import "IMAsset.h"

@interface IMAsset ()
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, copy) NSString *fileCreatedAt;
@property (nonatomic, getter=isFavorite) BOOL favorite;
@property (nonatomic, getter=isImage) BOOL image;
@property (nonatomic) NSInteger durationMs;
@property (nonatomic) double ratio;
@end

@implementation IMAsset

+ (NSArray<IMAsset *> *)assetsFromTimeBucketJSON:(NSDictionary *)json {
	NSArray<NSString *> *ids = json[@"id"];
	if (![ids isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSArray *fileCreatedAt = json[@"fileCreatedAt"];
	NSArray *isFavorite = json[@"isFavorite"];
	NSArray *isImage = json[@"isImage"];
	NSArray *duration = json[@"duration"];
	NSArray *ratio = json[@"ratio"];

	NSMutableArray<IMAsset *> *assets = [NSMutableArray arrayWithCapacity:ids.count];
	for (NSUInteger i = 0; i < ids.count; i++) {
		IMAsset *asset = [[IMAsset alloc] init];
		asset.assetId = ids[i];
		asset.fileCreatedAt = (i < fileCreatedAt.count) ? fileCreatedAt[i] : @"";
		asset.favorite = (i < isFavorite.count) ? [isFavorite[i] boolValue] : NO;
		asset.image = (i < isImage.count) ? [isImage[i] boolValue] : YES;
		id durationValue = (i < duration.count) ? duration[i] : nil;
		asset.durationMs = [durationValue isKindOfClass:[NSNumber class]] ? [durationValue integerValue] : 0;
		asset.ratio = (i < ratio.count) ? [ratio[i] doubleValue] : 1.0;
		[assets addObject:asset];
	}
	return assets;
}

+ (instancetype)assetWithId:(NSString *)assetId
              fileCreatedAt:(NSString *)fileCreatedAt
                   favorite:(BOOL)favorite
                      image:(BOOL)image
                 durationMs:(NSInteger)durationMs
                      ratio:(double)ratio {
	IMAsset *asset = [[IMAsset alloc] init];
	asset.assetId = assetId;
	asset.fileCreatedAt = fileCreatedAt;
	asset.favorite = favorite;
	asset.image = image;
	asset.durationMs = durationMs;
	asset.ratio = ratio;
	return asset;
}

@end
