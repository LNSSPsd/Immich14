#import <UIKit/UIKit.h>
#import "IMMapMarker.h"

NS_ASSUME_NONNULL_BEGIN

@interface MapViewController : UIViewController

+ (instancetype)mapViewControllerWithMarkers:(NSArray<IMMapMarker *> *)markers
	                                      title:(nullable NSString *)title;

@end

NS_ASSUME_NONNULL_END
