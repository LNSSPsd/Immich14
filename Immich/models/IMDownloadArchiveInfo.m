#import "IMDownloadArchiveInfo.h"
#import <math.h>
#include <string.h>

static BOOL IMDownloadArchiveUUIDv4(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) {
		return NO;
	}
	NSString *raw = (NSString *)value;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:raw];
	if (!uuid || ![raw.lowercaseString isEqualToString:uuid.UUIDString.lowercaseString]) {
		return NO;
	}
	unichar version = [raw characterAtIndex:14];
	unichar variant = [raw characterAtIndex:19];
	BOOL validVariant = variant == '8' || variant == '9' || variant == 'a' || variant == 'A' ||
	                    variant == 'b' || variant == 'B';
	return version == '4' && validVariant;
}

static BOOL IMDownloadArchiveInteger(id value, NSInteger *outValue) {
	if (![value isKindOfClass:[NSNumber class]]) {
		return NO;
	}
	const char *type = [(NSNumber *)value objCType];
	if (type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0)) {
		return NO;
	}
	double number = [(NSNumber *)value doubleValue];
	if (!isfinite(number) || floor(number) != number || number < 0.0 ||
	    number > 9007199254740991.0 || number > (double)NSIntegerMax) {
		return NO;
	}
	if (outValue) {
		*outValue = [(NSNumber *)value integerValue];
	}
	return YES;
}

@interface IMDownloadArchiveInfo ()
@property (nonatomic, copy) NSArray<NSString *> *assetIds;
@property (nonatomic) NSInteger size;
@end

@implementation IMDownloadArchiveInfo

+ (nullable instancetype)archiveWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id rawAssetIds = dictionary[@"assetIds"];
	if (![rawAssetIds isKindOfClass:[NSArray class]] || [(NSArray *)rawAssetIds count] == 0) {
		return nil;
	}
	NSMutableArray<NSString *> *assetIds = [NSMutableArray arrayWithCapacity:[(NSArray *)rawAssetIds count]];
	NSMutableSet<NSString *> *seenIds = [NSMutableSet setWithCapacity:[(NSArray *)rawAssetIds count]];
	for (id value in (NSArray *)rawAssetIds) {
		if (!IMDownloadArchiveUUIDv4(value)) {
			return nil;
		}
		NSString *canonicalId = [(NSString *)value lowercaseString];
		if ([seenIds containsObject:canonicalId]) {
			return nil;
		}
		[seenIds addObject:canonicalId];
		[assetIds addObject:value];
	}
	NSInteger size = 0;
	if (!IMDownloadArchiveInteger(dictionary[@"size"], &size)) {
		return nil;
	}
	IMDownloadArchiveInfo *archive = [[self alloc] init];
	archive.assetIds = [assetIds copy];
	archive.size = size;
	return archive;
}

@end
