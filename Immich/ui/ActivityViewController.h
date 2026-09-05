#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ActivityViewController : UITableViewController

+ (instancetype)activityViewControllerForAlbumId:(NSString *)albumId
                                           assetId:(nullable NSString *)assetId
                                             title:(nullable NSString *)title;

@end

NS_ASSUME_NONNULL_END
