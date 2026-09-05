#import <UIKit/UIKit.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface AssetEditViewController : UIViewController

- (instancetype)initWithAsset:(IMAsset *)asset;

@property (nonatomic, copy, nullable) void (^onSaved)(UIImage *_Nullable previewImage);

@end

NS_ASSUME_NONNULL_END
