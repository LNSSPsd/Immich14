#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AdminUserPreferencesViewController : UITableViewController

- (instancetype)initWithUserId:(NSString *)userId userName:(nullable NSString *)userName;

@end

NS_ASSUME_NONNULL_END
