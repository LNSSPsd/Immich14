#import "PersonMergeViewController.h"
#import "IMSearchApi.h"
#import "IMPeopleApi.h"
#import "IMApiClient.h"
#import "IMPerson.h"
#import "common.h"

@interface PersonMergeViewController ()
@property (nonatomic, copy) NSString *targetPersonId;
@property (nonatomic, copy) NSString *targetName;
@property (nonatomic, copy) NSArray<IMPerson *> *candidates;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedIds;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL merging;
@property (nonatomic) NSUInteger generation;
@end

@implementation PersonMergeViewController

- (instancetype)initWithTargetPersonId:(NSString *)personId targetName:(NSString *)name {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_targetPersonId = [personId copy];
		_targetName = [name copy] ?: @"";
		_candidates = @[];
		_selectedIds = [NSMutableSet set];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Merge People");
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Merge") style:UIBarButtonItemStyleDone target:self action:@selector(mergeTapped)];
	self.navigationItem.rightBarButtonItem.enabled = NO;
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reloadCandidates) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reloadCandidates)]];
	self.tableView.backgroundView = self.statusLabel;
	[self reloadCandidates];
}

- (void)dealloc {
	[self.task cancel];
	self.generation += 1;
}

- (void)reloadCandidates {
	if (self.loading || self.merging) { [self.refresh endRefreshing]; return; }
	[self.task cancel];
	self.loading = YES;
	NSUInteger generation = ++self.generation;
	self.statusLabel.text = _(@"Loading people…");
	__weak typeof(self) weakSelf = self;
	self.task = [IMSearchApi peopleAtPage:1 includeHidden:YES completion:^(NSArray<IMPerson *> *people, BOOL hasNextPage, NSError *error) {
		PersonMergeViewController *self = weakSelf;
		if (!self || generation != self.generation) return;
		self.task = nil;
		self.loading = NO;
		[self.refresh endRefreshing];
		if (error || !people) {
			self.statusLabel.text = _(@"Couldn't load people. Tap to retry.");
			if (error) [self showError:error];
			return;
		}
		NSMutableArray<IMPerson *> *filtered = [NSMutableArray array];
		for (IMPerson *person in people) if (![person.personId isEqualToString:self.targetPersonId]) [filtered addObject:person];
		self.candidates = filtered;
		self.statusLabel.text = filtered.count ? nil : _(@"No other people are available to merge.");
		[self.tableView reloadData];
	}];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Merge People") message:error.localizedDescription ?: _(@"The server could not complete this request.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (void)mergeTapped {
	if (self.merging || self.selectedIds.count == 0) return;
	NSString *target = self.targetName.length ? self.targetName : _(@"this person");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Merge selected people?") message:[NSString stringWithFormat:_(@"Their faces and photos will be moved into %@. This cannot be undone."), target] preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Merge") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		PersonMergeViewController *self = weakSelf;
		if (!self || self.merging) return;
		self.merging = YES;
		self.navigationItem.rightBarButtonItem.enabled = NO;
		[IMPeopleApi mergePersonId:self.targetPersonId withPersonIds:self.selectedIds.allObjects completion:^(NSArray<IMPersonMutationResult *> *results, NSError *error) {
			PersonMergeViewController *inner = weakSelf;
			if (!inner) return;
			inner.merging = NO;
			if (error) { inner.navigationItem.rightBarButtonItem.enabled = YES; [inner showError:error]; return; }
			NSInteger failures = 0;
			for (IMPersonMutationResult *result in results) if (!result.success) failures += 1;
			if (failures > 0) {
				inner.navigationItem.rightBarButtonItem.enabled = YES;
				[inner showError:[NSError errorWithDomain:IMApiErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:_(@"%ld people could not be merged."), (long)failures]}]];
				return;
			}
			[inner.navigationController popViewControllerAnimated:YES];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.candidates.count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.candidates.count ? _(@"Select people to merge into the current person") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"person-merge"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"person-merge"];
	IMPerson *person = self.candidates[indexPath.row];
	cell.textLabel.text = person.name.length ? person.name : _(@"Unnamed person");
	cell.detailTextLabel.text = person.isHidden ? _(@"Hidden") : nil;
	cell.accessoryType = [self.selectedIds containsObject:person.personId] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.merging || indexPath.row >= (NSInteger)self.candidates.count) return;
	IMPerson *person = self.candidates[indexPath.row];
	if ([self.selectedIds containsObject:person.personId]) [self.selectedIds removeObject:person.personId];
	else if (person.personId.length) [self.selectedIds addObject:person.personId];
	self.navigationItem.rightBarButtonItem.enabled = self.selectedIds.count > 0;
	[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

@end
