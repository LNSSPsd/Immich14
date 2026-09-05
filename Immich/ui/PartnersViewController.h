#import <UIKit/UIKit.h>
#import "IMPartner.h"
NS_ASSUME_NONNULL_BEGIN
@interface PartnersViewController : UITableViewController
+ (instancetype)pickerWithUsers:(NSArray<IMPartner *> *)users;
@end
NS_ASSUME_NONNULL_END
