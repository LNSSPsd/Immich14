#import <UIKit/UIKit.h>
#import "IMMemory.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMMemoryEditorSavedHandler)(IMMemory *memory);

@interface MemoryEditorViewController : UITableViewController

- (instancetype)initForCreate;

- (instancetype)initWithMemory:(IMMemory *)memory;

@property (nonatomic, copy, nullable) IMMemoryEditorSavedHandler onSaved;

@end

NS_ASSUME_NONNULL_END
