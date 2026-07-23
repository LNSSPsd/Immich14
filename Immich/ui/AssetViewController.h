#import <UIKit/UIKit.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface AssetViewController : UIViewController

+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets startIndex:(NSInteger)startIndex;

@end

NS_ASSUME_NONNULL_END
