#import "PluginsViewController.h"
#import "IMPluginApi.h"
#import "IMPlugin.h"
#import "common.h"

typedef NS_ENUM(NSInteger, IMPluginsSection) {
	IMPluginsSectionPlugins = 0,
	IMPluginsSectionTemplates = 1,
};

@interface PluginsViewController ()
@property (nonatomic, copy) NSArray<IMPlugin *> *plugins;
@property (nonatomic, copy) NSArray<IMPluginTemplate *> *templates;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSInteger pendingRequests;
@property (nonatomic, strong, nullable) NSError *loadError;
@end

@implementation PluginsViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Plugins");
	self.plugins = @[];
	self.templates = @[];
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 64.0;
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	if (@available(iOS 13.0, *)) self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.tableView.backgroundView = self.statusLabel;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
	                                                                                          target:self
	                                                                                          action:@selector(reload)];
	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (self.isViewLoaded && !self.loading) [self reload];
}

- (void)dealloc {
	self.generation += 1;
}

- (void)updateStatus {
	if (self.loading && self.plugins.count == 0 && self.templates.count == 0) {
		self.statusLabel.text = _(@"Loading installed plugins…");
	} else if (self.loadError && self.plugins.count == 0 && self.templates.count == 0) {
		self.statusLabel.text = _(@"Couldn't load plugins. Tap to retry.");
	} else if (!self.plugins.count && !self.templates.count) {
		self.statusLabel.text = _(@"No plugins or workflow templates are installed.");
	} else {
		self.statusLabel.text = nil;
	}
	self.statusLabel.accessibilityLabel = self.statusLabel.text;
}

- (void)reload {
	if (self.loading) {
		[self.refresh endRefreshing];
		return;
	}
	self.loading = YES;
	self.pendingRequests = 2;
	self.loadError = nil;
	NSUInteger generation = ++self.generation;
	[self updateStatus];
	[self.tableView reloadData];
	__weak typeof(self) weakSelf = self;
	[IMPluginApi pluginsWithCompletion:^(NSArray<IMPlugin *> *plugins, NSError *error) {
		PluginsViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		if (plugins) strongSelf.plugins = plugins;
		if (error) strongSelf.loadError = error;
		[strongSelf requestFinishedForGeneration:generation];
	}];
	[IMPluginApi pluginTemplatesWithCompletion:^(NSArray<IMPluginTemplate *> *templates, NSError *error) {
		PluginsViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		if (templates) strongSelf.templates = templates;
		if (error) strongSelf.loadError = error;
		[strongSelf requestFinishedForGeneration:generation];
	}];
}

- (void)requestFinishedForGeneration:(NSUInteger)generation {
	if (generation != self.generation || self.pendingRequests <= 0) return;
	self.pendingRequests -= 1;
	if (self.pendingRequests > 0) return;
	self.loading = NO;
	[self.refresh endRefreshing];
	[self updateStatus];
	[self.tableView reloadData];
	if (self.loadError && !self.plugins.count && !self.templates.count && self.viewIfLoaded.window) {
		[self showError:self.loadError];
	}
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not load plugin information.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Plugins") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	if (self.viewIfLoaded.window) [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == IMPluginsSectionPlugins ? self.plugins.count : self.templates.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == IMPluginsSectionPlugins) return self.plugins.count ? _(@"Installed plugins") : nil;
	return self.templates.count ? _(@"Workflow templates") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"plugin-row";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.textLabel.numberOfLines = 2;
	cell.detailTextLabel.numberOfLines = 3;
	if (indexPath.section == IMPluginsSectionPlugins) {
		IMPlugin *plugin = self.plugins[indexPath.row];
		cell.textLabel.text = plugin.title.length ? plugin.title : plugin.name;
		NSString *author = plugin.author.length ? plugin.author : _(@"Unknown author");
		cell.detailTextLabel.text = [NSString stringWithFormat:_(@"%@ · v%@ · %lu methods"), author,
		                              plugin.version.length ? plugin.version : @"?", (unsigned long)plugin.methods.count];
		cell.accessibilityLabel = cell.textLabel.text;
		cell.accessibilityValue = cell.detailTextLabel.text;
	} else {
		IMPluginTemplate *template = self.templates[indexPath.row];
		cell.textLabel.text = template.title.length ? template.title : template.key;
		cell.detailTextLabel.text = [NSString stringWithFormat:_(@"%@ · %lu steps"), template.trigger,
		                              (unsigned long)template.steps.count];
		cell.accessibilityLabel = cell.textLabel.text;
		cell.accessibilityValue = cell.detailTextLabel.text;
	}
	return cell;
}

- (NSString *)methodSummary:(IMPluginMethod *)method {
	NSString *name = method.title.length ? method.title : method.name;
	NSString *types = method.types.count ? [method.types componentsJoinedByString:@", "] : _(@"No workflow type");
	return [NSString stringWithFormat:_(@"%@ (%@)%@"), name, types, method.hostFunctions ? _(@" · host functions") : @""];
}

- (void)showPlugin:(IMPlugin *)plugin {
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	if (plugin.pluginDescription.length) [lines addObject:plugin.pluginDescription];
	[lines addObject:[NSString stringWithFormat:_(@"Version: %@\nAuthor: %@"), plugin.version, plugin.author]];
	if (plugin.methods.count) {
		[lines addObject:_(@"Methods")];
		for (IMPluginMethod *method in plugin.methods) [lines addObject:[NSString stringWithFormat:@"• %@", [self methodSummary:method]]];
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:plugin.title.length ? plugin.title : plugin.name
	                                                                 message:[lines componentsJoinedByString:@"\n\n"]
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showTemplate:(IMPluginTemplate *)template {
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	if (template.templateDescription.length) [lines addObject:template.templateDescription];
	[lines addObject:[NSString stringWithFormat:_(@"Trigger: %@\nSteps: %lu"), template.trigger, (unsigned long)template.steps.count]];
	for (NSUInteger index = 0; index < template.steps.count; index++) {
		IMPluginTemplateStep *step = template.steps[index];
		[lines addObject:[NSString stringWithFormat:_(@"%lu. %@%@"), (unsigned long)(index + 1), step.method,
		                                  step.isEnabled ? @"" : [NSString stringWithFormat:@" (%@)", _(@"disabled")]]];
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:template.title.length ? template.title : template.key
	                                                                 message:[lines componentsJoinedByString:@"\n\n"]
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == IMPluginsSectionPlugins && indexPath.row < (NSInteger)self.plugins.count) [self showPlugin:self.plugins[indexPath.row]];
	else if (indexPath.section == IMPluginsSectionTemplates && indexPath.row < (NSInteger)self.templates.count) [self showTemplate:self.templates[indexPath.row]];
}

@end
