#import "IMAsset.h"
#import "common.h"
#import <math.h>

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static NSArray *IMArrayOrEmpty(id value) {
	return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static id IMArrayValue(NSArray *array, NSUInteger index) {
	return index < array.count ? array[index] : nil;
}

@interface IMAsset ()
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, copy, nullable) NSString *ownerId;
@property (nonatomic, copy) NSString *fileCreatedAt;
@property (nonatomic, getter=isFavorite) BOOL favorite;
@property (nonatomic, getter=isImage) BOOL image;
@property (nonatomic) NSInteger durationMs;
@property (nonatomic) double ratio;
@property (nonatomic, copy) NSString *city;
@property (nonatomic, copy) NSString *country;
@property (nonatomic, copy, nullable) NSString *projectionType;
@property (nonatomic, copy) NSString *livePhotoVideoId;
@property (nonatomic, copy) NSString *stackId;
@property (nonatomic) NSInteger stackAssetCount;
@end

@implementation IMAsset

+ (NSArray<IMAsset *> *)assetsFromTimeBucketJSON:(NSDictionary *)json {
	if (![json isKindOfClass:[NSDictionary class]]) {
		return @[];
	}
	NSArray<NSString *> *ids = json[@"id"];
	if (![ids isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSArray *fileCreatedAt = IMArrayOrEmpty(json[@"fileCreatedAt"]);
	NSArray *ownerIds = IMArrayOrEmpty(json[@"ownerId"]);
	NSArray *isFavorite = IMArrayOrEmpty(json[@"isFavorite"]);
	NSArray *isImage = IMArrayOrEmpty(json[@"isImage"]);
	NSArray *duration = IMArrayOrEmpty(json[@"duration"]);
	NSArray *ratio = IMArrayOrEmpty(json[@"ratio"]);
	NSArray *city = IMArrayOrEmpty(json[@"city"]);
	NSArray *country = IMArrayOrEmpty(json[@"country"]);
	NSArray *projectionType = IMArrayOrEmpty(json[@"projectionType"]);
	NSArray *livePhotoVideoId = IMArrayOrEmpty(json[@"livePhotoVideoId"]);
	id stackValue = json[@"stack"];
	NSArray *stack = IMArrayOrEmpty(stackValue);

	NSMutableArray<IMAsset *> *assets = [NSMutableArray arrayWithCapacity:ids.count];
	for (NSUInteger i = 0; i < ids.count; i++) {
		IMAsset *asset = [[IMAsset alloc] init];
		id assetIdValue = IMArrayValue(ids, i);
		if (![assetIdValue isKindOfClass:[NSString class]] || [assetIdValue length] == 0) {
			continue;
		}
		asset.assetId = assetIdValue;
		id ownerIdValue = IMValueOrNil(IMArrayValue(ownerIds, i));
		asset.ownerId = [ownerIdValue isKindOfClass:[NSString class]] && [ownerIdValue length] > 0 ? ownerIdValue : nil;
		id createdValue = IMArrayValue(fileCreatedAt, i);
		asset.fileCreatedAt = [createdValue isKindOfClass:[NSString class]] ? createdValue : @"";
		id favoriteValue = IMValueOrNil(IMArrayValue(isFavorite, i));
		asset.favorite = [favoriteValue isKindOfClass:[NSNumber class]] && [favoriteValue boolValue];
		id imageValue = IMValueOrNil(IMArrayValue(isImage, i));
		asset.image = imageValue == nil ? YES : ([imageValue isKindOfClass:[NSNumber class]] && [imageValue boolValue]);
		id durationValue = IMArrayValue(duration, i);
		asset.durationMs = IMDurationMsFromJSONValue(durationValue);
		id ratioValue = IMArrayValue(ratio, i);
		double ratioNumber = [ratioValue isKindOfClass:[NSNumber class]] ? [ratioValue doubleValue] : 1.0;
		asset.ratio = isfinite(ratioNumber) && ratioNumber > 0 ? ratioNumber : 1.0;
		id cityValue = IMValueOrNil(IMArrayValue(city, i));
		asset.city = [cityValue isKindOfClass:[NSString class]] ? cityValue : nil;
		id countryValue = IMValueOrNil(IMArrayValue(country, i));
		asset.country = [countryValue isKindOfClass:[NSString class]] ? countryValue : nil;
		id projectionValue = IMValueOrNil(IMArrayValue(projectionType, i));
		asset.projectionType = [projectionValue isKindOfClass:[NSString class]] ? projectionValue : nil;
		id liveValue = IMValueOrNil(IMArrayValue(livePhotoVideoId, i));
		asset.livePhotoVideoId = [liveValue isKindOfClass:[NSString class]] ? liveValue : nil;
		id rowStackValue = IMValueOrNil(IMArrayValue(stack, i));
		if ([rowStackValue isKindOfClass:[NSArray class]] && [(NSArray *)rowStackValue count] == 2) {
			id sid = IMValueOrNil(rowStackValue[0]);
			id count = IMValueOrNil(rowStackValue[1]);
			if (![sid isKindOfClass:[NSString class]] || [(NSString *)sid length] == 0) {
				continue;
			}
			asset.stackId = sid;
			if ([count isKindOfClass:[NSNumber class]]) {
				double number = [count doubleValue];
				if (isfinite(number) && number >= 0 && floor(number) == number) {
					asset.stackAssetCount = [count integerValue];
				}
			} else if ([count isKindOfClass:[NSString class]]) {
				NSScanner *scanner = [NSScanner scannerWithString:count];
				NSInteger integerCount = 0;
				if ([scanner scanInteger:&integerCount] && scanner.isAtEnd && integerCount >= 0) {
					asset.stackAssetCount = integerCount;
				}
			}
		}
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
	id ownerId = IMValueOrNil(dict[@"ownerId"]);
	asset.ownerId = [ownerId isKindOfClass:[NSString class]] && [(NSString *)ownerId length] > 0 ? ownerId : nil;
	id fileCreatedAt = IMValueOrNil(dict[@"fileCreatedAt"]);
	asset.fileCreatedAt = [fileCreatedAt isKindOfClass:[NSString class]] ? fileCreatedAt : @"";
	id favorite = IMValueOrNil(dict[@"isFavorite"]);
	asset.favorite = [favorite isKindOfClass:[NSNumber class]] && [favorite boolValue];
	asset.image = ![IMValueOrNil(dict[@"type"]) isEqual:@"VIDEO"];
	asset.durationMs = IMDurationMsFromJSONValue(IMValueOrNil(dict[@"duration"]));
	id widthValue = IMValueOrNil(dict[@"width"]);
	id heightValue = IMValueOrNil(dict[@"height"]);
	NSDictionary *exif = IMValueOrNil(dict[@"exifInfo"]);
	id projectionValue = IMValueOrNil(dict[@"projectionType"]);
	if (![projectionValue isKindOfClass:[NSString class]] && [exif isKindOfClass:[NSDictionary class]]) {
		projectionValue = IMValueOrNil(exif[@"projectionType"]);
	}
	asset.projectionType = [projectionValue isKindOfClass:[NSString class]] ? projectionValue : nil;
	if (![widthValue isKindOfClass:[NSNumber class]] && [exif isKindOfClass:[NSDictionary class]]) {
		widthValue = IMValueOrNil(exif[@"exifImageWidth"]);
		heightValue = IMValueOrNil(exif[@"exifImageHeight"]);
	}
	double width = [widthValue isKindOfClass:[NSNumber class]] ? [widthValue doubleValue] : 0;
	double height = [heightValue isKindOfClass:[NSNumber class]] ? [heightValue doubleValue] : 0;
	asset.ratio = height > 0 ? width / height : 1.0;
	id liveValue = IMValueOrNil(dict[@"livePhotoVideoId"]);
	asset.livePhotoVideoId = [liveValue isKindOfClass:[NSString class]] ? liveValue : nil;
	NSDictionary *stack = IMValueOrNil(dict[@"stack"]);
	if ([stack isKindOfClass:[NSDictionary class]]) {
		id sid = IMValueOrNil(stack[@"id"]);
		id count = IMValueOrNil(stack[@"assetCount"]);
		asset.stackId = [sid isKindOfClass:[NSString class]] ? sid : nil;
		if ([count isKindOfClass:[NSNumber class]]) {
			asset.stackAssetCount = [count integerValue];
		} else if ([count isKindOfClass:[NSString class]]) {
			asset.stackAssetCount = [count integerValue];
		}
	}
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
