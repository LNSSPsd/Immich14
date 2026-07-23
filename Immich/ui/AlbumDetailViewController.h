#import <UIKit/UIKit.h>
#import "IMAlbum.h"

NS_ASSUME_NONNULL_BEGIN

@interface AlbumDetailViewController : UIViewController
+ (instancetype)detailViewControllerForAlbum:(IMAlbum *)album;
@end

NS_ASSUME_NONNULL_END
