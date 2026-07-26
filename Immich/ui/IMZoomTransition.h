#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol IMZoomTransitionSource <NSObject>
- (nullable UIImageView *)zoomTransitionImageViewForAssetId:(NSString *)assetId;
@end

@interface IMZoomTransition : NSObject <UIViewControllerAnimatedTransitioning>
+ (instancetype)transitionPresenting:(BOOL)presenting;
@end

NS_ASSUME_NONNULL_END
