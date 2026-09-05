#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AssetMetadataEditorViewController : UIViewController

- (instancetype)initWithAssetId:(NSString *)assetId
                   initialValues:(NSDictionary *)initialValues;

@property (nonatomic, copy, nullable) void (^onSaved)(void);

@end

NS_ASSUME_NONNULL_END
