#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMClusterCellReuseIdentifier;

@interface IMClusterCell : UICollectionViewCell

- (void)configureWithTitle:(NSString *)title count:(NSInteger)count coverAssetId:(nullable NSString *)assetId;

- (void)configureWithTitle:(NSString *)title count:(NSInteger)count coverLocalAsset:(nullable PHAsset *)asset;

@end

NS_ASSUME_NONNULL_END
