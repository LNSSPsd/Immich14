#import <UIKit/UIKit.h>
#import "IMAlbum.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMAlbumCellReuseIdentifier;

@interface IMAlbumCell : UICollectionViewCell
- (void)configureWithAlbum:(nullable IMAlbum *)album;
@end

NS_ASSUME_NONNULL_END
