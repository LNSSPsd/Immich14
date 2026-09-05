#import <UIKit/UIKit.h>
#import "IMPersonProfile.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMPersonProfileSavedHandler)(IMPersonProfile *person);

@interface PersonProfileViewController : UITableViewController

- (instancetype)initWithPersonId:(NSString *)personId
                      displayName:(nullable NSString *)displayName
                         onSaved:(nullable IMPersonProfileSavedHandler)onSaved;

@end

NS_ASSUME_NONNULL_END
