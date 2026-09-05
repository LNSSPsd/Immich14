#import "IMAssetEdit.h"
#import <math.h>

NSString *const IMAssetEditActionCrop = @"crop";
NSString *const IMAssetEditActionRotate = @"rotate";
NSString *const IMAssetEditActionMirror = @"mirror";
NSString *const IMAssetEditMirrorAxisHorizontal = @"horizontal";
NSString *const IMAssetEditMirrorAxisVertical = @"vertical";

static id IMAssetEditValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static BOOL IMAssetEditParametersValid(NSString *action, NSDictionary *parameters) {
	if (![parameters isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	if ([action isEqualToString:IMAssetEditActionCrop]) {
		for (NSString *key in @[ @"x", @"y", @"width", @"height" ]) {
			id value = parameters[key];
			double number = [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : -1;
			if (![value isKindOfClass:[NSNumber class]] || !isfinite(number) || number < 0 || floor(number) != number) {
				return NO;
			}
		}
		return [parameters[@"width"] integerValue] > 0 && [parameters[@"height"] integerValue] > 0;
	}
	if ([action isEqualToString:IMAssetEditActionRotate]) {
		id value = parameters[@"angle"];
		if (![value isKindOfClass:[NSNumber class]]) {
			return NO;
		}
		double angle = [value doubleValue];
		return isfinite(angle);
	}
	if ([action isEqualToString:IMAssetEditActionMirror]) {
		NSString *axis = parameters[@"axis"];
		return [axis isKindOfClass:[NSString class]] &&
		       ([axis isEqualToString:IMAssetEditMirrorAxisHorizontal] ||
		        [axis isEqualToString:IMAssetEditMirrorAxisVertical]);
	}
	return NO;
}

@interface IMAssetEdit ()
@property (nonatomic, copy) NSString *action;
@property (nonatomic, copy) NSDictionary<NSString *, id> *parameters;
@property (nonatomic, copy, nullable) NSString *editId;
@end

@implementation IMAssetEdit

+ (nullable instancetype)editWithAction:(NSString *)action
	                         parameters:(NSDictionary<NSString *, id> *)parameters {
	if (![action isKindOfClass:[NSString class]] || action.length == 0 ||
	    !IMAssetEditParametersValid(action, parameters)) {
		return nil;
	}
	IMAssetEdit *edit = [[self alloc] init];
	edit.action = action;
	edit.parameters = [parameters copy];
	return edit;
}

+ (nullable instancetype)editWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSString *action = IMAssetEditValueOrNil(dictionary[@"action"]);
	NSDictionary *parameters = IMAssetEditValueOrNil(dictionary[@"parameters"]);
	IMAssetEdit *edit = [self editWithAction:action parameters:parameters];
	if (!edit) {
		return nil;
	}
	NSString *editId = IMAssetEditValueOrNil(dictionary[@"id"]);
	if (![editId isKindOfClass:[NSString class]] || editId.length == 0) {
		return nil;
	}
	edit.editId = editId;
	return edit;
}

- (NSDictionary<NSString *, id> *)requestDictionary {
	return @{ @"action": self.action, @"parameters": self.parameters };
}

@end
