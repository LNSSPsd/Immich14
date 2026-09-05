#import "PartnersViewController.h"
#import "IMPartnerApi.h"
#import "IMSession.h"
#import "PartnerTimelineViewController.h"
#import "common.h"

@interface PartnersViewController ()
@property (nonatomic, copy) NSArray<IMPartner *> *sharedWith; 
@property (nonatomic, copy) NSArray<IMPartner *> *sharedBy;   
@property (nonatomic, copy) NSArray<IMPartner *> *users;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic) BOOL choosingUser;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@property (nonatomic) BOOL hasAppeared;
- (void)selectUser:(IMPartner *)user;
- (void)showError:(NSError *)error;
@end

@implementation PartnersViewController

+ (instancetype)pickerWithUsers:(NSArray<IMPartner *> *)users {
	PartnersViewController *vc = [[self alloc] initWithStyle:UITableViewStyleInsetGrouped];
	vc.choosingUser = YES;
	vc.users = [users copy] ?: @[];
	return vc;
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
	self = [super initWithStyle:style];
	if (self) {
		_sharedWith = @[];
		_sharedBy = @[];
		_users = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.choosingUser ? _(@"Choose Partner") : _(@"Partner Sharing");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	}
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.tableView.backgroundView = self.statusLabel;

	if (self.choosingUser) {
		self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
		                                                                                       target:self
		                                                                                       action:@selector(cancelPicker)];
		self.statusLabel.text = self.users.count ? nil : _(@"No users are available to add.");
		[self.tableView reloadData];
		return;
	}
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
	                                                                                        target:self
	                                                                                        action:@selector(addPartner)];
	self.refreshControl = [[UIRefreshControl alloc] init];
	[self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!self.choosingUser) {
		if (self.hasAppeared && !self.loading && !self.mutating) [self reload];
		self.hasAppeared = YES;
	}
}

- (void)cancelPicker {
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)reload {
	if (self.choosingUser || self.loading || self.mutating) {
		[self.refreshControl endRefreshing];
		return;
	}
	self.loading = YES;
	self.statusLabel.text = (self.sharedWith.count || self.sharedBy.count) ? nil : _(@"Loading partners…");
	__weak typeof(self) weakSelf = self;
	dispatch_group_t group = dispatch_group_create();
	__block NSArray<IMPartner *> *incoming = nil;
	__block NSArray<IMPartner *> *outgoing = nil;
	__block NSError *incomingError = nil;
	__block NSError *outgoingError = nil;
	dispatch_group_enter(group);
	[IMPartnerApi partnersWithDirection:@"shared-with" completion:^(NSArray<IMPartner *> *partners, NSError *error) {
		incoming = partners;
		incomingError = error;
		dispatch_group_leave(group);
	}];
	dispatch_group_enter(group);
	[IMPartnerApi partnersWithDirection:@"shared-by" completion:^(NSArray<IMPartner *> *partners, NSError *error) {
		outgoing = partners;
		outgoingError = error;
		dispatch_group_leave(group);
	}];
	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		PartnersViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		[self.refreshControl endRefreshing];
		if (incoming) self.sharedWith = incoming;
		if (outgoing) self.sharedBy = outgoing;
		[self.tableView reloadData];
		if (incoming.count || outgoing.count) {
			self.statusLabel.text = nil;
		} else if (incomingError || outgoingError) {
			self.statusLabel.text = _(@"Couldn't load partners. Tap to retry.");
			[self showError:incomingError ?: outgoingError];
		} else {
			self.statusLabel.text = _(@"No partner shares yet. Tap + to add one.");
		}
	});
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not complete this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Partner Sharing")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)addPartner {
	if (self.loading || self.mutating) return;
	self.loading = YES;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	self.statusLabel.text = _(@"Loading users…");
	__weak typeof(self) weakSelf = self;
	[IMPartnerApi usersWithCompletion:^(NSArray<IMPartner *> *users, NSError *error) {
		PartnersViewController *self = weakSelf;
		if (!self) return;
		self.loading = NO;
		self.navigationItem.rightBarButtonItem.enabled = YES;
		if (error) {
			[self showError:error];
			self.statusLabel.text = self.sharedWith.count || self.sharedBy.count ? nil : _(@"No partner shares yet. Tap + to add one.");
			return;
		}
		NSMutableSet<NSString *> *existingIds = [NSMutableSet set];
		for (IMPartner *partner in self.sharedBy) if (partner.partnerId.length) [existingIds addObject:partner.partnerId];
		if (IMSession.shared.userId.length) [existingIds addObject:IMSession.shared.userId];
		NSMutableArray<IMPartner *> *available = [NSMutableArray array];
		for (IMPartner *user in users) {
			if (user.partnerId.length && ![existingIds containsObject:user.partnerId]) [available addObject:user];
		}
		if (!available.count) {
			self.statusLabel.text = self.sharedWith.count || self.sharedBy.count ? nil : _(@"No partner shares yet. Tap + to add one.");
			[self showError:[NSError errorWithDomain:@"IMPartnerError"
			                                  code:2
			                              userInfo:@{ NSLocalizedDescriptionKey : _(@"Everyone on this server is already a partner.") }]];
			return;
		}
		[self.navigationController pushViewController:[PartnersViewController pickerWithUsers:available] animated:YES];
	}];
}

- (void)selectUser:(IMPartner *)user {
	if (self.mutating || !user.partnerId.length) return;
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMPartnerApi createPartnerWithUserId:user.partnerId completion:^(IMPartner *partner, NSError *error) {
		PartnersViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		self.tableView.userInteractionEnabled = YES;
		if (error || !partner) {
			[self showError:error ?: [NSError errorWithDomain:@"IMPartnerError"
			                                             code:3
			                                         userInfo:@{ NSLocalizedDescriptionKey : _(@"Could not add partner.") }]];
			return;
		}
		[self.navigationController popViewControllerAnimated:YES];
	}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.choosingUser ? 1 : 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (self.choosingUser) return self.users.count;
	return section == 0 ? self.sharedWith.count : self.sharedBy.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (self.choosingUser) return _(@"Users");
	return section == 0 ? _(@"Shared By") : _(@"Sharing With");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	IMPartner *partner = self.choosingUser ? self.users[indexPath.row] : (indexPath.section == 0 ? self.sharedWith[indexPath.row] : self.sharedBy[indexPath.row]);
	cell.textLabel.text = partner.name.length ? partner.name : partner.email;
	cell.detailTextLabel.text = partner.email.length ? partner.email : partner.partnerId;
	if (!self.choosingUser && indexPath.section == 0) {
		UISwitch *toggle = [[UISwitch alloc] init];
		toggle.on = partner.inTimeline;
		toggle.tag = indexPath.row;
		[toggle addTarget:self action:@selector(timelineChanged:) forControlEvents:UIControlEventValueChanged];
		cell.accessoryView = toggle;
		cell.accessibilityHint = _(@"Tap the row to browse this partner's shared photos.");
	} else if (self.choosingUser) {
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.choosingUser && indexPath.row < (NSInteger)self.users.count) {
		[self selectUser:self.users[indexPath.row]];
		return;
	}
	if (!self.choosingUser && indexPath.section == 0 && indexPath.row < (NSInteger)self.sharedWith.count) {
		IMPartner *partner = self.sharedWith[indexPath.row];
		if (partner.partnerId.length) {
			[self.navigationController pushViewController:[PartnerTimelineViewController viewControllerWithPartner:partner] animated:YES];
		}
	}
}

- (void)timelineChanged:(UISwitch *)toggle {
	NSInteger row = toggle.tag;
	if (row < 0 || row >= (NSInteger)self.sharedWith.count) return;
	IMPartner *partner = self.sharedWith[row];
	__weak typeof(self) weakSelf = self;
	[IMPartnerApi updatePartnerId:partner.partnerId inTimeline:toggle.isOn completion:^(IMPartner *updated, NSError *error) {
		if (error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				PartnersViewController *self = weakSelf;
				if (self) toggle.on = !toggle.isOn;
			});
		}
	}];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return !self.choosingUser && indexPath.section == 1;
}

- (void)tableView:(UITableView *)tableView
 commitEditingStyle:(UITableViewCellEditingStyle)style
 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.choosingUser || style != UITableViewCellEditingStyleDelete || indexPath.section != 1 || indexPath.row >= (NSInteger)self.sharedBy.count) return;
	IMPartner *partner = self.sharedBy[indexPath.row];
	self.mutating = YES;
	tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMPartnerApi removePartnerId:partner.partnerId completion:^(BOOL success, NSError *error) {
		PartnersViewController *self = weakSelf;
		if (!self) return;
		self.mutating = NO;
		self.tableView.userInteractionEnabled = YES;
		if (!success) {
			[self showError:error ?: [NSError errorWithDomain:@"IMPartnerError"
			                                             code:4
			                                         userInfo:@{ NSLocalizedDescriptionKey : _(@"Could not remove partner.") }]];
			return;
		}
		NSMutableArray<IMPartner *> *updated = [self.sharedBy mutableCopy];
		if (indexPath.row < (NSInteger)updated.count) [updated removeObjectAtIndex:indexPath.row];
		self.sharedBy = updated;
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	}];
}

@end
