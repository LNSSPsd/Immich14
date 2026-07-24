#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTimelineGridLayout : UICollectionViewLayout

@property (nonatomic, readonly) NSInteger fromColumns;
@property (nonatomic, readonly) NSInteger toColumns;
@property (nonatomic, readonly) CGFloat progress; 
@property (nonatomic) CGFloat spacing;

@property (nonatomic) BOOL rowMode;
@property (nonatomic) CGFloat rowHeight;

@property (nonatomic) CGFloat footerHeight;

- (void)setFromColumns:(NSInteger)fromColumns toColumns:(NSInteger)toColumns progress:(CGFloat)progress;

@end

NS_ASSUME_NONNULL_END
