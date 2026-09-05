#import "IMDownloadResponseDto.h"
#import <math.h>
#include <string.h>

static BOOL IMDownloadResponseInteger(id value, NSInteger *outValue) {
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

@interface IMDownloadResponseDto ()
@property (nonatomic, copy) NSArray<IMDownloadArchiveInfo *> *archives;
@property (nonatomic) NSInteger totalSize;
@end

@implementation IMDownloadResponseDto

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id rawArchives = dictionary[@"archives"];
	if (![rawArchives isKindOfClass:[NSArray class]]) {
		return nil;
	}
	NSMutableArray<IMDownloadArchiveInfo *> *archives = [NSMutableArray arrayWithCapacity:[(NSArray *)rawArchives count]];
	NSInteger sum = 0;
	for (id value in (NSArray *)rawArchives) {
		IMDownloadArchiveInfo *archive = [IMDownloadArchiveInfo archiveWithDictionary:value];
		if (!archive) {
			return nil;
		}
		if (archive.size > NSIntegerMax - sum) {
			return nil;
		}
		sum += archive.size;
		[archives addObject:archive];
	}
	NSInteger totalSize = 0;
	if (!IMDownloadResponseInteger(dictionary[@"totalSize"], &totalSize)) {
		return nil;
	}
	if (totalSize != sum) {
		return nil;
	}
	IMDownloadResponseDto *response = [[self alloc] init];
	response.archives = [archives copy];
	response.totalSize = totalSize;
	return response;
}

@end
