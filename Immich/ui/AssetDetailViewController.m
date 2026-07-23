#import "AssetDetailViewController.h"
#import "IMAssetApi.h"
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
@property (nonatomic, strong) NSArray<AssetDetailSection *> *sections;
@property (nonatomic, strong, nullable) IMAssetDetail *detail;
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
	[self.spinner startAnimating];

	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	__weak typeof(self) weakSelf = self;
	[IMAssetApi assetDetailForAssetId:self.assetId
	                        completion:^(IMAssetDetail *_Nullable detail, NSError *_Nullable error) {
		    weakSelf.detail = detail;
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

	NSMutableArray<AssetDetailSection *> *sections = [NSMutableArray array];
	IMAssetDetail *detail = self.detail;
	if (detail) {
		NSMutableArray<NSString *> *infoRows = [NSMutableArray array];
		[infoRows addObject:[NSString stringWithFormat:_(@"File: %@"), detail.originalFileName]];
		if (detail.fileCreatedAt.length > 0) {
			[infoRows addObject:[NSString stringWithFormat:_(@"Date: %@"), [self formattedDate:detail.fileCreatedAt]]];
		}
		[infoRows addObject:[NSString stringWithFormat:_(@"Dimensions: %ld x %ld"), (long)detail.width, (long)detail.height]];
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
		if (locationParts.count > 0) {
			[sections addObject:[self sectionWithTitle:_(@"Location") rows:@[ [locationParts componentsJoinedByString:@", "] ]]];
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

- (NSString *)formattedDate:(NSString *)iso8601 {
	static NSISO8601DateFormatter *parser;
	static NSDateFormatter *display;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		parser = [[NSISO8601DateFormatter alloc] init];
		display = [[NSDateFormatter alloc] init];
		display.dateStyle = NSDateFormatterLongStyle;
		display.timeStyle = NSDateFormatterShortStyle;
	});
	NSDate *date = [parser dateFromString:iso8601];
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
