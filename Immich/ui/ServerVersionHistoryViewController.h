#import <UIKit/UIKit.h>
#import "IMServerInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface ServerVersionHistoryViewController : UITableViewController
- (instancetype)initWithHistory:(NSArray<IMServerVersionHistoryEntry *> *)history;
@end

NS_ASSUME_NONNULL_END
