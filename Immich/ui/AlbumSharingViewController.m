#import "AlbumSharingViewController.h"
#import "IMAlbumSharingApi.h"
#import "IMSession.h"
#import "common.h"

@interface AlbumSharingViewController ()
@property (nonatomic, copy) NSString *albumId;
@property (nonatomic, copy) NSArray<IMAlbumMember *> *members;
@property (nonatomic, copy) NSArray<IMAlbumMember *> *users;
@property (nonatomic) BOOL choosingUser;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation AlbumSharingViewController
- (instancetype)initWithAlbumId:(NSString *)albumId {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) { _albumId = [albumId copy]; _members = @[]; _users = @[]; }
	return self;
}
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.choosingUser ? _(@"Add Member") : _(@"Album Sharing");
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reloadMembers) forControlEvents:UIControlEventValueChanged];
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reloadMembers)]];
	self.tableView.backgroundView = self.statusLabel;
	if (self.choosingUser) self.statusLabel.text = self.users.count ? nil : _(@"Everyone already has access to this album.");
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!self.choosingUser) [self reloadMembers];
}
- (BOOL)canManageSharing {
	for (IMAlbumMember *member in self.members) {
		if ([member.userId isEqualToString:IMSession.shared.userId] && ([member.role isEqualToString:@"owner"] || [member.role isEqualToString:@"editor"])) return YES;
	}
	return NO;
}
- (void)reloadMembers {
	if (self.loading || self.mutating || self.choosingUser) { [self.refreshControl endRefreshing]; return; }
	self.loading = YES;
	if (!self.members.count) self.statusLabel.text = _(@"Loading members…");
	__weak typeof(self) weakSelf = self;
	[IMAlbumSharingApi membersForAlbumId:self.albumId completion:^(NSArray<IMAlbumMember *> *members, NSError *error) {
		AlbumSharingViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		[self.refreshControl endRefreshing];
		if (error) {
			if (!self.members.count) self.statusLabel.text = _(@"Couldn't load members. Tap to retry.");
			else [self showError:error];
			return;
		}
		self.members = members;
		self.statusLabel.text = members.count ? nil : _(@"No album members.");
		self.navigationItem.rightBarButtonItem = self.canManageSharing ? [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addMember)] : nil;
		[self.tableView reloadData];
	}];
}
- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Album Sharing") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
- (void)addMember {
	if (self.loading || self.mutating || !self.canManageSharing) return;
	self.loading = YES;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMAlbumSharingApi availableUsersWithCompletion:^(NSArray<IMAlbumMember *> *users, NSError *error) {
		AlbumSharingViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		self.navigationItem.rightBarButtonItem.enabled = YES;
		if (error) { [self showError:error]; return; }
		NSMutableSet *existingIds = [NSMutableSet set];
		for (IMAlbumMember *member in self.members) [existingIds addObject:member.userId];
		NSMutableArray *available = [NSMutableArray array];
		for (IMAlbumMember *user in users) if (![existingIds containsObject:user.userId]) [available addObject:user];
		AlbumSharingViewController *picker = [[AlbumSharingViewController alloc] initWithAlbumId:self.albumId];
		picker.choosingUser = YES;
		picker.users = available;
		[self.navigationController pushViewController:picker animated:YES];
	}];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.choosingUser ? self.users.count : self.members.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"member"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"member"];
	IMAlbumMember *member = (self.choosingUser ? self.users : self.members)[indexPath.row];
	cell.textLabel.text = member.name.length ? member.name : member.email;
	NSString *role = [member.role isEqualToString:@"owner"] ? _(@"Owner") : ([member.role isEqualToString:@"editor"] ? _(@"Editor") : _(@"Viewer"));
	cell.detailTextLabel.text = self.choosingUser ? member.email : [NSString stringWithFormat:@"%@ · %@", member.email, role];
	BOOL actionable = self.choosingUser || (![member.role isEqualToString:@"owner"] && (self.canManageSharing || [member.userId isEqualToString:IMSession.shared.userId]));
	cell.accessoryType = actionable ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	cell.selectionStyle = actionable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.mutating) return;
	IMAlbumMember *member = (self.choosingUser ? self.users : self.members)[indexPath.row];
	BOOL ownMembership = [member.userId isEqualToString:IMSession.shared.userId];
	if (!self.choosingUser && ([member.role isEqualToString:@"owner"] || (!self.canManageSharing && !ownMembership))) return;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:member.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	if (self.choosingUser || self.canManageSharing) {
		for (NSString *role in @[@"viewer", @"editor"]) {
			NSString *title = [role isEqualToString:@"viewer"] ? _(@"Viewer — can view photos") : _(@"Editor — can contribute and manage sharing");
			[sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [weakSelf setRole:role forMember:member]; }]];
		}
	}
	if (!self.choosingUser) {
		[sheet addAction:[UIAlertAction actionWithTitle:ownMembership ? _(@"Leave Album") : _(@"Remove Member") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [weakSelf confirmRemoval:member]; }]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}
- (void)setBusy:(BOOL)busy {
	self.mutating = busy;
	self.tableView.userInteractionEnabled = !busy;
	self.navigationItem.rightBarButtonItem.enabled = !busy;
}
- (void)setRole:(NSString *)role forMember:(IMAlbumMember *)member {
	[self setBusy:YES];
	__weak typeof(self) weakSelf = self;
	void (^completion)(NSError *) = ^(NSError *error) {
		AlbumSharingViewController *self = weakSelf;
		if (!self) return;
		[self setBusy:NO];
		if (error) { [self showError:error]; return; }
		if (self.choosingUser) [self.navigationController popViewControllerAnimated:YES];
		else [self reloadMembers];
	};
	if (self.choosingUser) [IMAlbumSharingApi addUserId:member.userId role:role albumId:self.albumId completion:completion];
	else [IMAlbumSharingApi updateUserId:member.userId role:role albumId:self.albumId completion:completion];
}
- (void)confirmRemoval:(IMAlbumMember *)member {
	BOOL leaving = [member.userId isEqualToString:IMSession.shared.userId];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:leaving ? _(@"Leave Album?") : _(@"Remove Member?") message:leaving ? _(@"You will lose access to this shared album.") : _(@"This user will lose access to the album.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:leaving ? _(@"Leave") : _(@"Remove") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[weakSelf setBusy:YES];
		[IMAlbumSharingApi removeUserId:member.userId albumId:weakSelf.albumId completion:^(NSError *error) {
			AlbumSharingViewController *self = weakSelf;
			if (!self) return;
			[self setBusy:NO];
			if (error) { [self showError:error]; return; }
			if (leaving) [self.navigationController popToRootViewControllerAnimated:YES];
			else [self reloadMembers];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}
@end
