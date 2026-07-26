#import "IMAsset.h"
#import "common.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMAsset ()
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, copy) NSString *fileCreatedAt;
@property (nonatomic, getter=isFavorite) BOOL favorite;
@property (nonatomic, getter=isImage) BOOL image;
@property (nonatomic) NSInteger durationMs;
@property (nonatomic) double ratio;
@property (nonatomic, copy) NSString *city;
@property (nonatomic, copy) NSString *country;
@property (nonatomic, copy) NSString *livePhotoVideoId;
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
	NSArray *city = json[@"city"];
	NSArray *country = json[@"country"];
	NSArray *livePhotoVideoId = json[@"livePhotoVideoId"];

	NSMutableArray<IMAsset *> *assets = [NSMutableArray arrayWithCapacity:ids.count];
	for (NSUInteger i = 0; i < ids.count; i++) {
		IMAsset *asset = [[IMAsset alloc] init];
		asset.assetId = ids[i];
		asset.fileCreatedAt = (i < fileCreatedAt.count) ? fileCreatedAt[i] : @"";
		asset.favorite = (i < isFavorite.count) ? [isFavorite[i] boolValue] : NO;
		asset.image = (i < isImage.count) ? [isImage[i] boolValue] : YES;
		id durationValue = (i < duration.count) ? duration[i] : nil;
		asset.durationMs = IMDurationMsFromJSONValue(durationValue);
		asset.ratio = (i < ratio.count) ? [ratio[i] doubleValue] : 1.0;
		id cityValue = (i < city.count) ? IMValueOrNil(city[i]) : nil;
		asset.city = [cityValue isKindOfClass:[NSString class]] ? cityValue : nil;
		id countryValue = (i < country.count) ? IMValueOrNil(country[i]) : nil;
		asset.country = [countryValue isKindOfClass:[NSString class]] ? countryValue : nil;
		id liveValue = (i < livePhotoVideoId.count) ? IMValueOrNil(livePhotoVideoId[i]) : nil;
		asset.livePhotoVideoId = [liveValue isKindOfClass:[NSString class]] ? liveValue : nil;
		[assets addObject:asset];
	}
	return assets;
}

+ (nullable instancetype)assetWithResponseDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSString *assetId = IMValueOrNil(dict[@"id"]);
	if (![assetId isKindOfClass:[NSString class]] || assetId.length == 0) {
		return nil;
	}

	IMAsset *asset = [[IMAsset alloc] init];
	asset.assetId = assetId;
	id fileCreatedAt = IMValueOrNil(dict[@"fileCreatedAt"]);
	asset.fileCreatedAt = [fileCreatedAt isKindOfClass:[NSString class]] ? fileCreatedAt : @"";
	id favorite = IMValueOrNil(dict[@"isFavorite"]);
	asset.favorite = [favorite isKindOfClass:[NSNumber class]] && [favorite boolValue];
	asset.image = ![IMValueOrNil(dict[@"type"]) isEqual:@"VIDEO"];
	asset.durationMs = IMDurationMsFromJSONValue(IMValueOrNil(dict[@"duration"]));
	id widthValue = IMValueOrNil(dict[@"width"]);
	id heightValue = IMValueOrNil(dict[@"height"]);
	NSDictionary *exif = IMValueOrNil(dict[@"exifInfo"]);
	if (![widthValue isKindOfClass:[NSNumber class]] && [exif isKindOfClass:[NSDictionary class]]) {
		widthValue = IMValueOrNil(exif[@"exifImageWidth"]);
		heightValue = IMValueOrNil(exif[@"exifImageHeight"]);
	}
	double width = [widthValue isKindOfClass:[NSNumber class]] ? [widthValue doubleValue] : 0;
	double height = [heightValue isKindOfClass:[NSNumber class]] ? [heightValue doubleValue] : 0;
	asset.ratio = height > 0 ? width / height : 1.0;
	id liveValue = IMValueOrNil(dict[@"livePhotoVideoId"]);
	asset.livePhotoVideoId = [liveValue isKindOfClass:[NSString class]] ? liveValue : nil;
	return asset;
}

+ (NSArray<IMAsset *> *)assetsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMAsset *> *assets = [NSMutableArray arrayWithCapacity:array.count];
	for (NSDictionary *dict in array) {
		IMAsset *asset = [IMAsset assetWithResponseDictionary:dict];
		if (asset) {
			[assets addObject:asset];
		}
	}
	return assets;
}

+ (instancetype)assetWithId:(NSString *)assetId
              fileCreatedAt:(NSString *)fileCreatedAt
                   favorite:(BOOL)favorite
                      image:(BOOL)image
                 durationMs:(NSInteger)durationMs
                      ratio:(double)ratio
                       city:(NSString *)city
                    country:(NSString *)country
           livePhotoVideoId:(NSString *)livePhotoVideoId {
	IMAsset *asset = [[IMAsset alloc] init];
	asset.assetId = assetId;
	asset.fileCreatedAt = fileCreatedAt;
	asset.favorite = favorite;
	asset.image = image;
	asset.durationMs = durationMs;
	asset.ratio = ratio;
	asset.city = city;
	asset.country = country;
	asset.livePhotoVideoId = livePhotoVideoId;
	return asset;
}

@end
