#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AddToAlbumViewController : UIViewController
+ (instancetype)pickerForAssetId:(NSString *)assetId;
+ (instancetype)pickerForAssetIds:(NSArray<NSString *> *)assetIds;
@end

NS_ASSUME_NONNULL_END
