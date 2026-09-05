#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMCalendarHeatmapEntry : NSObject

@property (nonatomic, copy, readonly) NSString *date;
@property (nonatomic, readonly) NSInteger count;

+ (nullable instancetype)entryWithDictionary:(NSDictionary *)dictionary;

@end

@interface IMCalendarHeatmap : NSObject

@property (nonatomic, copy, readonly) NSString *fromDate;
@property (nonatomic, copy, readonly) NSString *toDate;
@property (nonatomic, copy, readonly) NSArray<IMCalendarHeatmapEntry *> *series;
@property (nonatomic, readonly) NSInteger totalCount;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
