#import <UIKit/UIKit.h>
#import "IMPartner.h"

NS_ASSUME_NONNULL_BEGIN

@interface PartnerTimelineViewController : UIViewController

+ (instancetype)viewControllerWithPartner:(IMPartner *)partner;
- (instancetype)initWithPartner:(IMPartner *)partner NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
