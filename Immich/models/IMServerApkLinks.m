#import "IMServerApkLinks.h"

static BOOL IMServerApkURLValue(id value) {
	if (![value isKindOfClass:[NSString class]]) {
		return NO;
	}
	NSString *string = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (string.length == 0) {
		return NO;
	}
	NSURLComponents *components = [NSURLComponents componentsWithString:string];
	NSString *scheme = components.scheme.lowercaseString;
	return components.URL != nil &&
	    ( [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"] ) &&
	    components.host.length > 0;
}

@interface IMServerApkLinks ()
@property (nonatomic, copy) NSString *arm64v8a;
@property (nonatomic, copy) NSString *armeabiv7a;
@property (nonatomic, copy) NSString *universal;
@property (nonatomic, copy) NSString *x86_64;
@end

@implementation IMServerApkLinks

+ (nullable instancetype)linksWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSArray<NSString *> *keys = @[ @"arm64v8a", @"armeabiv7a", @"universal", @"x86_64" ];
	for (NSString *key in keys) {
		if (!IMServerApkURLValue(dictionary[key])) {
			return nil;
		}
	}
	IMServerApkLinks *links = [[self alloc] init];
	links.arm64v8a = [dictionary[@"arm64v8a"] copy];
	links.armeabiv7a = [dictionary[@"armeabiv7a"] copy];
	links.universal = [dictionary[@"universal"] copy];
	links.x86_64 = [dictionary[@"x86_64"] copy];
	return links;
}

@end
