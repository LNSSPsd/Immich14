#import "IMDatabaseBackup.h"

static id IMDatabaseBackupValue(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMDatabaseBackup ()
@property (nonatomic, copy) NSString *filename;
@property (nonatomic) unsigned long long filesize;
@property (nonatomic, copy) NSString *timezone;
@end

@implementation IMDatabaseBackup

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMDatabaseBackupValue(dictionary[@"filename"]);
		_filename = [value isKindOfClass:[NSString class]] ? [value copy] : @"";
		value = IMDatabaseBackupValue(dictionary[@"filesize"]);
		_filesize = [value isKindOfClass:[NSNumber class]] ? [value unsignedLongLongValue] : 0;
		value = IMDatabaseBackupValue(dictionary[@"timezone"]);
		_timezone = [value isKindOfClass:[NSString class]] ? [value copy] : @"";
	}
	return self;
}

+ (NSArray<IMDatabaseBackup *> *)backupsWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray<IMDatabaseBackup *> *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		if ([value isKindOfClass:[NSDictionary class]]) [result addObject:[[self alloc] initWithDictionary:value]];
	}
	return [result copy];
}

@end
