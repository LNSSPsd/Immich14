#import "IMUserLicense.h"
#import "common.h"

static BOOL IMUserLicenseKeyIsValid(id value) {
	if (![value isKindOfClass:[NSString class]]) return NO;
	NSString *key = (NSString *)value;
	static NSRegularExpression *regex;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"^IM(SV|CL)(-[0-9A-Za-z]{4}){8}$" options:0 error:nil];
	});
	return [regex firstMatchInString:key options:0 range:NSMakeRange(0, key.length)] != nil;
}

static BOOL IMUserLicenseDateTimeIsValid(id value) {
	if (![value isKindOfClass:[NSString class]]) return NO;
	NSString *raw = (NSString *)value;
	static NSRegularExpression *regex;
	static NSISO8601DateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d+)?)?(?:Z|[+-]\\d{2}:\\d{2})$" options:0 error:nil];
		formatter = [[NSISO8601DateFormatter alloc] init];
		formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	});
	return [regex firstMatchInString:raw options:0 range:NSMakeRange(0, raw.length)] != nil && [formatter dateFromString:raw] != nil;
}

@interface IMUserLicense ()
@property (nonatomic, copy, readwrite) NSString *activationKey;
@property (nonatomic, copy, readwrite) NSString *licenseKey;
@property (nonatomic, copy, readwrite) NSString *activatedAt;
@end

@implementation IMUserLicense

+ (nullable instancetype)licenseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id activationKey = dictionary[@"activationKey"];
	id licenseKey = dictionary[@"licenseKey"];
	id activatedAt = dictionary[@"activatedAt"];
	if (![activationKey isKindOfClass:[NSString class]] || [(NSString *)activationKey length] == 0 ||
	    !IMUserLicenseKeyIsValid(licenseKey) || !IMUserLicenseDateTimeIsValid(activatedAt)) return nil;
	IMUserLicense *license = [[self alloc] init];
	license.activationKey = activationKey;
	license.licenseKey = licenseKey;
	license.activatedAt = activatedAt;
	return license;
}

@end
