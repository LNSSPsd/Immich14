#import <UIKit/UIKit.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMBulkAssetActions : NSObject

+ (void)confirmDeleteAssets:(NSArray<IMAsset *> *)assets
       presentingController:(UIViewController *)presenter
                  completion:(void (^)(BOOL deleted))completion;

+ (void)favoriteAssets:(NSArray<IMAsset *> *)assets
  presentingController:(UIViewController *)presenter
             completion:(void (^)(BOOL success))completion;

+ (void)downloadAssets:(NSArray<IMAsset *> *)assets
  presentingController:(UIViewController *)presenter
             completion:(void (^)(void))completion;

+ (void)presentAddToAlbumForAssets:(NSArray<IMAsset *> *)assets
              presentingController:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
