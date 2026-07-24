#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LocalAssetGridViewController : UIViewController
+ (instancetype)gridWithTitle:(NSString *)title deviceAssetIds:(NSArray<NSString *> *)deviceAssetIds;
@end

NS_ASSUME_NONNULL_END
