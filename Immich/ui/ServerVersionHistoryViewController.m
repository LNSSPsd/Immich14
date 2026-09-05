#import "ServerVersionHistoryViewController.h"
#import "common.h"

@interface ServerVersionHistoryViewController ()
@property (nonatomic, copy) NSArray<IMServerVersionHistoryEntry *> *history;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation ServerVersionHistoryViewController

- (instancetype)initWithHistory:(NSArray<IMServerVersionHistoryEntry *> *)history {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_history = [history copy] ?: @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Version history");
	self.dateFormatter = [[NSDateFormatter alloc] init];
	self.dateFormatter.dateStyle = NSDateFormatterMediumStyle;
	self.dateFormatter.timeStyle = NSDateFormatterShortStyle;
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.history.count ?: 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"server-version-history";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	if (self.history.count == 0) {
		cell.textLabel.text = _(@"No version history available");
		cell.detailTextLabel.text = nil;
		cell.accessoryType = UITableViewCellAccessoryNone;
		return cell;
	}
	IMServerVersionHistoryEntry *entry = self.history[indexPath.row];
	cell.textLabel.text = entry.version;
	NSDate *date = IMDateFromServerTimestamp(entry.createdAt);
	cell.detailTextLabel.text = date ? [self.dateFormatter stringFromDate:date] : entry.createdAt;
	cell.accessoryType = UITableViewCellAccessoryNone;
	return cell;
}

@end
