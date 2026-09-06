#import <UIKit/UIKit.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSURLSessionTask *_Nullable (^IMAssetGridPageLoader)(NSInteger page,
	void (^completion)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error));
typedef void (^IMAssetGridSelectionHandler)(IMAsset *asset);

@interface AssetGridViewController : UIViewController

+ (instancetype)gridWithTitle:(NSString *)title assets:(NSArray<IMAsset *> *)assets;

@property (nonatomic, copy, nullable) NSString *nextPageToken;
@property (nonatomic, copy, nullable) IMAssetGridPageLoader pageLoader;

@property (nonatomic, copy, nullable) IMAssetGridSelectionHandler selectionHandler;

@end

NS_ASSUME_NONNULL_END
