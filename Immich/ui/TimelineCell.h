#import <UIKit/UIKit.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TimelineCellReuseIdentifier;

@interface TimelineCell : UICollectionViewCell

- (void)configureWithAsset:(nullable IMAsset *)asset;

@end

NS_ASSUME_NONNULL_END
