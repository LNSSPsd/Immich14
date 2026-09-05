#import "IMOcrLine.h"
#import <math.h>

@interface IMOcrLine ()
@property (nonatomic, copy) NSString *text;
@property (nonatomic) CGRect normalizedRect;
@end

@implementation IMOcrLine

static BOOL IMOcrFiniteNumber(id value) {
	if (![value isKindOfClass:[NSNumber class]]) {
		return NO;
	}
	double number = [value doubleValue];
	return isfinite(number);
}

+ (nullable instancetype)lineWithDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSString *text = dict[@"text"];
	NSString *assetId = dict[@"assetId"];
	NSString *lineId = dict[@"id"];
	if (![text isKindOfClass:[NSString class]] ||
	    ![assetId isKindOfClass:[NSString class]] || assetId.length == 0 ||
	    ![lineId isKindOfClass:[NSString class]] || lineId.length == 0) {
		return nil;
	}
	for (NSString *key in @[ @"x1", @"x2", @"x3", @"x4", @"y1", @"y2", @"y3", @"y4" ]) {
		if (!IMOcrFiniteNumber(dict[key])) {
			return nil;
		}
	}
	for (NSString *key in @[ @"boxScore", @"textScore" ]) {
		if (![dict[key] isKindOfClass:[NSNumber class]] || !isfinite([dict[key] doubleValue])) {
			return nil;
		}
	}

	double xs[4] = {
		[dict[@"x1"] doubleValue], [dict[@"x2"] doubleValue],
		[dict[@"x3"] doubleValue], [dict[@"x4"] doubleValue],
	};
	double ys[4] = {
		[dict[@"y1"] doubleValue], [dict[@"y2"] doubleValue],
		[dict[@"y3"] doubleValue], [dict[@"y4"] doubleValue],
	};
	double minX = xs[0], maxX = xs[0], minY = ys[0], maxY = ys[0];
	for (int i = 1; i < 4; i++) {
		minX = MIN(minX, xs[i]);
		maxX = MAX(maxX, xs[i]);
		minY = MIN(minY, ys[i]);
		maxY = MAX(maxY, ys[i]);
	}

	IMOcrLine *line = [[IMOcrLine alloc] init];
	line.text = text;
	line.normalizedRect = CGRectMake(minX, minY, maxX - minX, maxY - minY);
	return line;
}

@end
