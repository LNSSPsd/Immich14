#import <UIKit/UIKit.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMPlaceCellReuseIdentifier;

@interface IMPlaceCell : UICollectionViewCell
- (void)configureWithAsset:(nullable IMAsset *)asset cityName:(nullable NSString *)cityName;
@end

NS_ASSUME_NONNULL_END
