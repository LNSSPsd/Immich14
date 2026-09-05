#import "IMLibrary.h"

static id IMLibraryValue(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

static NSArray<NSString *> *IMLibraryStrings(id value) {
	if (![value isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *result = [NSMutableArray array];
	for (id item in (NSArray *)value) if ([item isKindOfClass:[NSString class]]) [result addObject:item];
	return result;
}

@interface IMLibrary ()
@property (nonatomic, copy) NSString *libraryId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *ownerId;
@property (nonatomic, copy) NSArray<NSString *> *importPaths;
@property (nonatomic, copy) NSArray<NSString *> *exclusionPatterns;
@property (nonatomic, copy, nullable) NSString *createdAt;
@property (nonatomic, copy, nullable) NSString *updatedAt;
@property (nonatomic, copy, nullable) NSString *refreshedAt;
@property (nonatomic) NSInteger assetCount;
@end

@implementation IMLibrary
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMLibraryValue(dictionary[@"id"]);
		_libraryId = [value isKindOfClass:[NSString class]] ? [value copy] : @"";
		value = IMLibraryValue(dictionary[@"name"]);
		_name = [value isKindOfClass:[NSString class]] ? [value copy] : @"";
		value = IMLibraryValue(dictionary[@"ownerId"]);
		_ownerId = [value isKindOfClass:[NSString class]] ? [value copy] : @"";
		_importPaths = IMLibraryStrings(dictionary[@"importPaths"]);
		_exclusionPatterns = IMLibraryStrings(dictionary[@"exclusionPatterns"]);
		_createdAt = [[IMLibraryValue(dictionary[@"createdAt"]) isKindOfClass:[NSString class]] ? dictionary[@"createdAt"] : nil copy];
		_updatedAt = [[IMLibraryValue(dictionary[@"updatedAt"]) isKindOfClass:[NSString class]] ? dictionary[@"updatedAt"] : nil copy];
		_refreshedAt = [[IMLibraryValue(dictionary[@"refreshedAt"]) isKindOfClass:[NSString class]] ? dictionary[@"refreshedAt"] : nil copy];
		value = IMLibraryValue(dictionary[@"assetCount"]);
		_assetCount = [value isKindOfClass:[NSNumber class]] ? [value integerValue] : 0;
	}
	return self;
}
@end

@interface IMLibraryStats ()
@property (nonatomic) NSInteger photos;
@property (nonatomic) NSInteger videos;
@property (nonatomic) NSInteger total;
@property (nonatomic) unsigned long long usage;
@end

@implementation IMLibraryStats
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		_photos = [dictionary[@"photos"] isKindOfClass:[NSNumber class]] ? [dictionary[@"photos"] integerValue] : 0;
		_videos = [dictionary[@"videos"] isKindOfClass:[NSNumber class]] ? [dictionary[@"videos"] integerValue] : 0;
		_total = [dictionary[@"total"] isKindOfClass:[NSNumber class]] ? [dictionary[@"total"] integerValue] : 0;
		_usage = [dictionary[@"usage"] isKindOfClass:[NSNumber class]] ? [dictionary[@"usage"] unsignedLongLongValue] : 0;
	}
	return self;
}
@end

@interface IMLibraryValidation ()
@property (nonatomic, copy) NSString *importPath;
@property (nonatomic) BOOL valid;
@property (nonatomic, copy, nullable) NSString *message;
@end

@implementation IMLibraryValidation
- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		_importPath = [dictionary[@"importPath"] isKindOfClass:[NSString class]] ? [dictionary[@"importPath"] copy] : @"";
		_valid = [dictionary[@"isValid"] boolValue];
		_message = [dictionary[@"message"] isKindOfClass:[NSString class]] ? [dictionary[@"message"] copy] : nil;
	}
	return self;
}
@end
