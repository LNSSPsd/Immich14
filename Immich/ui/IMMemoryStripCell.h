#import <UIKit/UIKit.h>
#import "IMMemory.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMMemoryStripCellReuseIdentifier;

@interface IMMemoryStripCell : UICollectionViewCell
@property (nonatomic, copy) NSArray<IMMemory *> *memories;
@property (nonatomic, copy, nullable) void (^onSelect)(NSInteger index, UIImageView *cover);
@end

NS_ASSUME_NONNULL_END
