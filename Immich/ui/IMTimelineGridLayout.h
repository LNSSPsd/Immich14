#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMTimelineGridLayoutBackLayerKind;

@interface IMTimelineGridLayout : UICollectionViewLayout

@property (nonatomic, readonly) NSInteger columns;
@property (nonatomic) CGFloat spacing;

@property (nonatomic) BOOL rowMode;
@property (nonatomic) CGFloat rowHeight;

@property (nonatomic) CGFloat footerHeight;

- (void)setColumns:(NSInteger)columns;

#pragma mark Zoom

@property (nonatomic, readonly, getter=isZooming) BOOL zooming;
@property (nonatomic, readonly) NSInteger frontColumns;
@property (nonatomic, readonly) NSInteger backColumns;

- (void)beginZoomWithAnchor:(NSIndexPath *)anchor
                   fraction:(CGPoint)fraction
                     target:(CGPoint)target
              contentOffset:(CGPoint)contentOffset;

- (void)setZoomFrontColumns:(NSInteger)frontColumns
                backColumns:(NSInteger)backColumns
            normalizedWidth:(CGFloat)normalizedWidth
                       fade:(CGFloat)fade;

- (CGFloat)restingContentOffsetYForColumns:(NSInteger)columns;

- (void)endZoomAtColumns:(NSInteger)columns;

@end

NS_ASSUME_NONNULL_END
