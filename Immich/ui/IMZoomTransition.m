#import "IMZoomTransition.h"
#import "AssetViewController.h"

@interface IMZoomTransition ()
@property (nonatomic) BOOL presenting;
@end

@implementation IMZoomTransition

+ (instancetype)transitionPresenting:(BOOL)presenting {
	IMZoomTransition *transition = [[IMZoomTransition alloc] init];
	transition.presenting = presenting;
	return transition;
}

- (NSTimeInterval)transitionDuration:(nullable id<UIViewControllerContextTransitioning>)context {
	return 0.38;
}

static CGRect IMAspectFitRect(double ratio, CGRect bounds) {
	if (ratio <= 0) {
		return bounds;
	}
	CGFloat width = bounds.size.width;
	CGFloat height = width / (CGFloat)ratio;
	if (height > bounds.size.height) {
		height = bounds.size.height;
		width = height * (CGFloat)ratio;
	}
	return CGRectMake(bounds.origin.x + (bounds.size.width - width) / 2,
	                  bounds.origin.y + (bounds.size.height - height) / 2,
	                  width, height);
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
	if (self.presenting) {
		[self animatePresent:context];
	} else {
		[self animateDismiss:context];
	}
}

- (void)animatePresent:(id<UIViewControllerContextTransitioning>)context {
	UIView *container = context.containerView;
	AssetViewController *viewer =
	    (AssetViewController *)[context viewControllerForKey:UITransitionContextToViewControllerKey];
	UIView *toView = [context viewForKey:UITransitionContextToViewKey];
	toView.frame = [context finalFrameForViewController:viewer];
	[container addSubview:toView];

	IMAsset *asset = viewer.currentAsset;
	UIImageView *sourceView = viewer.presentSourceImageView;
	if (!sourceView || !sourceView.image || !sourceView.window) {
		sourceView = [viewer.zoomSource zoomTransitionImageViewForAssetId:asset.assetId];
	}
	if (!sourceView || !sourceView.image || !sourceView.window) {
		toView.alpha = 0;
		toView.transform = CGAffineTransformMakeScale(0.86, 0.86);
		[UIView animateWithDuration:0.3
		                      delay:0
		                    options:UIViewAnimationOptionCurveEaseOut
		                 animations:^{
			    toView.alpha = 1;
			    toView.transform = CGAffineTransformIdentity;
		    }
		                 completion:^(BOOL finished) { [context completeTransition:YES]; }];
		return;
	}

	UIImage *thumb = sourceView.image;
	CGRect sourceFrame = [sourceView convertRect:sourceView.bounds toView:container];
	double ratio = asset.ratio > 0
	                   ? asset.ratio
	                   : (thumb.size.height > 0 ? thumb.size.width / thumb.size.height : 0);
	CGRect destFrame = IMAspectFitRect(ratio, toView.frame);

	UIImageView *movingView = [[UIImageView alloc] initWithImage:thumb];
	movingView.contentMode = UIViewContentModeScaleAspectFill;
	movingView.clipsToBounds = YES;
	movingView.frame = sourceFrame;
	[container addSubview:movingView];
	sourceView.hidden = YES;
	toView.alpha = 0;

	[UIView animateWithDuration:[self transitionDuration:context]
	                      delay:0
	     usingSpringWithDamping:0.9
	      initialSpringVelocity:0.3
	                    options:0
	                 animations:^{
		    movingView.frame = destFrame;
		    toView.alpha = 1;
	    }
	                 completion:^(BOOL finished) {
		    sourceView.hidden = NO;
		    [movingView removeFromSuperview];
		    [context completeTransition:YES];
	    }];
}

- (void)animateDismiss:(id<UIViewControllerContextTransitioning>)context {
	UIView *container = context.containerView;
	AssetViewController *viewer =
	    (AssetViewController *)[context viewControllerForKey:UITransitionContextFromViewControllerKey];
	UIView *fromView = [context viewForKey:UITransitionContextFromViewKey];
	UIView *toView = [context viewForKey:UITransitionContextToViewKey];
	if (toView) {
		toView.frame = [context finalFrameForViewController:
		                            [context viewControllerForKey:UITransitionContextToViewControllerKey]];
		[container insertSubview:toView belowSubview:fromView];
	}

	UIImageView *pageImageView = viewer.currentPageImageView;
	UIImageView *destView = [viewer.zoomSource zoomTransitionImageViewForAssetId:viewer.currentAsset.assetId];
	if (!pageImageView || !pageImageView.image || !destView || !destView.window) {
		[UIView animateWithDuration:0.25
		                 animations:^{
			    fromView.alpha = 0;
			    fromView.transform = CGAffineTransformTranslate(fromView.transform, 0, 120);
		    }
		                 completion:^(BOOL finished) { [context completeTransition:YES]; }];
		return;
	}

	CGRect startFrame = [pageImageView convertRect:pageImageView.bounds toView:container];
	CGRect destFrame = [destView convertRect:destView.bounds toView:container];

	UIImageView *movingView = [[UIImageView alloc] initWithImage:pageImageView.image];
	movingView.contentMode = UIViewContentModeScaleAspectFill;
	movingView.clipsToBounds = YES;
	movingView.frame = startFrame;
	[container addSubview:movingView];
	pageImageView.hidden = YES;
	destView.hidden = YES;

	[UIView animateWithDuration:[self transitionDuration:context]
	                      delay:0
	     usingSpringWithDamping:0.9
	      initialSpringVelocity:0.1
	                    options:0
	                 animations:^{
		    movingView.frame = destFrame;
		    fromView.alpha = 0;
	    }
	                 completion:^(BOOL finished) {
		    destView.hidden = NO;
		    [movingView removeFromSuperview];
		    [context completeTransition:YES];
	    }];
}

@end
