#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PersonMergeViewController : UITableViewController
- (instancetype)initWithTargetPersonId:(NSString *)personId targetName:(nullable NSString *)name;
@end

NS_ASSUME_NONNULL_END
