#import <UIKit/UIKit.h>
#import "IMSharedLink.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMSharedLinkAssetPickerCompletion)(NSArray<IMAsset *> *assets);

@interface SharedLinkAssetsViewController : UIViewController

+ (instancetype)managerForLink:(IMSharedLink *)link;

+ (instancetype)pickerWithExcludedAssetIds:(NSSet<NSString *> *)excludedAssetIds
                                completion:(IMSharedLinkAssetPickerCompletion)completion;

@end

NS_ASSUME_NONNULL_END
