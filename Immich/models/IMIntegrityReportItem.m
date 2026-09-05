#import "IMIntegrityReportItem.h"
#import "IMIntegrityReportSummary.h"

static BOOL IMIntegrityReportIdentifierIsValid(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) {
		return NO;
	}
	NSString *raw = (NSString *)value;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:raw];
	if (!uuid || ![raw.lowercaseString isEqualToString:uuid.UUIDString.lowercaseString]) {
		return NO;
	}
	NSString *canonical = raw.lowercaseString;
	unichar version = [canonical characterAtIndex:14];
	unichar variant = [canonical characterAtIndex:19];
	BOOL validVariant = variant == '8' || variant == '9' || variant == 'a' || variant == 'b';
	return (version == '4' || version == '7') && validVariant;
}

static id IMIntegrityValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMIntegrityReportItem ()
@property (nonatomic, copy) NSString *reportId;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy, nullable) NSString *assetId;
@property (nonatomic, copy, nullable) NSString *fileAssetId;
@property (nonatomic, copy, nullable) NSString *createdAt;
@end

@implementation IMIntegrityReportItem

+ (nullable instancetype)itemWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id identifier = IMIntegrityValueOrNil(dictionary[@"id"]);
	if (identifier == nil) {
		identifier = IMIntegrityValueOrNil(dictionary[@"reportId"]);
	}
	id type = IMIntegrityValueOrNil(dictionary[@"type"]);
	id path = IMIntegrityValueOrNil(dictionary[@"path"]);
	if (!IMIntegrityReportIdentifierIsValid(identifier) || !IMIntegrityReportTypeIsKnown(type) ||
	    ![path isKindOfClass:[NSString class]]) {
		return nil;
	}
	IMIntegrityReportItem *item = [[self alloc] init];
	item.reportId = [identifier copy];
	item.type = [type copy];
	item.path = [path copy];
	id value = IMIntegrityValueOrNil(dictionary[@"assetId"]);
	item.assetId = [value isKindOfClass:[NSString class]] && [value length] ? [value copy] : nil;
	value = IMIntegrityValueOrNil(dictionary[@"fileAssetId"]);
	item.fileAssetId = [value isKindOfClass:[NSString class]] && [value length] ? [value copy] : nil;
	value = IMIntegrityValueOrNil(dictionary[@"createdAt"]);
	item.createdAt = [value isKindOfClass:[NSString class]] && [value length] ? [value copy] : nil;
	return item;
}

+ (NSArray<IMIntegrityReportItem *> *)itemsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMIntegrityReportItem *> *items = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMIntegrityReportItem *item = [self itemWithResponseDictionary:value];
		if (item) {
			[items addObject:item];
		}
	}
	return [items copy];
}

@end
