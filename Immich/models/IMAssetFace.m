#import "IMAssetFace.h"

#include <math.h>
#include <string.h>

static id IMFaceValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMFaceUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
	if (!uuid) return NO;
	NSString *raw = [(NSString *)value lowercaseString];
	NSString *canonical = uuid.UUIDString.lowercaseString;
	if (![raw isEqualToString:canonical] || [canonical characterAtIndex:14] != '4') return NO;
	unichar variant = [canonical characterAtIndex:19];
	return variant == '8' || variant == '9' || variant == 'a' || variant == 'b';
}

static BOOL IMFaceInteger(id value, BOOL nonnegative) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) return NO;
	double number = [(NSNumber *)value doubleValue];
	return isfinite(number) && floor(number) == number && number >= (nonnegative ? 0.0 : -9007199254740991.0) &&
	       number <= 9007199254740991.0;
}

static BOOL IMFaceSourceType(id value) {
	return [value isKindOfClass:[NSString class]] &&
	       ([(NSString *)value isEqualToString:@"machine-learning"] ||
	        [(NSString *)value isEqualToString:@"exif"] ||
	        [(NSString *)value isEqualToString:@"manual"]);
}

@interface IMAssetFace ()
@property (nonatomic, copy) NSString *faceId;
@property (nonatomic) NSInteger imageWidth;
@property (nonatomic) NSInteger imageHeight;
@property (nonatomic) NSInteger boundingBoxX1;
@property (nonatomic) NSInteger boundingBoxX2;
@property (nonatomic) NSInteger boundingBoxY1;
@property (nonatomic) NSInteger boundingBoxY2;
@property (nonatomic, copy, nullable) NSString *sourceType;
@property (nonatomic, strong, nullable) IMPerson *person;
@end

@implementation IMAssetFace

+ (nullable instancetype)faceWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id identifier = IMFaceValueOrNil(dictionary[@"id"]);
	if (!IMFaceUUIDv4(identifier)) return nil;
	NSArray<NSString *> *nonnegativeKeys = @[ @"imageWidth", @"imageHeight" ];
	for (NSString *key in nonnegativeKeys) if (!IMFaceInteger(IMFaceValueOrNil(dictionary[key]), YES)) return nil;
	NSArray<NSString *> *coordinateKeys = @[ @"boundingBoxX1", @"boundingBoxX2", @"boundingBoxY1", @"boundingBoxY2" ];
	for (NSString *key in coordinateKeys) if (!IMFaceInteger(IMFaceValueOrNil(dictionary[key]), NO)) return nil;
	IMAssetFace *face = [[self alloc] init];
	face.faceId = [identifier copy];
	face.imageWidth = [dictionary[@"imageWidth"] integerValue];
	face.imageHeight = [dictionary[@"imageHeight"] integerValue];
	face.boundingBoxX1 = [dictionary[@"boundingBoxX1"] integerValue];
	face.boundingBoxX2 = [dictionary[@"boundingBoxX2"] integerValue];
	face.boundingBoxY1 = [dictionary[@"boundingBoxY1"] integerValue];
	face.boundingBoxY2 = [dictionary[@"boundingBoxY2"] integerValue];
	id source = dictionary[@"sourceType"];
	if (source != nil && !IMFaceSourceType(source)) return nil;
	face.sourceType = [source isKindOfClass:[NSString class]] ? [source copy] : nil;
	if (dictionary[@"person"] == nil) return nil;
	id person = IMFaceValueOrNil(dictionary[@"person"]);
	if (person && ![person isKindOfClass:[NSDictionary class]]) return nil;
	face.person = [person isKindOfClass:[NSDictionary class]] ? [IMPerson personWithDictionary:person] : nil;
	if ([person isKindOfClass:[NSDictionary class]] && !face.person) return nil;
	return face;
}

+ (NSArray<IMAssetFace *> *)facesWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray<IMAssetFace *> *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMAssetFace *face = [self faceWithResponseDictionary:value];
		if (face) [result addObject:face];
	}
	return [result copy];
}

@end
