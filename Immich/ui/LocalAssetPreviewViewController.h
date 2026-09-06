#import <UIKit/UIKit.h>

@class PHAsset;

NS_ASSUME_NONNULL_BEGIN

@interface LocalAssetPreviewViewController : UIViewController

+ (instancetype)previewWithAsset:(PHAsset *)asset;

@end

NS_ASSUME_NONNULL_END
