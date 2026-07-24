#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import "IMAsset.h"
#import "IMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const TimelineCellReuseIdentifier;

@interface TimelineCell : UICollectionViewCell

@property (nonatomic) BOOL selectionModeEnabled;

- (void)configureWithAsset:(nullable IMAsset *)asset;

- (void)configureWithLocalAsset:(nullable PHAsset *)asset syncState:(IMSyncState)state;

@end

NS_ASSUME_NONNULL_END
