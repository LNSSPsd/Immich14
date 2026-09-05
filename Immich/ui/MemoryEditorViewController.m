#import "MemoryEditorViewController.h"
#import "IMMemoryApi.h"
#import "IMApiClient.h"
#import "common.h"
#import <math.h>

typedef NS_ENUM(NSInteger, IMMemoryEditorSection) {
	IMMemoryEditorSectionDetails = 0,
	IMMemoryEditorSectionAssets,
	IMMemoryEditorSectionCount,
};

typedef NS_ENUM(NSInteger, IMMemoryEditorDetailsRow) {
	IMMemoryEditorDetailsDate = 0,
	IMMemoryEditorDetailsYear,
	IMMemoryEditorDetailsSaved,
	IMMemoryEditorDetailsCount,
};

@interface MemoryEditorViewController ()
@property (nonatomic, strong, nullable) IMMemory *memory;
@property (nonatomic) BOOL creating;
@property (nonatomic, strong) UIDatePicker *datePicker;
@property (nonatomic, strong) UITextField *yearField;
@property (nonatomic, strong) UISwitch *savedSwitch;
@property (nonatomic, strong) UITextField *assetIDsField;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL saving;
@property (nonatomic, strong, nullable) NSError *lastError;
@end

static NSString *IMMemoryEditorISODate(NSDate *date) {
	static NSISO8601DateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSISO8601DateFormatter alloc] init];
		formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
	});
	return [formatter stringFromDate:date ?: [NSDate date]];
}

static NSArray<NSString *> *IMMemoryEditorIDsFromText(NSString *text) {
	if (![text isKindOfClass:[NSString class]] || text.length == 0) return @[];
	NSMutableArray<NSString *> *result = [NSMutableArray array];
	NSMutableSet<NSString *> *seen = [NSMutableSet set];
	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",;\n\t "];
	for (NSString *raw in [text componentsSeparatedByCharactersInSet:separators]) {
		NSString *value = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (value.length && ![seen containsObject:value]) {
			[seen addObject:value];
			[result addObject:value];
		}
	}
	return result;
}

@implementation MemoryEditorViewController

- (instancetype)initForCreate {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_creating = YES;
		self.title = _(@"New Memory");
	}
	return self;
}

- (instancetype)initWithMemory:(IMMemory *)memory {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_memory = memory;
		_creating = NO;
		self.title = _(@"Edit Memory");
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 52.0;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                         target:self
	                                                                                         action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
	                                                                                          target:self
	                                                                                          action:@selector(saveTapped)];

	self.datePicker = [[UIDatePicker alloc] init];
	self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
	if (@available(iOS 13.4, *)) self.datePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;
	NSDate *initialDate = self.memory.memoryAt ?: [NSDate date];
	self.datePicker.date = initialDate;
	self.datePicker.maximumDate = [NSDate dateWithTimeIntervalSinceNow:365.0 * 24.0 * 60.0 * 60.0];
	self.datePicker.minimumDate = [NSDate dateWithTimeIntervalSince1970:0];

	self.yearField = [[UITextField alloc] init];
	self.yearField.placeholder = _(@"Source year (1000–9999)");
	self.yearField.keyboardType = UIKeyboardTypeNumberPad;
	NSInteger defaultYear = self.memory.sourceYear >= 1000 && self.memory.sourceYear <= 9999
	    ? self.memory.sourceYear
	    : [[NSCalendar currentCalendar] component:NSCalendarUnitYear fromDate:initialDate];
	self.yearField.text = [NSString stringWithFormat:@"%ld", (long)defaultYear];
	self.yearField.clearButtonMode = UITextFieldViewModeWhileEditing;
	self.yearField.accessibilityLabel = _(@"Source year");

	self.savedSwitch = [[UISwitch alloc] init];
	self.savedSwitch.on = self.memory.isSaved;
	self.savedSwitch.accessibilityLabel = _(@"Save memory");

	self.assetIDsField = [[UITextField alloc] init];
	self.assetIDsField.placeholder = _(@"Asset IDs separated by commas");
	self.assetIDsField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.assetIDsField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.assetIDsField.clearButtonMode = UITextFieldViewModeWhileEditing;
	self.assetIDsField.accessibilityLabel = _(@"Memory asset IDs");
	NSMutableArray<NSString *> *existingIDs = [NSMutableArray arrayWithCapacity:self.memory.assets.count];
	for (IMAsset *asset in self.memory.assets) if (asset.assetId.length) [existingIDs addObject:asset.assetId];
	self.assetIDsField.text = [existingIDs componentsJoinedByString:@", "];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.hidden = YES;
	self.tableView.tableFooterView = self.statusLabel;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat width = CGRectGetWidth(self.tableView.bounds);
	if (width <= 0) return;
	CGFloat height = self.statusLabel.hidden ? 0 : 48;
	self.statusLabel.frame = CGRectMake(16, 8, MAX(1, width - 32), height);
	self.tableView.tableFooterView = self.statusLabel;
}

- (void)cancelTapped {
	if (self.saving) return;
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not save this memory.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Memory") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)setSaving:(BOOL)saving {
	_saving = saving;
	self.navigationItem.rightBarButtonItem.enabled = !saving;
	self.navigationItem.leftBarButtonItem.enabled = !saving;
	if (saving) [self.spinner startAnimating]; else [self.spinner stopAnimating];
}

- (void)saveTapped {
	if (self.saving) return;
	NSInteger year = self.yearField.text.integerValue;
	if (year < 1000 || year > 9999) {
		[self showError:[NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Enter a source year from 1000 to 9999.")}]];
		return;
	}
	NSString *memoryAt = IMMemoryEditorISODate(self.datePicker.date);
	NSArray<NSString *> *assetIDs = IMMemoryEditorIDsFromText(self.assetIDsField.text);
	self.saving = YES;
	self.statusLabel.hidden = YES;
	__weak typeof(self) weakSelf = self;
	if (self.creating) {
		[IMMemoryApi createMemoryWithType:@"on_this_day"
		                         dataYear:year
		                        memoryAt:memoryAt
		                        assetIds:assetIDs
		                        isSaved:@(self.savedSwitch.isOn)
		                         seenAt:nil
		                          showAt:nil
		                          hideAt:nil
		                      completion:^(IMMemory *memory, NSError *error) {
			[self finishSaveWithMemory:memory error:error weakSelf:weakSelf];
		}];
		return;
	}
	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	if (!self.memory.memoryAt || fabs([self.memory.memoryAt timeIntervalSinceDate:self.datePicker.date]) > 0.5) fields[@"memoryAt"] = memoryAt;
	if (self.memory.isSaved != self.savedSwitch.isOn) fields[@"isSaved"] = @(self.savedSwitch.isOn);
	NSArray<NSString *> *oldIDs = [self.memory.assets valueForKey:@"assetId"] ?: @[];
	NSMutableSet *oldSet = [NSMutableSet setWithArray:oldIDs];
	NSMutableSet *newSet = [NSMutableSet setWithArray:assetIDs];
	[oldSet minusSet:newSet];
	[newSet minusSet:[NSSet setWithArray:oldIDs]];
	NSArray<NSString *> *removed = [oldSet allObjects];
	NSArray<NSString *> *added = [newSet allObjects];
	[self updateMemoryFields:fields added:added removed:removed weakSelf:weakSelf];
}

- (void)finishSaveWithMemory:(IMMemory *)memory error:(NSError *)error weakSelf:(MemoryEditorViewController *)weakSelf {
	MemoryEditorViewController *strongSelf = weakSelf;
	if (!strongSelf) return;
	strongSelf.saving = NO;
	if (error || !memory) {
		strongSelf.statusLabel.hidden = NO;
		strongSelf.statusLabel.text = _(@"Couldn't save. Check the fields and try again.");
		[strongSelf showError:error];
		return;
	}
	if (strongSelf.onSaved) strongSelf.onSaved(memory);
	[strongSelf dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateMemoryFields:(NSDictionary<NSString *, id> *)fields
                  added:(NSArray<NSString *> *)added
                removed:(NSArray<NSString *> *)removed
               weakSelf:(MemoryEditorViewController *)weakSelf {
	void (^refresh)(void) = ^{
		[IMMemoryApi memoryWithId:weakSelf.memory.memoryId completion:^(IMMemory *memory, NSError *error) {
			[weakSelf finishSaveWithMemory:memory error:error weakSelf:weakSelf];
		}];
	};
	void (^removeThenAdd)(void) = ^{
		if (removed.count) {
			[IMMemoryApi removeAssetIds:removed fromMemoryId:weakSelf.memory.memoryId completion:^(BOOL success, NSError *error) {
				if (!success || error) { [weakSelf finishSaveWithMemory:nil error:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not remove memory photos.")} ] weakSelf:weakSelf]; return; }
				if (added.count) {
					[IMMemoryApi addAssetIds:added toMemoryId:weakSelf.memory.memoryId completion:^(BOOL addSuccess, NSError *addError) {
						if (!addSuccess || addError) { [weakSelf finishSaveWithMemory:nil error:addError ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not add memory photos.")} ] weakSelf:weakSelf]; return; }
						refresh();
					}];
				} else refresh();
			}];
		} else if (added.count) {
			[IMMemoryApi addAssetIds:added toMemoryId:weakSelf.memory.memoryId completion:^(BOOL success, NSError *error) {
				if (!success || error) { [weakSelf finishSaveWithMemory:nil error:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not add memory photos.")} ] weakSelf:weakSelf]; return; }
				refresh();
			}];
		} else refresh();
	};
	if (fields.count) {
		[IMMemoryApi updateMemoryId:weakSelf.memory.memoryId fields:fields completion:^(IMMemory *memory, NSError *error) {
			if (!memory || error) { [weakSelf finishSaveWithMemory:nil error:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not update memory details.")} ] weakSelf:weakSelf]; return; }
			removeThenAdd();
		}];
	} else removeThenAdd();
}

#pragma mark UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return IMMemoryEditorSectionCount; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == IMMemoryEditorSectionDetails ? IMMemoryEditorDetailsCount : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == IMMemoryEditorSectionDetails) return _(@"Memory details");
	return _(@"Photos");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == IMMemoryEditorSectionAssets) return _(@"Paste asset IDs from Photo Info, separated by commas. Photos are kept in your library when a memory is deleted.");
	return self.creating ? _(@"Memories currently use the server's on-this-day type.") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSString *identifier = [NSString stringWithFormat:@"memory-editor-%ld-%ld", (long)indexPath.section, (long)indexPath.row];
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryView = nil;
	if (indexPath.section == IMMemoryEditorSectionDetails) {
		switch (indexPath.row) {
			case IMMemoryEditorDetailsDate:
				cell.textLabel.text = _(@"Memory date");
				cell.accessoryView = self.datePicker;
				break;
			case IMMemoryEditorDetailsYear:
				cell.textLabel.text = _(@"Source year");
				cell.accessoryView = self.yearField;
				self.yearField.frame = CGRectMake(0, 0, 130, 36);
				break;
			case IMMemoryEditorDetailsSaved:
				cell.textLabel.text = _(@"Saved");
				cell.accessoryView = self.savedSwitch;
				break;
		}
	} else {
		cell.textLabel.text = nil;
		cell.textLabel.numberOfLines = 0;
		cell.accessoryView = self.assetIDsField;
		self.assetIDsField.frame = CGRectMake(0, 0, MAX(160, self.tableView.bounds.size.width - 32), 36);
	}
	return cell;
}

@end
