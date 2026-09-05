#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDownloadArchiveInfo : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString *> *assetIds;
@property (nonatomic, readonly) NSInteger size;

+ (nullable instancetype)archiveWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
