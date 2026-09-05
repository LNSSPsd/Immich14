#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMIntegrityReportItem : NSObject

@property (nonatomic, copy, readonly) NSString *reportId;
@property (nonatomic, copy, readonly) NSString *type;
@property (nonatomic, copy, readonly) NSString *path;

@property (nonatomic, copy, readonly, nullable) NSString *assetId;
@property (nonatomic, copy, readonly, nullable) NSString *fileAssetId;
@property (nonatomic, copy, readonly, nullable) NSString *createdAt;

+ (nullable instancetype)itemWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMIntegrityReportItem *> *)itemsWithResponseArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
