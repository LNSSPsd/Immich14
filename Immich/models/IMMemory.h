#import <Foundation/Foundation.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMMemory : NSObject

@property (nonatomic, copy, readonly) NSString *memoryId;
@property (nonatomic, copy, readonly) NSString *type;
@property (nonatomic, copy, readonly) NSArray<IMAsset *> *assets;
@property (nonatomic, strong, readonly) NSDate *memoryAt;
@property (nonatomic, strong, readonly, nullable) NSDate *showAt;
@property (nonatomic, strong, readonly, nullable) NSDate *hideAt;
@property (nonatomic, strong, readonly, nullable) NSDate *seenAt;
@property (nonatomic, readonly, getter=isSaved) BOOL saved;
@property (nonatomic, readonly) NSInteger sourceYear;

@property (nonatomic, readonly) NSString *displayTitle;
@property (nonatomic, readonly) NSString *displaySubtitle;
@property (nonatomic, readonly, getter=isActiveToday) BOOL activeToday;

+ (nullable instancetype)memoryWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMMemory *> *)memoriesWithResponseArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
