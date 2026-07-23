#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMThumbCacheTask : NSObject
- (void)cancel;
@end

@interface IMThumbCache : NSObject

+ (instancetype)shared;

- (nullable IMThumbCacheTask *)thumbnailForAssetId:(NSString *)assetId
                                                size:(NSString *)size
                                          completion:(void (^)(UIImage *_Nullable image))completion;

@end

NS_ASSUME_NONNULL_END
