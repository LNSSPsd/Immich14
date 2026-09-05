#import "IMMaintenanceDetectInstall.h"
#include <math.h>
#include <string.h>

static BOOL IMMaintenanceBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMMaintenanceInteger(id value, NSInteger *outValue) {
	if (![value isKindOfClass:[NSNumber class]] || IMMaintenanceBoolean(value)) return NO;
	double number = [(NSNumber *)value doubleValue];
	if (!isfinite(number) || floor(number) != number || number < -9007199254740991.0 || number > 9007199254740991.0) return NO;
	if (outValue) *outValue = [(NSNumber *)value integerValue];
	return YES;
}

static BOOL IMMaintenanceFolderName(NSString *value) {
	return [value isKindOfClass:[NSString class]] &&
	       ([value isEqualToString:@"encoded-video"] || [value isEqualToString:@"library"] ||
	        [value isEqualToString:@"upload"] || [value isEqualToString:@"profile"] ||
	        [value isEqualToString:@"thumbs"] || [value isEqualToString:@"backups"]);
}

@interface IMMaintenanceStorageFolder ()
@property (nonatomic, copy) NSString *folder;
@property (nonatomic, getter=isReadable) BOOL readable;
@property (nonatomic, getter=isWritable) BOOL writable;
@property (nonatomic) NSInteger files;
@end

@interface IMMaintenanceDetectInstall ()
@property (nonatomic, copy) NSArray<IMMaintenanceStorageFolder *> *storage;
@end

@implementation IMMaintenanceStorageFolder

+ (nullable instancetype)folderWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id folder = dictionary[@"folder"];
	id readable = dictionary[@"readable"];
	id writable = dictionary[@"writable"];
	NSInteger files = 0;
	if (!IMMaintenanceFolderName(folder) || !IMMaintenanceBoolean(readable) ||
	    !IMMaintenanceBoolean(writable) || !IMMaintenanceInteger(dictionary[@"files"], &files)) return nil;
	IMMaintenanceStorageFolder *result = [[self alloc] init];
	result.folder = [folder copy];
	result.readable = [readable boolValue];
	result.writable = [writable boolValue];
	result.files = files;
	return result;
}

+ (NSArray<IMMaintenanceStorageFolder *> *)foldersWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray<IMMaintenanceStorageFolder *> *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMMaintenanceStorageFolder *folder = [value isKindOfClass:[NSDictionary class]] ? [self folderWithResponseDictionary:value] : nil;
		if (folder) [result addObject:folder];
	}
	return [result copy];
}

@end

@implementation IMMaintenanceDetectInstall

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] || ![dictionary[@"storage"] isKindOfClass:[NSArray class]]) return nil;
	NSArray *rawStorage = dictionary[@"storage"];
	NSMutableArray<IMMaintenanceStorageFolder *> *storage = [NSMutableArray arrayWithCapacity:rawStorage.count];
	for (id value in rawStorage) {
		if (![value isKindOfClass:[NSDictionary class]]) return nil;
		IMMaintenanceStorageFolder *folder = [IMMaintenanceStorageFolder folderWithResponseDictionary:value];
		if (!folder) return nil;
		[storage addObject:folder];
	}
	IMMaintenanceDetectInstall *result = [[self alloc] init];
	result.storage = [storage copy];
	return result;
}

@end
