#import "IMAssetDetail.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMAssetDetail ()
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, getter=isVideo) BOOL video;
@property (nonatomic, copy) NSString *originalFileName;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic, copy, nullable) NSString *fileCreatedAt;
@property (nonatomic, copy, nullable) NSString *cameraMake;
@property (nonatomic, copy, nullable) NSString *cameraModel;
@property (nonatomic, copy, nullable) NSString *lensModel;
@property (nonatomic, copy, nullable) NSNumber *fNumber;
@property (nonatomic, copy, nullable) NSString *exposureTime;
@property (nonatomic, copy, nullable) NSNumber *iso;
@property (nonatomic, copy, nullable) NSNumber *focalLength;
@property (nonatomic, copy, nullable) NSString *city;
@property (nonatomic, copy, nullable) NSString *state;
@property (nonatomic, copy, nullable) NSString *country;
@property (nonatomic, copy, nullable) NSString *exifDescription;
@property (nonatomic, copy) NSArray<NSString *> *peopleNames;
@property (nonatomic, copy) NSArray<NSString *> *tagNames;
@end

@implementation IMAssetDetail

- (instancetype)initWithDictionary:(NSDictionary *)dict {
	self = [super init];
	if (self) {
		_assetId = IMValueOrNil(dict[@"id"]);
		_video = [IMValueOrNil(dict[@"type"]) isEqual:@"VIDEO"];
		_originalFileName = IMValueOrNil(dict[@"originalFileName"]) ?: @"";
		_width = [IMValueOrNil(dict[@"width"]) integerValue];
		_height = [IMValueOrNil(dict[@"height"]) integerValue];
		_fileCreatedAt = IMValueOrNil(dict[@"fileCreatedAt"]);

		id exifValue = IMValueOrNil(dict[@"exifInfo"]);
		NSDictionary *exif = [exifValue isKindOfClass:[NSDictionary class]] ? exifValue : nil;
		_cameraMake = IMValueOrNil(exif[@"make"]);
		_cameraModel = IMValueOrNil(exif[@"model"]);
		_lensModel = IMValueOrNil(exif[@"lensModel"]);
		_fNumber = IMValueOrNil(exif[@"fNumber"]);
		_exposureTime = IMValueOrNil(exif[@"exposureTime"]);
		_iso = IMValueOrNil(exif[@"iso"]);
		_focalLength = IMValueOrNil(exif[@"focalLength"]);
		_city = IMValueOrNil(exif[@"city"]);
		_state = IMValueOrNil(exif[@"state"]);
		_country = IMValueOrNil(exif[@"country"]);
		_exifDescription = IMValueOrNil(exif[@"description"]);

		NSMutableArray<NSString *> *people = [NSMutableArray array];
		id peopleValue = IMValueOrNil(dict[@"people"]);
		if ([peopleValue isKindOfClass:[NSArray class]]) {
			for (NSDictionary *person in (NSArray *)peopleValue) {
				NSString *name = [person isKindOfClass:[NSDictionary class]] ? IMValueOrNil(person[@"name"]) : nil;
				if (name.length > 0) {
					[people addObject:name];
				}
			}
		}
		_peopleNames = people;

		NSMutableArray<NSString *> *tags = [NSMutableArray array];
		id tagsValue = IMValueOrNil(dict[@"tags"]);
		if ([tagsValue isKindOfClass:[NSArray class]]) {
			for (NSDictionary *tag in (NSArray *)tagsValue) {
				NSString *name = [tag isKindOfClass:[NSDictionary class]] ? IMValueOrNil(tag[@"name"]) : nil;
				if (name.length > 0) {
					[tags addObject:name];
				}
			}
		}
		_tagNames = tags;
	}
	return self;
}

@end
