#import <UIKit/UIKit.h>
#import "IMMemory.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMMemoryCellReuseIdentifier;

@interface IMMemoryCell : UICollectionViewCell
- (void)configureWithMemory:(nullable IMMemory *)memory;
@end

NS_ASSUME_NONNULL_END
