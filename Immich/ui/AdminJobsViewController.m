#import "AdminJobsViewController.h"
#import "IMQueueApi.h"
#import "IMQueue.h"
#import "common.h"

@interface AdminJobsViewController ()
@property (nonatomic, copy) NSArray<IMQueue *> *queues;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic) BOOL loading;
@end

@implementation AdminJobsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Jobs & Queues");
	self.queues = @[];
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Run Job") style:UIBarButtonItemStylePlain target:self action:@selector(runJobTapped)];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.queues.count) [self reload];
}

- (void)reload {
	if (self.loading) return;
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	[IMQueueApi allQueuesWithCompletion:^(NSArray<IMQueue *> *queues, NSError *error) {
		AdminJobsViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.loading = NO;
		[strongSelf.refresh endRefreshing];
		if (error) {
			[strongSelf showError:error];
			return;
		}
		strongSelf.queues = queues ?: @[];
		[strongSelf.tableView reloadData];
	}];
}

- (void)showError:(NSError *)error {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Jobs & Queues")
	                                                                 message:error.localizedDescription ?: _(@"The server could not load queue status.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)displayNameForQueue:(NSString *)name {
	NSMutableString *display = [name mutableCopy];
	[display replaceOccurrencesOfString:@"Generation" withString:_(@" Generation") options:0 range:NSMakeRange(0, display.length)];
	[display replaceOccurrencesOfString:@"Extraction" withString:_(@" Extraction") options:0 range:NSMakeRange(0, display.length)];
	[display replaceOccurrencesOfString:@"Conversion" withString:_(@" Conversion") options:0 range:NSMakeRange(0, display.length)];
	[display replaceOccurrencesOfString:@"Detection" withString:_(@" Detection") options:0 range:NSMakeRange(0, display.length)];
	[display replaceOccurrencesOfString:@"Task" withString:_(@" Task") options:0 range:NSMakeRange(0, display.length)];
	return display.capitalizedString;
}

- (NSString *)summaryForQueue:(IMQueue *)queue {
	return [NSString stringWithFormat:_(@"%@ waiting · %@ active · %@ failed · %@ completed"),
	        @(queue.waiting), @(queue.active), @(queue.failed), @(queue.completed)];
}

- (NSString *)displayNameForManualJob:(NSString *)job {
	NSDictionary<NSString *, NSString *> *names = @{
		@"person-cleanup": _(@"Clean up people"),
		@"tag-cleanup": _(@"Clean up tags"),
		@"user-cleanup": _(@"Clean up users"),
		@"memory-cleanup": _(@"Clean up memories"),
		@"memory-create": _(@"Generate memories"),
		@"backup-database": _(@"Back up database"),
		@"integrity-missing-files": _(@"Find missing files"),
		@"integrity-untracked-files": _(@"Find untracked files"),
		@"integrity-checksum-mismatch": _(@"Find checksum mismatches"),
	};
	return names[job] ?: job;
}

- (void)queueSwitchChanged:(UISwitch *)sender {
	NSInteger index = sender.tag;
	if (index < 0 || index >= (NSInteger)self.queues.count) return;
	IMQueue *queue = self.queues[index];
	sender.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMQueueApi setQueueNamed:queue.name paused:sender.isOn completion:^(IMQueue *updated, NSError *error) {
		AdminJobsViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		if (error || !updated) {
			sender.on = queue.paused;
			[strongSelf showError:error ?: [NSError errorWithDomain:@"IMQueueApi" code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not update this queue.")}]];
		}
		sender.enabled = YES;
		if (updated && index < (NSInteger)strongSelf.queues.count) {
			NSMutableArray *copy = [strongSelf.queues mutableCopy];
			copy[index] = updated;
			strongSelf.queues = [copy copy];
			[strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
		}
	}];
}

- (void)runJobTapped {
	NSArray<NSString *> *jobs = @[ @"person-cleanup", @"tag-cleanup", @"user-cleanup", @"memory-cleanup", @"memory-create", @"backup-database", @"integrity-missing-files", @"integrity-untracked-files", @"integrity-checksum-mismatch" ];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Run Manual Job") message:_(@"Choose a job to queue on the server.") preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	for (NSString *job in jobs) {
		[sheet addAction:[UIAlertAction actionWithTitle:[self displayNameForManualJob:job] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			[IMQueueApi runManualJobNamed:job completion:^(BOOL success, NSError *error) {
				AdminJobsViewController *strongSelf = weakSelf;
				if (!strongSelf) return;
				if (!success || error) { [strongSelf showError:error]; return; }
				[strongSelf reload];
			}];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.queues.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return _(@"Server Queues");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"admin-queue";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	IMQueue *queue = self.queues[indexPath.row];
	cell.textLabel.text = [self displayNameForQueue:queue.name];
	cell.detailTextLabel.text = [self summaryForQueue:queue];
	cell.detailTextLabel.numberOfLines = 2;
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = queue.paused;
	toggle.tag = indexPath.row;
	[toggle addTarget:self action:@selector(queueSwitchChanged:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	cell.accessibilityLabel = cell.textLabel.text;
	cell.accessibilityValue = queue.paused ? _(@"Paused") : _(@"Running");
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete) return;
	IMQueue *queue = self.queues[indexPath.row];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Empty Queue?") message:[self displayNameForQueue:queue.name] preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Empty") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[IMQueueApi emptyQueueNamed:queue.name includeFailed:YES completion:^(BOOL success, NSError *error) {
			AdminJobsViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (!success || error) { [strongSelf showError:error]; return; }
			[strongSelf reload];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
