#import "IMBulkAssetActions.h"
#import "IMAssetApi.h"
#import "IMAssetManagementApi.h"
#import "IMApiClient.h"
#import "IMDownloadApi.h"
#import "IMDownloadArchiveInfo.h"
#import "IMStackApi.h"
#import "IMTagApi.h"
#import "AddToAlbumViewController.h"
#import "common.h"
#import <Photos/Photos.h>

@interface IMBulkTagPickerController : UITableViewController
@property (nonatomic, copy) NSArray<IMTag *> *tags;
@property (nonatomic, copy) NSArray<NSString *> *assetIds;
@property (nonatomic, copy, nullable) void (^resultCompletion)(BOOL success);
@property (nonatomic) BOOL submitting;
@property (nonatomic) BOOL completionDelivered;
- (instancetype)initWithTags:(NSArray<IMTag *> *)tags
                     assetIds:(NSArray<NSString *> *)assetIds
                   completion:(nullable void (^)(BOOL success))completion;
@end

@interface IMBulkAssetActions ()
+ (void)saveAssetsToPhotos:(NSArray<IMAsset *> *)assets
      presentingController:(UIViewController *)presenter
                 completion:(void (^)(void))completion;
+ (void)downloadArchiveAssets:(NSArray<IMAsset *> *)assets
         presentingController:(UIViewController *)presenter
                    completion:(void (^)(void))completion;
@end

@implementation IMBulkTagPickerController

- (instancetype)initWithTags:(NSArray<IMTag *> *)tags
                     assetIds:(NSArray<NSString *> *)assetIds
                   completion:(void (^)(BOOL success))completion {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_tags = [tags copy];
		_assetIds = [assetIds copy];
		_resultCompletion = [completion copy];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Add Tags");
	self.tableView.allowsMultipleSelection = YES;
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                         target:self
	                                                                                         action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Apply")
	                                                                               style:UIBarButtonItemStyleDone
	                                                                              target:self
	                                                                              action:@selector(applyTapped)];
	self.navigationItem.rightBarButtonItem.enabled = NO;
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server rejected this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Add Tags")
	                                                                     message:message
	                                                              preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deliverCompletion:(BOOL)success {
	if (self.completionDelivered) return;
	self.completionDelivered = YES;
	void (^completion)(BOOL) = self.resultCompletion;
	self.resultCompletion = nil;
	if (completion) completion(success);
}

- (void)cancelTapped {
	[self deliverCompletion:NO];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)applyTapped {
	if (self.submitting) return;
	NSArray<NSIndexPath *> *selected = self.tableView.indexPathsForSelectedRows;
	if (selected.count == 0) {
		[self showError:[NSError errorWithDomain:IMApiErrorDomain
		                                    code:1
		                                userInfo:@{ NSLocalizedDescriptionKey: _(@"Choose at least one tag.") }]];
		return;
	}
	NSMutableArray<NSString *> *tagIds = [NSMutableArray arrayWithCapacity:selected.count];
	for (NSIndexPath *indexPath in selected) {
		if (indexPath.row >= 0 && indexPath.row < (NSInteger)self.tags.count) {
			NSString *tagId = self.tags[indexPath.row].tagId;
			if (tagId.length > 0 && ![tagIds containsObject:tagId]) [tagIds addObject:tagId];
		}
	}
	if (tagIds.count == 0 || self.assetIds.count == 0) {
		[self showError:[NSError errorWithDomain:IMApiErrorDomain
		                                    code:1
		                                userInfo:@{ NSLocalizedDescriptionKey: _(@"Choose at least one tag and photo.") }]];
		return;
	}
	self.submitting = YES;
	self.navigationItem.leftBarButtonItem.enabled = NO;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMTagApi bulkTagIds:tagIds assetIds:self.assetIds completion:^(NSInteger count, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			IMBulkTagPickerController *strongSelf = weakSelf;
			if (!strongSelf) return;
			(void)count;
			strongSelf.submitting = NO;
			if (error) {
				strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
				[strongSelf showError:error];
				[strongSelf deliverCompletion:NO];
				return;
			}
			[strongSelf dismissViewControllerAnimated:YES completion:^{
				[strongSelf deliverCompletion:YES];
			}];
		} );
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.tags.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"bulk-tag-cell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	IMTag *tag = self.tags[indexPath.row];
	cell.textLabel.text = tag.value.length ? tag.value : tag.name;
	cell.detailTextLabel.text = tag.value.length && tag.name.length && ![tag.value isEqualToString:tag.name] ? tag.name : nil;
	cell.accessoryType = [tableView.indexPathsForSelectedRows containsObject:indexPath] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryCheckmark;
	self.navigationItem.rightBarButtonItem.enabled = YES;
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryNone;
	self.navigationItem.rightBarButtonItem.enabled = tableView.indexPathsForSelectedRows.count > 0;
}

@end

@implementation IMBulkAssetActions

+ (NSArray<NSString *> *)idsForAssets:(NSArray<IMAsset *> *)assets {
	NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:assets.count];
	for (IMAsset *asset in assets) {
		NSString *assetId = asset.assetId;
		if ([assetId isKindOfClass:[NSString class]] && assetId.length > 0 && ![ids containsObject:assetId]) {
			[ids addObject:assetId];
		}
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
	if (![assets isKindOfClass:[NSArray class]] || assets.count == 0) {
		if (completion) completion();
		return;
	}
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Download")
	                                                                 message:[NSString stringWithFormat:_(@"%ld selected item%@"),
	                                                                                                     (long)assets.count,
	                                                                                                     assets.count == 1 ? @"" : @"s"]
	                                                          preferredStyle:UIAlertControllerStyleActionSheet];
	__weak UIViewController *weakPresenter = presenter;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Save to Photos")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
		UIViewController *strongPresenter = weakPresenter;
		if (!strongPresenter) return;
		[self saveAssetsToPhotos:assets presentingController:strongPresenter completion:completion];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Download ZIP")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
		UIViewController *strongPresenter = weakPresenter;
		if (!strongPresenter) return;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self downloadArchiveAssets:assets presentingController:strongPresenter completion:completion];
		});
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.sourceView = presenter.view;
		sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds),
		                                                            CGRectGetMaxY(presenter.view.bounds) - 1,
		                                                            1,
		                                                            1);
	}
	[presenter presentViewController:sheet animated:YES completion:nil];
}

+ (void)saveAssetsToPhotos:(NSArray<IMAsset *> *)assets
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

+ (void)downloadArchiveAssets:(NSArray<IMAsset *> *)assets
	         presentingController:(UIViewController *)presenter
	                    completion:(void (^)(void))completion {
	NSArray<NSString *> *assetIds = [self idsForAssets:assets];
	if (assetIds.count == 0) {
		[self showErrorAlertWithTitle:_(@"Couldn't Download")
		                        message:_(@"Select at least one valid server asset.")
		          presentingController:presenter];
		if (completion) completion();
		return;
	}

	NSString *directoryName = [NSString stringWithFormat:@"ImmichDownload-%@", NSUUID.UUID.UUIDString];
	NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:directoryName]
	                               isDirectory:YES];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if (![fileManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:NULL]) {
		[self showErrorAlertWithTitle:_(@"Couldn't Download")
		                        message:_(@"A temporary download folder could not be created.")
		          presentingController:presenter];
		if (completion) completion();
		return;
	}

	UIAlertController *progress = [UIAlertController alertControllerWithTitle:_(@"Preparing Download")
	                                                                      message:_(@"Requesting archive information…")
	                                                               preferredStyle:UIAlertControllerStyleAlert];
	__block BOOL cancelled = NO;
	__block BOOL finished = NO;
	__block NSURLSessionTask *currentTask = nil;
	__block void (^downloadNext)(NSUInteger) = nil;
	NSMutableArray<NSURL *> *files = [NSMutableArray array];
	__weak UIViewController *weakPresenter = presenter;

	void (^finish)(NSError *) = ^(NSError *error) {
		if (finished) return;
		finished = YES;
		currentTask = nil;
		downloadNext = nil;
		UIViewController *strongPresenter = weakPresenter;
		if (cancelled || error || files.count == 0 || !strongPresenter) {
			[fileManager removeItemAtURL:directory error:NULL];
			void (^finishOnMain)(void) = ^{
				if (error && strongPresenter) {
					[self showErrorAlertWithTitle:_(@"Couldn't Download")
					                        message:error.localizedDescription
					          presentingController:strongPresenter];
				}
				if (completion) completion();
			};
			if (strongPresenter && progress.presentingViewController == strongPresenter) {
				[progress dismissViewControllerAnimated:YES completion:finishOnMain];
			} else {
				finishOnMain();
			}
			return;
		}
		[progress dismissViewControllerAnimated:YES completion:^{
			UIViewController *presenterForShare = weakPresenter;
			if (!presenterForShare) {
				[fileManager removeItemAtURL:directory error:NULL];
				if (completion) completion();
				return;
			}
			UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:files
			                                                                        applicationActivities:nil];
			activity.completionWithItemsHandler = ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
				[fileManager removeItemAtURL:directory error:NULL];
				if (completion) completion();
			};
			if (activity.popoverPresentationController) {
				activity.popoverPresentationController.sourceView = presenterForShare.view;
				activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenterForShare.view.bounds),
				                                                               CGRectGetMaxY(presenterForShare.view.bounds) - 1,
				                                                               1,
				                                                               1);
			}
			[presenterForShare presentViewController:activity animated:YES completion:nil];
		}];
	};

	[progress addAction:[UIAlertAction actionWithTitle:_(@"Cancel")
	                                           style:UIAlertActionStyleCancel
	                                         handler:^(UIAlertAction *action) {
		cancelled = YES;
		[currentTask cancel];
		finish(nil);
	}]];
	[presenter presentViewController:progress animated:YES completion:nil];

	currentTask = [IMDownloadApi downloadInfoForAssetIds:assetIds
	                                          archiveSize:nil
	                                           completion:^(IMDownloadResponseDto *_Nullable response, NSError *_Nullable error) {
		if (cancelled || finished) return;
		if (error || !response || response.archives.count == 0) {
			NSError *failure = error ?: [NSError errorWithDomain:IMApiErrorDomain
			                                                code:2
			                                            userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned no downloadable files.")}];
			finish(failure);
			return;
		}
		progress.title = _(@"Downloading");
		progress.message = [NSString stringWithFormat:_(@"Archive 1 of %ld…"), (long)response.archives.count];
		NSUInteger archiveCount = response.archives.count;
		downloadNext = ^(NSUInteger index) {
			if (cancelled || finished) return;
			if (index >= archiveCount) {
				finish(nil);
				return;
			}
			IMDownloadArchiveInfo *archive = response.archives[index];
			progress.message = [NSString stringWithFormat:_(@"Archive %ld of %ld…"), (long)(index + 1), (long)archiveCount];
			NSURL *destination = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"archive-%lu.zip", (unsigned long)(index + 1)]];
			currentTask = [IMDownloadApi downloadArchiveForAssetIds:archive.assetIds
			                                                  edited:NO
			                                                     key:nil
			                                                    slug:nil
			                                          destinationURL:destination
			                                              completion:^(NSURL *_Nullable fileURL, NSError *_Nullable archiveError) {
				if (cancelled || finished) return;
				if (archiveError || !fileURL) {
					finish(archiveError ?: [NSError errorWithDomain:IMApiErrorDomain
					                                             code:2
					                                         userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an empty archive.")}]);
					return;
				}
				[files addObject:fileURL];
				downloadNext(index + 1);
			}];
		};
		downloadNext(0);
	}];
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

+ (void)presentCreateStackForAssets:(NSArray<IMAsset *> *)assets
                presentingController:(UIViewController *)presenter
                           completion:(void (^)(BOOL success))completion {
	if (assets.count < 2) {
		[self showErrorAlertWithTitle:_(@"Select at least two photos") message:nil presentingController:presenter];
		if (completion) completion(NO);
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Create Stack?")
	                                                                 message:[NSString stringWithFormat:_(@"This will stack %ld selected items."), (long)assets.count]
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { if (completion) completion(NO); }]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Create") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSArray<NSString *> *ids = [self idsForAssets:assets];
		if (ids.count < 2) {
			[self showErrorAlertWithTitle:_(@"Couldn't Create Stack")
			                        message:_(@"Select at least two valid server assets.")
			          presentingController:presenter];
			if (completion) completion(NO);
			return;
		}
		[IMStackApi createStackWithAssetIds:ids completion:^(IMStack *stack, NSError *error) {
			if (!stack) [self showErrorAlertWithTitle:_(@"Couldn't Create Stack") message:error.localizedDescription presentingController:presenter];
			if (completion) completion(stack != nil);
		}];
	}]];
	[presenter presentViewController:alert animated:YES completion:nil];
}

+ (void)presentAssetJobPickerForAssets:(NSArray<IMAsset *> *)assets
                  presentingController:(UIViewController *)presenter
                             completion:(void (^)(BOOL success))completion {
	if (assets.count == 0) {
		if (completion) completion(NO);
		return;
	}
	NSArray<NSDictionary *> *jobs = @[
		@{ @"name": IMAssetJobNameRefreshFaces, @"title": _(@"Refresh faces") },
		@{ @"name": IMAssetJobNameRefreshMetadata, @"title": _(@"Refresh metadata") },
		@{ @"name": IMAssetJobNameRegenerateThumbnail, @"title": _(@"Regenerate thumbnails") },
		@{ @"name": IMAssetJobNameTranscodeVideo, @"title": _(@"Transcode videos") },
	];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Run asset job")
	                                                                    message:[NSString stringWithFormat:_(@"Queue a job for %ld selected item%@."),
	                                                                                                        (long)assets.count,
	                                                                                                        assets.count == 1 ? @"" : @"s"]
	                                                             preferredStyle:UIAlertControllerStyleActionSheet];
	__weak UIViewController *weakPresenter = presenter;
	for (NSDictionary *job in jobs) {
		[sheet addAction:[UIAlertAction actionWithTitle:job[@"title"]
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
			UIViewController *strongPresenter = weakPresenter;
			NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:assets.count];
			for (IMAsset *asset in assets) {
				if (asset.assetId.length > 0) [ids addObject:asset.assetId];
			}
			[IMAssetManagementApi runAssetJobNamed:job[@"name"]
			                         forAssetIds:ids
			                          completion:^(BOOL success, NSError *error) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (!success && strongPresenter) {
						[self showErrorAlertWithTitle:_(@"Couldn't queue asset job")
						                message:error.localizedDescription
						  presentingController:strongPresenter];
					}
					if (completion) completion(success);
				});
			}];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
		if (completion) completion(NO);
	}]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.sourceView = presenter.view;
		sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMaxY(presenter.view.bounds) - 1, 1, 1);
	}
	[presenter presentViewController:sheet animated:YES completion:nil];
}

+ (void)presentVisibilityPickerForAssets:(NSArray<IMAsset *> *)assets
                    presentingController:(UIViewController *)presenter
                               completion:(void (^)(BOOL success))completion {
	if (assets.count == 0) { if (completion) completion(NO); return; }
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Move Photos") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	NSArray<NSDictionary *> *choices = @[
		@{ @"title": _(@"Timeline"), @"value": @"timeline" },
		@{ @"title": _(@"Archive"), @"value": @"archive" },
		@{ @"title": _(@"Hidden"), @"value": @"hidden" },
		@{ @"title": _(@"Locked Photos"), @"value": @"locked" },
	];
	__weak typeof(presenter) weakPresenter = presenter;
	for (NSDictionary *choice in choices) {
		[sheet addAction:[UIAlertAction actionWithTitle:choice[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			UIViewController *strongPresenter = weakPresenter;
			[IMAssetManagementApi setVisibility:choice[@"value"] forAssetIds:[self idsForAssets:assets] completion:^(BOOL success, NSError *error) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (!success && strongPresenter) [self showErrorAlertWithTitle:_(@"Couldn't Move Photos") message:error.localizedDescription presentingController:strongPresenter];
					if (completion) completion(success);
				});
			}];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { if (completion) completion(NO); }]];
	if (sheet.popoverPresentationController) { sheet.popoverPresentationController.sourceView = presenter.view; sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMaxY(presenter.view.bounds)-1, 1, 1); }
	[presenter presentViewController:sheet animated:YES completion:nil];
}

+ (void)presentAddToAlbumForAssets:(NSArray<IMAsset *> *)assets presentingController:(UIViewController *)presenter {
	AddToAlbumViewController *picker = [AddToAlbumViewController pickerForAssetIds:[self idsForAssets:assets]];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
	[presenter presentViewController:nav animated:YES completion:nil];
}

+ (void)presentTagPickerForAssets:(NSArray<IMAsset *> *)assets
             presentingController:(UIViewController *)presenter
                        completion:(void (^)(BOOL success))completion {
	NSArray<NSString *> *assetIds = [self idsForAssets:assets];
	if (assetIds.count == 0) {
		[self showErrorAlertWithTitle:_(@"Couldn't Add Tags")
		                        message:_(@"Select at least one valid server asset.")
		          presentingController:presenter];
		if (completion) completion(NO);
		return;
	}
	__weak UIViewController *weakPresenter = presenter;
	[IMTagApi allTagsWithCompletion:^(NSArray<IMTag *> *tags, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *strongPresenter = weakPresenter;
			if (!strongPresenter) return;
			if (error) {
				[self showErrorAlertWithTitle:_(@"Couldn't Load Tags")
				                        message:error.localizedDescription
				          presentingController:strongPresenter];
				if (completion) completion(NO);
				return;
			}
			if (tags.count == 0) {
				[self showErrorAlertWithTitle:_(@"No Tags")
				                        message:_(@"Create a tag in Settings → Tags before adding one to photos.")
				          presentingController:strongPresenter];
				if (completion) completion(NO);
				return;
			}
			IMBulkTagPickerController *picker = [[IMBulkTagPickerController alloc] initWithTags:tags
			                                                                    assetIds:assetIds
			                                                                  completion:completion];
			UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:picker];
			navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
			[strongPresenter presentViewController:navigationController animated:YES completion:nil];
		});
	}];
}

@end
