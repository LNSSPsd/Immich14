#import <UIKit/UIKit.h>
#import "IMAsset.h"
#import "IMZoomTransition.h"

NS_ASSUME_NONNULL_BEGIN

@class PHAsset;

@interface AssetViewController : UIViewController

+ (IMAsset *)viewerAssetForLocalAsset:(PHAsset *)asset;
+ (nullable NSString *)localIdentifierForViewerAssetId:(NSString *)assetId;
+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets
                       startIndex:(NSInteger)startIndex
                      localAssets:(NSDictionary<NSString *, PHAsset *> *)localAssets;

+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets startIndex:(NSInteger)startIndex;
+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets
                       startIndex:(NSInteger)startIndex
                         readOnly:(BOOL)readOnly;
+ (instancetype)viewerWithAssets:(NSArray<IMAsset *> *)assets
                       startIndex:(NSInteger)startIndex
                         readOnly:(BOOL)readOnly
                    ownerAware:(BOOL)ownerAware;

@property (nonatomic, weak, nullable) id<IMZoomTransitionSource> zoomSource;

@property (nonatomic, weak, nullable) UIImageView *presentSourceImageView;

- (IMAsset *)currentAsset;
- (nullable UIImageView *)currentPageImageView;

@end

NS_ASSUME_NONNULL_END
