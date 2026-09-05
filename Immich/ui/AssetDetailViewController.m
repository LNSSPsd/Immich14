#import "AssetDetailViewController.h"
#import "IMAssetApi.h"
#import "IMAssetManagementApi.h"
#import "IMApiClient.h"
#import "IMFaceApi.h"
#import "AssetFacesViewController.h"
#import "AssetMetadataEditorViewController.h"
#import "IMTagApi.h"
#import "common.h"

@interface AssetDetailSection : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<NSString *> *rows;
@end
@implementation AssetDetailSection
@end

@interface AssetDetailViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) NSArray<AssetDetailSection *> *sections;
@property (nonatomic, strong, nullable) IMAssetDetail *detail;
@property (nonatomic, strong, nullable) NSDictionary *rawDetail;
@property (nonatomic, strong, nullable) NSArray<NSString *> *ocrTexts;
@property (nonatomic) BOOL detailLoaded;
@property (nonatomic) BOOL ocrLoaded;
@property (nonatomic) BOOL tagControlsBusy;
@property (nonatomic) BOOL operationBusy;
@property (nonatomic, strong) UIBarButtonItem *operationsButton;
@end

@implementation AssetDetailViewController

+ (instancetype)detailViewControllerForAssetId:(NSString *)assetId {
	AssetDetailViewController *vc = [[AssetDetailViewController alloc] init];
	vc.assetId = assetId;
	vc.sections = @[];
	return vc;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Info");
	UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                                                                          target:self
	                                                                          action:@selector(doneTapped)];
	UIBarButtonItem *edit = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
	                                                                          target:self
	                                                                          action:@selector(editTapped)];
	edit.enabled = NO;
	UIBarButtonItem *tags = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"tag"] style:UIBarButtonItemStylePlain target:self action:@selector(tagsTapped)];
	tags.accessibilityLabel = _(@"Manage Tags");
	tags.enabled = NO;
	UIBarButtonItem *faces = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"person.2"] style:UIBarButtonItemStylePlain target:self action:@selector(facesTapped)];
	faces.accessibilityLabel = _(@"Manage Faces");
	faces.enabled = NO;
	self.operationsButton = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
	                                                          style:UIBarButtonItemStylePlain
	                                                         target:self
	                                                         action:@selector(operationsTapped)];
	self.operationsButton.accessibilityLabel = _(@"Asset operations");
	self.operationsButton.enabled = NO;
	self.navigationItem.rightBarButtonItems = @[ done, edit, tags, faces, self.operationsButton ];
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	}

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	[self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
	[self.view addSubview:self.tableView];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.spinner];

	self.errorLabel = [[UILabel alloc] init];
	self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.errorLabel.text = _(@"Couldn't load info. Tap to retry.");
	self.errorLabel.textAlignment = NSTextAlignmentCenter;
	if (@available(iOS 13.0, *)) {
		self.errorLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.errorLabel.textColor = UIColor.grayColor;
	}
	self.errorLabel.numberOfLines = 0;
	self.errorLabel.hidden = YES;
	self.errorLabel.userInteractionEnabled = YES;
	[self.errorLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(loadData)]];
	[self.view addSubview:self.errorLabel];

	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

		[self.errorLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.errorLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.errorLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
	]];

	[self loadData];
}

- (void)loadData {
	self.errorLabel.hidden = YES;
	[self.spinner startAnimating];
	self.detailLoaded = NO;
	self.ocrLoaded = NO;
	[self setTagControlsBusy:YES];
	__weak typeof(self) weakSelf = self;
	NSString *path = [NSString stringWithFormat:@"/assets/%@", self.assetId];
	[[IMApiClient shared] GET:path
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    NSDictionary *dict = [json isKindOfClass:[NSDictionary class]] ? json : nil;
		    weakSelf.rawDetail = dict;
		    weakSelf.detail = dict ? [[IMAssetDetail alloc] initWithDictionary:dict] : nil;
		    weakSelf.detailLoaded = YES;
		    [weakSelf rebuildSectionsIfReady];
	    }];
	[IMAssetApi ocrLinesForAssetId:self.assetId
	                     completion:^(NSArray<IMOcrLine *> *_Nullable lines, NSError *_Nullable error) {
		    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:lines.count];
		    for (IMOcrLine *line in lines) {
			    [texts addObject:line.text];
		    }
		    weakSelf.ocrTexts = texts;
		    weakSelf.ocrLoaded = YES;
		    [weakSelf rebuildSectionsIfReady];
	    }];
}

- (void)rebuildSectionsIfReady {
	if (!self.detailLoaded || !self.ocrLoaded) {
		return;
	}
	[self.spinner stopAnimating];
	[self setTagControlsBusy:NO];
	if (!self.detail && self.sections.count == 0) {
		self.errorLabel.hidden = NO; 
		return;
	}

	NSMutableArray<AssetDetailSection *> *sections = [NSMutableArray array];
	IMAssetDetail *detail = self.detail;
	if (detail) {
		NSMutableArray<NSString *> *infoRows = [NSMutableArray array];
		[infoRows addObject:[NSString stringWithFormat:_(@"File: %@"), detail.originalFileName]];
		if (detail.fileCreatedAt.length > 0) {
			[infoRows addObject:[NSString stringWithFormat:_(@"Date: %@"), [self formattedDate:detail.fileCreatedAt]]];
		}
		[infoRows addObject:[NSString stringWithFormat:_(@"Dimensions: %ld x %ld"), (long)detail.width, (long)detail.height]];
		id exifValue = self.rawDetail[@"exifInfo"];
		NSDictionary *exif = [exifValue isKindOfClass:[NSDictionary class]] ? exifValue : nil;
		NSNumber *fileSize = [exif[@"fileSizeInByte"] isKindOfClass:[NSNumber class]] ? exif[@"fileSizeInByte"] : nil;
		if (fileSize) {
			[infoRows addObject:[NSString stringWithFormat:_(@"Size: %@"),
			                                               [NSByteCountFormatter stringFromByteCount:fileSize.longLongValue
			                                                                              countStyle:NSByteCountFormatterCountStyleFile]]];
		}
		NSNumber *durationMs = [self.rawDetail[@"duration"] isKindOfClass:[NSNumber class]] ? self.rawDetail[@"duration"] : nil;
		if (durationMs.integerValue > 0) {
			[infoRows addObject:[NSString stringWithFormat:_(@"Duration: %@"), [self formattedDurationMs:durationMs.integerValue]]];
		}
		[sections addObject:[self sectionWithTitle:_(@"Info") rows:infoRows]];

		NSMutableArray<NSString *> *cameraRows = [NSMutableArray array];
		if (detail.cameraMake.length > 0 || detail.cameraModel.length > 0) {
			[cameraRows addObject:[NSString stringWithFormat:@"%@ %@", detail.cameraMake ?: @"", detail.cameraModel ?: @""]];
		}
		if (detail.lensModel.length > 0) {
			[cameraRows addObject:[NSString stringWithFormat:_(@"Lens: %@"), detail.lensModel]];
		}
		if (detail.exposureTime.length > 0) {
			[cameraRows addObject:[NSString stringWithFormat:_(@"Exposure: %@"), detail.exposureTime]];
		}
		if (detail.fNumber) {
			[cameraRows addObject:[NSString stringWithFormat:_(@"Aperture: f/%.1f"), detail.fNumber.doubleValue]];
		}
		if (detail.iso) {
			[cameraRows addObject:[NSString stringWithFormat:_(@"ISO: %@"), detail.iso]];
		}
		if (detail.focalLength) {
			[cameraRows addObject:[NSString stringWithFormat:_(@"Focal Length: %.0fmm"), detail.focalLength.doubleValue]];
		}
		if (cameraRows.count > 0) {
			[sections addObject:[self sectionWithTitle:_(@"Camera") rows:cameraRows]];
		}

		NSMutableArray<NSString *> *locationParts = [NSMutableArray array];
		if (detail.city.length > 0) {
			[locationParts addObject:detail.city];
		}
		if (detail.state.length > 0) {
			[locationParts addObject:detail.state];
		}
		if (detail.country.length > 0) {
			[locationParts addObject:detail.country];
		}
		NSMutableArray<NSString *> *locationRows = [NSMutableArray array];
		if (locationParts.count > 0) {
			[locationRows addObject:[locationParts componentsJoinedByString:@", "]];
		}
		NSNumber *latitude = [exif[@"latitude"] isKindOfClass:[NSNumber class]] ? exif[@"latitude"] : nil;
		NSNumber *longitude = [exif[@"longitude"] isKindOfClass:[NSNumber class]] ? exif[@"longitude"] : nil;
		if (latitude && longitude) {
			[locationRows addObject:[NSString stringWithFormat:@"%.5f, %.5f", latitude.doubleValue, longitude.doubleValue]];
		}
		if (locationRows.count > 0) {
			[sections addObject:[self sectionWithTitle:_(@"Location") rows:locationRows]];
		}

		if (detail.exifDescription.length > 0) {
			[sections addObject:[self sectionWithTitle:_(@"Description") rows:@[ detail.exifDescription ]]];
		}
		if (detail.peopleNames.count > 0) {
			[sections addObject:[self sectionWithTitle:_(@"People") rows:detail.peopleNames]];
		}
		if (detail.tagNames.count > 0) {
			[sections addObject:[self sectionWithTitle:_(@"Tags") rows:detail.tagNames]];
		}
	}
	if (self.ocrTexts.count > 0) {
		[sections addObject:[self sectionWithTitle:_(@"Text Found") rows:self.ocrTexts]];
	}

	self.sections = sections;
	if (self.navigationItem.rightBarButtonItems.count > 1) {
		self.navigationItem.rightBarButtonItems[1].enabled = (self.rawDetail != nil);
		if (self.navigationItem.rightBarButtonItems.count > 2) self.navigationItem.rightBarButtonItems[2].enabled = (self.rawDetail != nil);
		if (self.navigationItem.rightBarButtonItems.count > 3) self.navigationItem.rightBarButtonItems[3].enabled = (self.rawDetail != nil);
		[self updateOperationButtonState];
	}
	[self.tableView reloadData];
}

- (AssetDetailSection *)sectionWithTitle:(NSString *)title rows:(NSArray<NSString *> *)rows {
	AssetDetailSection *section = [[AssetDetailSection alloc] init];
	section.title = title;
	section.rows = rows;
	return section;
}

- (NSString *)formattedDurationMs:(NSInteger)milliseconds {
	NSInteger totalSeconds = (milliseconds + 500) / 1000;
	NSInteger hours = totalSeconds / 3600;
	NSInteger minutes = (totalSeconds % 3600) / 60;
	NSInteger seconds = totalSeconds % 60;
	if (hours > 0) {
		return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
	}
	return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

- (NSString *)formattedDate:(NSString *)iso8601 {
	static NSDateFormatter *display;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		display = [[NSDateFormatter alloc] init];
		display.dateStyle = NSDateFormatterLongStyle;
		display.timeStyle = NSDateFormatterShortStyle;
	});
	NSDate *date = IMDateFromServerTimestamp(iso8601);
	return date ? [display stringFromDate:date] : iso8601;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.sections[section].rows.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.sections[section].title;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
	cell.textLabel.text = self.sections[indexPath.section].rows[indexPath.row];
	cell.textLabel.numberOfLines = 0;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	return cell;
}

- (void)doneTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)editTapped {
	if (!self.rawDetail) {
		return;
	}
	AssetMetadataEditorViewController *editor = [[AssetMetadataEditorViewController alloc] initWithAssetId:self.assetId
	                                                                                              initialValues:self.rawDetail];
	__weak typeof(self) weakSelf = self;
	editor.onSaved = ^{
		[weakSelf loadData];
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)tagsTapped {
	if (!self.rawDetail || self.tagControlsBusy) return;
	[self setTagControlsBusy:YES];
	__weak typeof(self) weakSelf = self;
	[IMTagApi allTagsWithCompletion:^(NSArray<IMTag *> *tags, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			AssetDetailViewController *self = weakSelf;
			if (!self) return;
			if (error) {
				[self setTagControlsBusy:NO];
				UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Tags") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
				[self presentViewController:alert animated:YES completion:nil];
				return;
			}
			UIAlertController *picker = [UIAlertController alertControllerWithTitle:_(@"Manage Tags") message:tags.count ? nil : _(@"Create a tag in Settings → Tags first.") preferredStyle:UIAlertControllerStyleActionSheet];
			NSArray *rawTags = [self.rawDetail[@"tags"] isKindOfClass:[NSArray class]] ? self.rawDetail[@"tags"] : @[];
			NSMutableSet *appliedIds = [NSMutableSet set];
			for (id item in rawTags) if ([item isKindOfClass:[NSDictionary class]] && [item[@"id"] isKindOfClass:[NSString class]]) [appliedIds addObject:item[@"id"]];
			for (IMTag *tag in tags) {
				if (!tag.tagId.length) continue;
				BOOL applied = [appliedIds containsObject:tag.tagId];
				NSString *title = [NSString stringWithFormat:applied ? _(@"Remove %@") : _(@"Add %@"), tag.value.length ? tag.value : tag.name];
				[picker addAction:[UIAlertAction actionWithTitle:title style:applied ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
					NSArray *ids = @[ self.assetId ];
					void (^done)(NSError *) = ^(NSError *requestError) {
						dispatch_async(dispatch_get_main_queue(), ^{
							if (requestError) {
								[self setTagControlsBusy:NO];
								UIAlertController *failure = [UIAlertController alertControllerWithTitle:_(@"Tags") message:requestError.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
								[failure addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
								[self presentViewController:failure animated:YES completion:nil];
							} else {
								[self loadData];
							}
						});
					};
					if (applied) [IMTagApi untagId:tag.tagId assetIds:ids completion:done];
					else [IMTagApi tagId:tag.tagId assetIds:ids completion:done];
				}]];
			}
			[picker addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { [self setTagControlsBusy:NO]; }]];
			if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
				picker.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.count > 2 ? self.navigationItem.rightBarButtonItems[2] : nil;
			}
			[self presentViewController:picker animated:YES completion:nil];
		});
	}];
}

- (void)facesTapped {
	if (!self.rawDetail || self.tagControlsBusy || self.assetId.length == 0) return;
	AssetFacesViewController *faces = [[AssetFacesViewController alloc] initWithAssetId:self.assetId];
	[self.navigationController pushViewController:faces animated:YES];
}

#pragma mark - Asset operations

- (void)operationsTapped {
	if (!self.rawDetail || self.operationBusy) {
		return;
	}
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Asset operations")
	                                                                    message:nil
	                                                             preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Copy metadata to another asset")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
		dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf presentCopyTargetPrompt];
			});
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Run an asset job")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *action) {
		dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf presentAssetJobPicker];
			});
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) {
		sheet.popoverPresentationController.barButtonItem = self.operationsButton;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentCopyTargetPrompt {
	if (!self.rawDetail || self.operationBusy) {
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Copy asset metadata")
	                                                                     message:_(@"Enter the UUID of the target asset. Albums, favorite state, shared links, sidecar, and stack associations will be copied.")
	                                                              preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Target asset UUID");
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
		field.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		AssetDetailViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *target = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		[strongSelf setOperationBusy:YES];
		[IMAssetManagementApi copyAssetFromId:strongSelf.assetId
		                          toAssetId:target
		                            options:@{ @"albums": @YES, @"favorite": @YES, @"sharedLinks": @YES, @"sidecar": @YES, @"stack": @YES }
		                         completion:^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[strongSelf setOperationBusy:NO];
				if (!success) {
					[strongSelf showOperationError:error title:_(@"Couldn't copy asset metadata")];
					return;
				}
				[strongSelf showOperationMessage:_(@"Asset metadata copied.") title:_(@"Copy complete")];
			});
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)presentAssetJobPicker {
	if (!self.rawDetail || self.operationBusy) {
		return;
	}
	NSArray<NSDictionary *> *jobs = @[
		@{ @"name": IMAssetJobNameRefreshFaces, @"title": _(@"Refresh faces") },
		@{ @"name": IMAssetJobNameRefreshMetadata, @"title": _(@"Refresh metadata") },
		@{ @"name": IMAssetJobNameRegenerateThumbnail, @"title": _(@"Regenerate thumbnail") },
		@{ @"name": IMAssetJobNameTranscodeVideo, @"title": _(@"Transcode video") },
	];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Run asset job") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *job in jobs) {
		[sheet addAction:[UIAlertAction actionWithTitle:job[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			AssetDetailViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			[strongSelf setOperationBusy:YES];
			[IMAssetManagementApi runAssetJobNamed:job[@"name"] forAssetIds:@[ strongSelf.assetId ] completion:^(BOOL success, NSError *error) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[strongSelf setOperationBusy:NO];
					if (!success) {
						[strongSelf showOperationError:error title:_(@"Couldn't queue asset job")];
						return;
					}
					[strongSelf showOperationMessage:_(@"The job was queued on the server.") title:_(@"Job queued")];
				});
			}];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	if (sheet.popoverPresentationController) sheet.popoverPresentationController.barButtonItem = self.operationsButton;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)setOperationBusy:(BOOL)busy {
	_operationBusy = busy;
	[self updateOperationButtonState];
}

- (void)updateOperationButtonState {
	self.operationsButton.enabled = self.rawDetail != nil && !self.operationBusy && !self.tagControlsBusy;
}

- (void)showOperationError:(NSError *)error title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
	                                                                    message:error.localizedDescription ?: _(@"The server rejected this operation.")
	                                                             preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showOperationMessage:(NSString *)message title:(NSString *)title {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)setTagControlsBusy:(BOOL)busy {
	_tagControlsBusy = busy;
	if (self.navigationItem.rightBarButtonItems.count > 2) self.navigationItem.rightBarButtonItems[2].enabled = !busy && self.rawDetail != nil;
	[self updateOperationButtonState];
}

@end
