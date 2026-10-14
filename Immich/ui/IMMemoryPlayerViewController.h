#import <UIKit/UIKit.h>
#import "IMMemory.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMMemoryPlayerViewController : UIViewController

+ (instancetype)playerWithMemories:(NSArray<IMMemory *> *)memories startIndex:(NSInteger)startIndex;

@property (nonatomic, weak, nullable) UIImageView *sourceImageView;

@property (nonatomic, copy, nullable) void (^onChange)(void);

@end

NS_ASSUME_NONNULL_END
