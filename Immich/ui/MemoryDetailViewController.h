#import <UIKit/UIKit.h>
#import "IMMemory.h"

NS_ASSUME_NONNULL_BEGIN

@interface MemoryDetailViewController : UIViewController
+ (instancetype)viewControllerForMemory:(IMMemory *)memory;
@end

NS_ASSUME_NONNULL_END
