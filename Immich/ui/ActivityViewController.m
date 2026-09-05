#import "ActivityViewController.h"
#import "IMActivityApi.h"
#import "IMActivity.h"
#import "IMApiClient.h"
#import "IMSession.h"
#import "common.h"

@interface ActivityViewController ()
@property (nonatomic, copy) NSString *albumId;
@property (nonatomic, copy, nullable) NSString *assetId;
@property (nonatomic, copy) NSArray<IMActivity *> *activities;
@property (nonatomic) NSInteger commentsCount;
@property (nonatomic) NSInteger likesCount;
@property (nonatomic) BOOL loading;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) UIRefreshControl *refresh;
@end

@implementation ActivityViewController

+ (instancetype)activityViewControllerForAlbumId:(NSString *)albumId
                                           assetId:(NSString *)assetId
                                             title:(NSString *)title {
	ActivityViewController *controller = [[self alloc] initWithStyle:UITableViewStyleInsetGrouped];
	controller.albumId = albumId ?: @"";
	controller.assetId = assetId;
	controller.title = title.length ? title : _(@"Activity");
	return controller;
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
	self = [super initWithStyle:style];
	if (self) {
		_activities = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
	                                                                                         target:self
	                                                                                         action:@selector(commentTapped)];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Like")
	                                                                            style:UIBarButtonItemStylePlain
	                                                                           target:self
	                                                                           action:@selector(likeTapped)];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.activities.count > 0) {
		[self reload];
	}
}

- (void)reload {
	if (self.loading || self.albumId.length == 0) {
		return;
	}
	self.loading = YES;
	NSUInteger generation = ++self.generation;
	__weak typeof(self) weakSelf = self;
	__block NSArray<IMActivity *> *loadedActivities;
	__block NSInteger loadedComments = 0;
	__block NSInteger loadedLikes = 0;
	__block NSError *firstError;
	__block NSInteger pending = 2;
	void (^finish)(void) = ^{
		pending -= 1;
		if (pending != 0) {
			return;
		}
		ActivityViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) {
			return;
		}
		strongSelf.loading = NO;
		[strongSelf.refresh endRefreshing];
		if (loadedActivities) {
			strongSelf.activities = loadedActivities;
		}
		if (!firstError) {
			strongSelf.commentsCount = loadedComments;
			strongSelf.likesCount = loadedLikes;
		}
		[strongSelf updateLikeButton];
		[strongSelf.tableView reloadData];
		if (firstError && !loadedActivities) {
			[strongSelf showError:firstError];
		}
	};
	[IMActivityApi activitiesForAlbumId:self.albumId
	                           assetId:self.assetId
	                              type:nil
	                             level:nil
	                            userId:nil
	                        completion:^(NSArray<IMActivity *> *items, NSError *error) {
		loadedActivities = items;
		if (error && !firstError) firstError = error;
		finish();
	}];
	[IMActivityApi statisticsForAlbumId:self.albumId
	                            assetId:self.assetId
	                         completion:^(NSInteger comments, NSInteger likes, NSError *error) {
		loadedComments = comments;
		loadedLikes = likes;
		if (error && !firstError) firstError = error;
		finish();
	}];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Activity")
	                                                                 message:error.localizedDescription ?: _(@"The server could not load activity.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (IMActivity *)currentUserLike {
	NSString *userId = IMSession.shared.userId;
	if (userId.length == 0) return nil;
	for (IMActivity *activity in self.activities) {
		if (activity.isLike && [activity.user.userId isEqualToString:userId]) return activity;
	}
	return nil;
}

- (void)updateLikeButton {
	self.navigationItem.leftBarButtonItem.title = [self currentUserLike] ? _(@"Unlike") : _(@"Like");
}

- (void)likeTapped {
	if (self.loading || self.albumId.length == 0) return;
	IMActivity *existing = [self currentUserLike];
	self.navigationItem.leftBarButtonItem.enabled = NO;
	__weak typeof(self) weakSelf = self;
	if (existing) {
		[IMActivityApi deleteActivityId:existing.activityId completion:^(BOOL success, NSError *error) {
			ActivityViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
			if (!success || error) { [strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The like could not be removed.")}]]; return; }
			[strongSelf reload];
		}];
		return;
	}
	[IMActivityApi createForAlbumId:self.albumId assetId:self.assetId type:@"like" comment:nil completion:^(IMActivity *activity, NSError *error) {
		ActivityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
		if (!activity || error) { [strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The like could not be added.")}]]; return; }
		[strongSelf reload];
	}];
}

- (void)commentTapped {
	if (self.loading || self.albumId.length == 0) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Add Comment") message:nil preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Comment");
		field.autocapitalizationType = UITextAutocapitalizationTypeSentences;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Post") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *comment = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (comment.length == 0) return;
		[IMActivityApi createForAlbumId:weakSelf.albumId assetId:weakSelf.assetId type:@"comment" comment:comment completion:^(IMActivity *activity, NSError *error) {
			ActivityViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!activity || error) { [strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The comment could not be posted.")}]]; return; }
			[strongSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)dateString:(NSDate *)date {
	static NSDateFormatter *formatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.dateStyle = NSDateFormatterShortStyle;
		formatter.timeStyle = NSDateFormatterShortStyle;
	});
	return [formatter stringFromDate:date ?: [NSDate date]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1;
	return MAX((NSInteger)1, self.activities.count);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? _(@"Summary") : _(@"Comments and Likes");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"activity-cell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	if (indexPath.section == 0) {
		cell.textLabel.text = [NSString stringWithFormat:_(@"%ld likes · %ld comments"), (long)self.likesCount, (long)self.commentsCount];
		cell.detailTextLabel.text = _(@"Use Like or Compose to add activity.");
		return cell;
	}
	if (self.activities.count == 0) {
		cell.textLabel.text = _(@"No activity yet");
		cell.detailTextLabel.text = nil;
		return cell;
	}
	IMActivity *activity = self.activities[indexPath.row];
	NSString *name = activity.user.name.length ? activity.user.name : (activity.user.email.length ? activity.user.email : _(@"Immich user"));
	cell.textLabel.text = activity.isLike ? [NSString stringWithFormat:_(@"%@ liked this"), name] : name;
	cell.detailTextLabel.text = activity.isComment
	    ? [NSString stringWithFormat:_(@"%@ · %@"), activity.comment ?: @"", [self dateString:activity.createdAt]]
	    : [self dateString:activity.createdAt];
	cell.detailTextLabel.numberOfLines = 0;
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section != 1 || indexPath.row >= (NSInteger)self.activities.count) return NO;
	IMActivity *activity = self.activities[indexPath.row];
	return [activity.user.userId isEqualToString:IMSession.shared.userId];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 1 || indexPath.row >= (NSInteger)self.activities.count) return;
	IMActivity *activity = self.activities[indexPath.row];
	__weak typeof(self) weakSelf = self;
	[IMActivityApi deleteActivityId:activity.activityId completion:^(BOOL success, NSError *error) {
		ActivityViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		if (!success || error) { [strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The activity could not be deleted.")}]]; return; }
		[strongSelf reload];
	}];
}

@end
