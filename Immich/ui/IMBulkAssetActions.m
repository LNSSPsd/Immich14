#import "IMBulkAssetActions.h"
#import "IMAssetApi.h"
#import "AddToAlbumViewController.h"
#import "common.h"
#import <Photos/Photos.h>

@implementation IMBulkAssetActions

+ (NSArray<NSString *> *)idsForAssets:(NSArray<IMAsset *> *)assets {
	NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:assets.count];
	for (IMAsset *asset in assets) {
		[ids addObject:asset.assetId];
	}
	return ids;
}

+ (void)showErrorAlertWithTitle:(NSString *)title
                          message:(nullable NSString *)message
            presentingController:(UIViewController *)presenter {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Delete

+ (void)confirmDeleteAssets:(NSArray<IMAsset *> *)assets
       presentingController:(UIViewController *)presenter
                  completion:(void (^)(BOOL deleted))completion {
	NSString *title = assets.count == 1 ? _(@"Delete 1 item?") : [NSString stringWithFormat:_(@"Delete %ld items?"), (long)assets.count];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
	                                                                 message:_(@"This deletes them from the server.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel")
	                                           style:UIAlertActionStyleCancel
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    completion(NO);
	    }]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete")
	                                           style:UIAlertActionStyleDestructive
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    [IMAssetApi deleteAssetIds:[self idsForAssets:assets]
		                          force:NO
		                     completion:^(BOOL success, NSError *_Nullable error) {
			        if (!success) {
				        [self showErrorAlertWithTitle:_(@"Couldn't Delete")
				                                message:error.localizedDescription
				                  presentingController:presenter];
			        }
			        completion(success);
		        }];
	    }]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Favorite

+ (void)favoriteAssets:(NSArray<IMAsset *> *)assets
  presentingController:(UIViewController *)presenter
             completion:(void (^)(BOOL success))completion {
	[self setFavorite:YES assets:assets presentingController:presenter completion:completion];
}

+ (void)setFavorite:(BOOL)favorite
             assets:(NSArray<IMAsset *> *)assets
presentingController:(UIViewController *)presenter
         completion:(void (^)(BOOL success))completion {
	[IMAssetApi setFavorite:favorite
	            forAssetIds:[self idsForAssets:assets]
	             completion:^(BOOL success, NSError *_Nullable error) {
		    if (!success) {
			    [self showErrorAlertWithTitle:favorite ? _(@"Couldn't Favorite") : _(@"Couldn't Unfavorite")
			                            message:error.localizedDescription
			              presentingController:presenter];
		    }
		    completion(success);
	    }];
}

#pragma mark - Download

+ (void)downloadAssets:(NSArray<IMAsset *> *)assets
  presentingController:(UIViewController *)presenter
             completion:(void (^)(void))completion {
	__weak UIViewController *weakPresenter = presenter;
	void (^handler)(PHAuthorizationStatus) = ^(PHAuthorizationStatus status) {
		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *strongPresenter = weakPresenter;
			if (!strongPresenter) {
				return;
			}
			BOOL authorized = (status == PHAuthorizationStatusAuthorized);
			if (@available(iOS 14.0, *)) {
				authorized = authorized || (status == PHAuthorizationStatusLimited);
			}
			if (!authorized) {
				[self showErrorAlertWithTitle:_(@"No Photos Access")
				                        message:_(@"Allow photo library access in Settings to save downloads.")
				              presentingController:strongPresenter];
				completion();
				return;
			}
			__block BOOL cancelled = NO;
			UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Downloading")
			                                                                 message:@""
			                                                          preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel")
			                                           style:UIAlertActionStyleCancel
			                                         handler:^(UIAlertAction *_Nonnull action) {
				cancelled = YES;
			}]];
			[strongPresenter presentViewController:alert animated:YES completion:nil];
			[self downloadNext:assets
			             index:0
			          failures:0
			             alert:alert
			       isCancelled:^BOOL { return cancelled; }
			presentingController:strongPresenter
			          completion:completion];
		});
	};
	if (@available(iOS 14.0, *)) {
		[PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:handler];
	} else {
		[PHPhotoLibrary requestAuthorization:handler];
	}
}

+ (void)downloadNext:(NSArray<IMAsset *> *)assets
               index:(NSUInteger)index
            failures:(NSUInteger)failures
               alert:(UIAlertController *)alert
         isCancelled:(BOOL (^)(void))isCancelled
presentingController:(UIViewController *)presenter
          completion:(void (^)(void))completion {
	if (isCancelled()) {
		completion();
		return;
	}
	if (index >= assets.count) {
		[alert dismissViewControllerAnimated:YES
		                           completion:^{
			    if (failures > 0) {
				    [self showErrorAlertWithTitle:_(@"Some Downloads Failed")
				                            message:[NSString stringWithFormat:_(@"%ld of %ld items couldn't be saved."), (long)failures, (long)assets.count]
				                  presentingController:presenter];
			    }
			    completion();
		    }];
		return;
	}

	alert.message = [NSString stringWithFormat:_(@"Saving %ld of %ld…"), (long)(index + 1), (long)assets.count];

	IMAsset *asset = assets[index];
	UIAlertController *presentedAlert = alert;
	[IMAssetApi originalDataForAssetId:asset.assetId
	                        completion:^(NSData *_Nullable data, NSError *_Nullable error) {
		    if (isCancelled()) {
			    completion();
			    return;
		    }
		    if (!data) {
			    [self downloadNext:assets
			                 index:index + 1
			              failures:failures + 1
			                 alert:presentedAlert
			           isCancelled:isCancelled
			  presentingController:presenter
			            completion:completion];
			    return;
		    }
		    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
			    PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
			    PHAssetResourceType resourceType = asset.isImage ? PHAssetResourceTypePhoto : PHAssetResourceTypeVideo;
			    [request addResourceWithType:resourceType data:data options:nil];
		    }
			                                       completionHandler:^(BOOL success, NSError *_Nullable saveError) {
				    dispatch_async(dispatch_get_main_queue(), ^{
					    [self downloadNext:assets
					                 index:index + 1
					              failures:failures + (success ? 0 : 1)
					                 alert:presentedAlert
					           isCancelled:isCancelled
					  presentingController:presenter
					            completion:completion];
				    });
			    }];
	    }];
}

#pragma mark - Add to album

+ (void)presentAddToAlbumForAssets:(NSArray<IMAsset *> *)assets presentingController:(UIViewController *)presenter {
	AddToAlbumViewController *picker = [AddToAlbumViewController pickerForAssetIds:[self idsForAssets:assets]];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
	[presenter presentViewController:nav animated:YES completion:nil];
}

@end
