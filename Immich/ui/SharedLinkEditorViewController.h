#import <UIKit/UIKit.h>
#import "IMSharedLink.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMSharedLinkEditorSaveHandler)(NSDictionary<NSString *, id> *fields);

@interface SharedLinkEditorViewController : UITableViewController

+ (instancetype)editorForNewLinkWithTitle:(NSString *)title
                               saveHandler:(IMSharedLinkEditorSaveHandler)saveHandler;
+ (instancetype)editorForLink:(IMSharedLink *)link
                   saveHandler:(IMSharedLinkEditorSaveHandler)saveHandler;

- (void)setSaving:(BOOL)saving;

@end

NS_ASSUME_NONNULL_END
