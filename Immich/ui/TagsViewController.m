#import "TagsViewController.h"
#import "IMTagApi.h"
#import "IMSearchApi.h"
#import "AssetGridViewController.h"
#import "common.h"

@interface TagsViewController ()
@property (nonatomic, copy) NSArray<IMTag *> *tags;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic) BOOL loading;
@property (nonatomic, strong) NSURLSessionTask *assetTask;
@end

@implementation TagsViewController

- (void)dealloc { [_assetTask cancel]; }

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.assetTask cancel];
	self.assetTask = nil;
	self.navigationItem.rightBarButtonItem.enabled = YES;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Tags");
	self.tags = @[];
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reloadTags) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createTag)];
	self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyLabel.text = _(@"No tags yet. Tap + to create one.");
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	self.tableView.backgroundView = self.emptyLabel;
	[self reloadTags];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.tags.count) [self reloadTags];
}

- (void)reloadTags {
	if (self.loading) return;
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	[IMTagApi allTagsWithCompletion:^(NSArray<IMTag *> *tags, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			TagsViewController *self = weakSelf;
			if (!self) return;
			self.loading = NO;
			[self.refresh endRefreshing];
			if (error) { [self showError:error]; return; }
			self.tags = tags ?: @[];
			self.emptyLabel.hidden = self.tags.count != 0;
			[self.tableView reloadData];
		});
	}];
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server rejected this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Tags") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)createTag {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Create Tag") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Tag name"); field.autocapitalizationType = UITextAutocapitalizationTypeWords; }];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = _(@"Color (optional, e.g. #5AC8FA)"); field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters; }];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Create") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *name = [alert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *color = [alert.textFields[1].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!name.length) return;
		[IMTagApi createTagNamed:name color:color.length ? color : nil completion:^(IMTag *tag, NSError *error) {
			if (error || !tag) { dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showError:error]; }); return; }
			[weakSelf reloadTags];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.tags.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"tag-cell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	IMTag *tag = self.tags[indexPath.row];
	cell.textLabel.text = tag.name.length ? tag.name : tag.value;
	cell.detailTextLabel.text = tag.value.length && ![tag.value isEqualToString:tag.name] ? tag.value : _(@"Tap to browse photos");
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	if (tag.color.length) {
		unsigned int rgb = 0;
		NSScanner *scanner = [NSScanner scannerWithString:[tag.color hasPrefix:@"#"] ? [tag.color substringFromIndex:1] : tag.color];
		[scanner scanHexInt:&rgb];
		cell.imageView.image = [self swatchForColor:[UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1.0]];
	} else {
		cell.imageView.image = [self swatchForColor:UIColor.systemBlueColor];
	}
	return cell;
}

- (UIImage *)swatchForColor:(UIColor *)color {
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 0);
	[color setFill];
	UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1, 1, 22, 22) cornerRadius:5];
	[path fill];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.assetTask) return;
	IMTag *tag = self.tags[indexPath.row];
	[self.navigationItem.rightBarButtonItem setEnabled:NO];
	__weak typeof(self) weakSelf = self;
	self.assetTask = [IMSearchApi metadataSearchWithTagId:tag.tagId page:1 completion:^(NSArray<IMAsset *> *assets, NSString *nextPage, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			TagsViewController *self = weakSelf;
			if (!self) return;
			self.assetTask = nil;
			[self.navigationItem.rightBarButtonItem setEnabled:YES];
			if (self.navigationController.topViewController != self) return;
			if (error) { [self showError:error]; return; }
			AssetGridViewController *grid = [AssetGridViewController gridWithTitle:tag.value.length ? tag.value : tag.name assets:assets ?: @[]];
			grid.nextPageToken = nextPage;
			grid.pageLoader = ^NSURLSessionTask *(NSInteger page, void (^completion)(NSArray<IMAsset *> *, NSString *, NSError *)) {
				return [IMSearchApi metadataSearchWithTagId:tag.tagId page:page completion:completion];
			};
			[self.navigationController pushViewController:grid animated:YES];
		});
	}];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete) return;
	IMTag *tag = self.tags[indexPath.row];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete Tag?") message:tag.name preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[IMTagApi deleteTagId:tag.tagId completion:^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{ if (!success || error) [weakSelf showError:error]; else [weakSelf reloadTags]; });
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}
@end
