#import "IMAssetFaceCreate.h"

#include <math.h>
#include <string.h>

static const double IMAssetFaceCreateMaxSafeInteger = 9007199254740991.0;

static BOOL IMAssetFaceCreateIntegerValueIsSafe(NSInteger value) {
	return value >= (NSInteger)-9007199254740991LL && value <= (NSInteger)9007199254740991LL;
}

static BOOL IMAssetFaceCreateUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = [(NSString *)value lowercaseString];
	if (![raw isEqualToString:canonical]) return NO;
	if ([canonical characterAtIndex:14] != '4') return NO;
	unichar variant = [canonical characterAtIndex:19];
	return variant == '8' || variant == '9' || variant == 'a' || variant == 'b';
}

static BOOL IMAssetFaceCreateInteger(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) return NO;
	double number = [(NSNumber *)value doubleValue];
	return isfinite(number) && floor(number) == number && number >= -IMAssetFaceCreateMaxSafeInteger &&
	       number <= IMAssetFaceCreateMaxSafeInteger;
}

@interface IMAssetFaceCreate ()
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, copy) NSString *personId;
@property (nonatomic) NSInteger imageWidth;
@property (nonatomic) NSInteger imageHeight;
@property (nonatomic) NSInteger x;
@property (nonatomic) NSInteger y;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@end

@implementation IMAssetFaceCreate

+ (nullable instancetype)requestWithAssetId:(NSString *)assetId
                                    personId:(NSString *)personId
                                 imageWidth:(NSInteger)imageWidth
                                imageHeight:(NSInteger)imageHeight
                                          x:(NSInteger)x
                                          y:(NSInteger)y
                                       width:(NSInteger)width
                                      height:(NSInteger)height {
	if (!IMAssetFaceCreateUUIDv4(assetId) || !IMAssetFaceCreateUUIDv4(personId)) return nil;
	if (!IMAssetFaceCreateIntegerValueIsSafe(imageWidth) || !IMAssetFaceCreateIntegerValueIsSafe(imageHeight) ||
	    !IMAssetFaceCreateIntegerValueIsSafe(x) || !IMAssetFaceCreateIntegerValueIsSafe(y) ||
	    !IMAssetFaceCreateIntegerValueIsSafe(width) || !IMAssetFaceCreateIntegerValueIsSafe(height)) return nil;
	IMAssetFaceCreate *result = [[self alloc] init];
	result.assetId = [assetId copy];
	result.personId = [personId copy];
	result.imageWidth = imageWidth;
	result.imageHeight = imageHeight;
	result.x = x;
	result.y = y;
	result.width = width;
	result.height = height;
	return result;
}

+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id assetId = dictionary[@"assetId"];
	id personId = dictionary[@"personId"];
	NSArray<NSString *> *keys = @[ @"imageWidth", @"imageHeight", @"x", @"y", @"width", @"height" ];
	for (NSString *key in keys) {
		if (!IMAssetFaceCreateInteger(dictionary[key])) return nil;
	}
	return [self requestWithAssetId:assetId
	                         personId:personId
	                      imageWidth:[dictionary[@"imageWidth"] integerValue]
	                     imageHeight:[dictionary[@"imageHeight"] integerValue]
	                               x:[dictionary[@"x"] integerValue]
	                               y:[dictionary[@"y"] integerValue]
	                            width:[dictionary[@"width"] integerValue]
	                           height:[dictionary[@"height"] integerValue]];
}

- (NSDictionary<NSString *, id> *)requestDictionary {
	return @{
		@"assetId": self.assetId,
		@"personId": self.personId,
		@"imageWidth": @(self.imageWidth),
		@"imageHeight": @(self.imageHeight),
		@"x": @(self.x),
		@"y": @(self.y),
		@"width": @(self.width),
		@"height": @(self.height),
	};
}

@end
