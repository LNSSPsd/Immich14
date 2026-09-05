#import "AddToAlbumViewController.h"
#import "IMAlbumApi.h"
#import "IMSession.h"
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
		NSMutableArray *editable = [NSMutableArray array];
		for (IMAlbum *album in albums) {
			NSString *role = [album roleForUserId:IMSession.shared.userId];
			if ([role isEqualToString:@"owner"] || [role isEqualToString:@"editor"]) [editable addObject:album];
		}
		strongSelf.albums = editable;
		[strongSelf.tableView reloadData];
	}];
}

- (void)cancelTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Adding

- (void)addToAlbum:(IMAlbum *)album {
	self.tableView.userInteractionEnabled = NO;
	self.navigationItem.leftBarButtonItem.enabled = NO;
	[self.spinner startAnimating];
	NSString *albumName = album.name;
	__weak typeof(self) weakSelf = self;
	[IMAlbumApi addAssetIds:self.assetIds
	              toAlbumId:album.albumId
	     detailedCompletion:^(NSInteger added, NSInteger duplicates, NSInteger failed, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    [strongSelf.spinner stopAnimating];
		    UIViewController *presenter = strongSelf.presentingViewController;
		    [strongSelf dismissViewControllerAnimated:YES completion:^{
			    [AddToAlbumViewController showAddResultWithAdded:added
			                                          duplicates:duplicates
			                                              failed:failed
			                                               error:error
			                                           albumName:albumName
			                                                  on:presenter];
		    }];
	    }];
}

+ (void)showAddResultWithAdded:(NSInteger)added
                    duplicates:(NSInteger)duplicates
                        failed:(NSInteger)failed
                         error:(nullable NSError *)error
                     albumName:(NSString *)albumName
                            on:(nullable UIViewController *)presenter {
	if (!presenter) {
		return;
	}
	if (error || (added == 0 && duplicates == 0)) {
		NSString *message = error.localizedDescription ?: _(@"The server rejected these items.");
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn't Add to Album")
		                                                                 message:message
		                                                          preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[presenter presentViewController:alert animated:YES completion:nil];
		return;
	}
	NSString *title;
	if (added > 0) {
		title = [NSString stringWithFormat:_(@"Added %ld to \"%@\""), (long)added, albumName];
	} else {
		title = [NSString stringWithFormat:_(@"Already in \"%@\""), albumName];
	}
	NSMutableArray<NSString *> *notes = [NSMutableArray array];
	if (added > 0 && duplicates > 0) {
		[notes addObject:[NSString stringWithFormat:_(@"%ld already in the album."), (long)duplicates]];
	}
	if (failed > 0) {
		[notes addObject:[NSString stringWithFormat:_(@"%ld couldn't be added."), (long)failed]];
	}
	UIAlertController *toast = [UIAlertController alertControllerWithTitle:title
	                                                                 message:notes.count > 0 ? [notes componentsJoinedByString:@"\n"] : nil
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[presenter presentViewController:toast animated:YES completion:nil];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[toast dismissViewControllerAnimated:YES completion:nil];
	});
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
				        [weakSelf addToAlbum:album];
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
	[self addToAlbum:self.albums[indexPath.row]];
}

@end
