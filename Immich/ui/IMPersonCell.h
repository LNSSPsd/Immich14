#import <UIKit/UIKit.h>
#import "IMPerson.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMPersonCellReuseIdentifier;

@interface IMPersonCell : UICollectionViewCell
- (void)configureWithPerson:(nullable IMPerson *)person;
@end

NS_ASSUME_NONNULL_END
