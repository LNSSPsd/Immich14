#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMSearchFilterApplyHandler)(NSDictionary<NSString *, id> *criteria);

@interface IMSearchFilterViewController : UIViewController

- (instancetype)initWithApplyHandler:(IMSearchFilterApplyHandler)handler;

@end

NS_ASSUME_NONNULL_END
