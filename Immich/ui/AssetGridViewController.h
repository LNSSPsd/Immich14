#import <UIKit/UIKit.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface AssetGridViewController : UIViewController
+ (instancetype)gridWithTitle:(NSString *)title assets:(NSArray<IMAsset *> *)assets;
@end

NS_ASSUME_NONNULL_END
