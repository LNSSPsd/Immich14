#import <Foundation/Foundation.h>
#import "IMIntegrityReportItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMIntegrityReportPage : NSObject

@property (nonatomic, copy, readonly) NSArray<IMIntegrityReportItem *> *items;
@property (nonatomic, copy, readonly, nullable) NSString *nextCursor;

+ (nullable instancetype)pageWithResponseDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
