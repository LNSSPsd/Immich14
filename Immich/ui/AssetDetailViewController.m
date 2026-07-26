#import "AssetDetailViewController.h"
#import "IMAssetApi.h"
#import "IMApiClient.h"
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
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
	                                                                                        target:self
	                                                                                        action:@selector(doneTapped)];
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

@end
