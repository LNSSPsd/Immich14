#import <Foundation/Foundation.h>
#import "IMDownloadArchiveInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMDownloadResponseDto : NSObject

@property (nonatomic, copy, readonly) NSArray<IMDownloadArchiveInfo *> *archives;
@property (nonatomic, readonly) NSInteger totalSize;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
