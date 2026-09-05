#import "OAuthAccountViewController.h"
#import "IMOAuthCoordinator.h"
#import "IMOAuthApi.h"
#import "IMUserApi.h"
#import "IMUser.h"
#import "IMApiClient.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMOAuthAccountSection) {
	IMOAuthAccountSectionStatus = 0,
	IMOAuthAccountSectionActions,
	IMOAuthAccountSectionCount,
};

@interface OAuthAccountViewController ()
@property (nonatomic, strong, nullable) IMUser *user;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong, nullable) NSError *loadError;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
@end

@implementation OAuthAccountViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"OAuth Account");
	if (@available(iOS 13.0, *)) self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	else self.view.backgroundColor = UIColor.groupTableViewBackgroundColor;
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading && !self.mutating) [self reload];
}

- (void)reload {
	if (self.loading || self.mutating) {
		[self.refresh endRefreshing];
		return;
	}
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	[IMUserApi currentUserWithCompletion:^(IMUser *user, NSError *error) {
		OAuthAccountViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loading = NO;
		[strongSelf.refresh endRefreshing];
		if (user) {
			strongSelf.user = user;
			strongSelf.loadError = nil;
		} else {
			strongSelf.loadError = error;
		}
		[strongSelf.tableView reloadData];
		if (!user && error && strongSelf.viewIfLoaded.window) [strongSelf showError:error];
	}];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"OAuth Account")
	                                                                 message:error.localizedDescription ?: _(@"The server could not load the OAuth account.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showMutationError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"OAuth Account")
	                                                                 message:error.localizedDescription ?: _(@"The server rejected the OAuth change.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)isLinked {
	return self.user.oauthId.length > 0;
}

- (UITableViewCell *)cellWithTitle:(NSString *)title detail:(NSString *)detail accessory:(BOOL)accessory {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.numberOfLines = 0;
	cell.accessoryType = accessory ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	return cell;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return IMOAuthAccountSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == IMOAuthAccountSectionStatus ? _(@"Connection") : _(@"Actions");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == IMOAuthAccountSectionStatus) {
		return _(@"OAuth is used for browser-based sign-in. The provider identity is stored on the Immich server.");
	}
	return _(@"Linking opens the server's configured OAuth provider. Unlinking does not delete your Immich account.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == IMOAuthAccountSectionStatus) {
		if (!self.user) {
			return [self cellWithTitle:_(@"OAuth status") detail:self.loadError.localizedDescription ?: _(@"Loading…") accessory:NO];
		}
		if ([self isLinked]) {
			NSString *identity = self.user.oauthId;
			if (identity.length > 32) identity = [NSString stringWithFormat:@"%@…", [identity substringToIndex:32]];
			return [self cellWithTitle:_(@"Linked") detail:identity accessory:NO];
		}
		return [self cellWithTitle:_(@"Not linked") detail:_(@"No OAuth provider is connected") accessory:NO];
	}
	NSString *title = [self isLinked] ? _(@"Unlink OAuth Account") : _(@"Link OAuth Account");
	NSString *detail = [self isLinked] ? _(@"Remove the provider connection from this account") : _(@"Connect a provider for browser sign-in");
	UITableViewCell *cell = [self cellWithTitle:title detail:detail accessory:YES];
	cell.selectionStyle = self.user && !self.loading && !self.mutating ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != IMOAuthAccountSectionActions || !self.user || self.loading || self.mutating) return;
	if ([self isLinked]) [self confirmUnlink];
	else [self linkOAuth];
}

- (void)linkOAuth {
	self.mutating = YES;
	self.tableView.userInteractionEnabled = NO;
	__weak typeof(self) weakSelf = self;
	BOOL started = [IMOAuthCoordinator.shared startLinkFromViewController:self completion:^(IMUser *user, NSError *error) {
		OAuthAccountViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = NO;
		strongSelf.tableView.userInteractionEnabled = YES;
		if (!user || error) {
			[strongSelf showMutationError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid linked-user response.")}]];
			return;
		}
		strongSelf.user = user;
		[strongSelf.tableView reloadData];
	}];
	if (!started && !IMOAuthCoordinator.shared.isActive) {
		self.mutating = NO;
		self.tableView.userInteractionEnabled = YES;
		[self.tableView reloadData];
	}
}

- (void)confirmUnlink {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Unlink OAuth Account?")
	                                                                 message:_(@"You can link it again later. Your Immich account and photos remain unchanged.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Unlink") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		OAuthAccountViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = YES;
		strongSelf.tableView.userInteractionEnabled = NO;
		[IMOAuthApi unlinkWithCompletion:^(IMUser *user, NSError *error) {
			OAuthAccountViewController *inner = weakSelf;
			if (!inner) return;
			inner.mutating = NO;
			inner.tableView.userInteractionEnabled = YES;
			if (!user || error) {
				[inner showMutationError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid unlinked-user response.")}]];
				return;
			}
			inner.user = user;
			[inner.tableView reloadData];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
