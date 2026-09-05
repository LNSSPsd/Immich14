#import "IMIntegrityReportPage.h"

static id IMIntegrityPageValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMIntegrityReportPage ()
@property (nonatomic, copy) NSArray<IMIntegrityReportItem *> *items;
@property (nonatomic, copy, nullable) NSString *nextCursor;
@end

@implementation IMIntegrityReportPage

+ (nullable instancetype)pageWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id rawItems = IMIntegrityPageValueOrNil(dictionary[@"items"]);
	if (![rawItems isKindOfClass:[NSArray class]]) {
		return nil;
	}
	NSMutableArray<IMIntegrityReportItem *> *items = [NSMutableArray arrayWithCapacity:[rawItems count]];
	for (id value in (NSArray *)rawItems) {
		IMIntegrityReportItem *item = [IMIntegrityReportItem itemWithResponseDictionary:value];
		if (!item) {
			return nil;
		}
		[items addObject:item];
	}
	id cursor = IMIntegrityPageValueOrNil(dictionary[@"nextCursor"]);
	if (cursor != nil && (![cursor isKindOfClass:[NSString class]] || [cursor length] == 0)) {
		return nil;
	}
	IMIntegrityReportPage *page = [[self alloc] init];
	page.items = [items copy];
	page.nextCursor = [cursor isKindOfClass:[NSString class]] ? [cursor copy] : nil;
	return page;
}

@end
