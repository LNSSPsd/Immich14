#import "AddToAlbumViewController.h"
#import "IMAlbumApi.h"
#import "common.h"

static NSString *const kNewAlbumCellId = @"newAlbum";
static NSString *const kAlbumCellId = @"album";

@interface AddToAlbumViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSArray<NSString *> *assetIds;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, copy) NSArray<IMAlbum *> *albums;
@end

@implementation AddToAlbumViewController

+ (instancetype)pickerForAssetId:(NSString *)assetId {
	return [self pickerForAssetIds:@[ assetId ]];
}

+ (instancetype)pickerForAssetIds:(NSArray<NSString *> *)assetIds {
	AddToAlbumViewController *vc = [[AddToAlbumViewController alloc] init];
	vc.assetIds = assetIds;
	vc.albums = @[];
	return vc;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Add to Album");
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                       target:self
	                                                                                       action:@selector(cancelTapped)];
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	}

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	[self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kNewAlbumCellId];
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
	[IMAlbumApi allAlbumsWithCompletion:^(NSArray<IMAlbum *> *_Nullable albums, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[strongSelf.spinner stopAnimating];
		strongSelf.albums = albums ?: @[];
		[strongSelf.tableView reloadData];
	}];
}

- (void)cancelTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Adding

- (void)addToAlbumId:(NSString *)albumId {
	[IMAlbumApi addAssetIds:self.assetIds
	              toAlbumId:albumId
	             completion:^(BOOL success, NSError *_Nullable error) {
	    }];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)newAlbumTapped {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"New Album")
	                                                                 message:nil
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.placeholder = _(@"Album name");
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Create")
	                                           style:UIAlertActionStyleDefault
	                                         handler:^(UIAlertAction *_Nonnull action) {
		    NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		    if (name.length == 0) {
			    return;
		    }
		    [IMAlbumApi createAlbumWithName:name
		                          completion:^(IMAlbum *_Nullable album, NSError *_Nullable error) {
			        if (album) {
				        [weakSelf addToAlbumId:album.albumId];
			        }
		        }];
	    }]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 1 : self.albums.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kNewAlbumCellId forIndexPath:indexPath];
		cell.textLabel.text = _(@"New Album");
		if (@available(iOS 13.0, *)) {
			cell.textLabel.textColor = UIColor.systemBlueColor;
			cell.imageView.image = [UIImage systemImageNamed:@"plus.circle"];
		}
		return cell;
	}
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAlbumCellId];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kAlbumCellId];
	}
	IMAlbum *album = self.albums[indexPath.row];
	cell.textLabel.text = album.name;
	cell.detailTextLabel.text = [NSString stringWithFormat:_(@"%ld"), (long)album.assetCount];
	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0) {
		[self newAlbumTapped];
		return;
	}
	[self addToAlbumId:self.albums[indexPath.row].albumId];
}

@end
