#import "WorkflowsViewController.h"
#import "IMWorkflowApi.h"
#import "IMWorkflow.h"
#import "IMWorkflowStep.h"
#import "IMApiClient.h"
#import "PluginsViewController.h"
#import "common.h"

static NSString *const IMWorkflowAssetCreateTrigger = @"AssetCreate";
static NSString *const IMWorkflowMetadataTrigger = @"AssetMetadataExtraction";

typedef void (^IMWorkflowEditorSavedBlock)(IMWorkflow *workflow);

@interface IMWorkflowEditorViewController : UIViewController
- (instancetype)initWithWorkflow:(nullable IMWorkflow *)workflow
                         onSaved:(IMWorkflowEditorSavedBlock)onSaved;
@end

@interface IMWorkflowEditorViewController ()
@property (nonatomic, strong, nullable) IMWorkflow *workflow;
@property (nonatomic, copy) IMWorkflowEditorSavedBlock onSaved;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *descriptionField;
@property (nonatomic, strong) UITextField *triggerField;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UITextView *stepsView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic) BOOL saving;
@end

@implementation IMWorkflowEditorViewController

- (instancetype)initWithWorkflow:(IMWorkflow *)workflow
                         onSaved:(IMWorkflowEditorSavedBlock)onSaved {
	self = [super init];
	if (self) {
		_workflow = workflow;
		_onSaved = [onSaved copy];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	BOOL editing = self.workflow != nil;
	self.title = editing ? _(@"Edit Workflow") : _(@"New Workflow");
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
	                                                                                         target:self
	                                                                                         action:@selector(cancelTapped)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
	                                                                                          target:self
	                                                                                          action:@selector(saveTapped)];

	UIScrollView *scroll = [[UIScrollView alloc] init];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:scroll];
	UIStackView *stack = [[UIStackView alloc] init];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 8;
	stack.layoutMargins = UIEdgeInsetsMake(20, 20, 28, 20);
	stack.layoutMarginsRelativeArrangement = YES;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[scroll addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
		[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
	]];

	self.nameField = [self textFieldWithPlaceholder:_(@"Name (optional)")];
	self.nameField.text = self.workflow.name ?: @"";
	[stack addArrangedSubview:[self labelWithText:_(@"Name")]];
	[stack addArrangedSubview:self.nameField];

	self.descriptionField = [self textFieldWithPlaceholder:_(@"Description (optional)")];
	self.descriptionField.text = self.workflow.workflowDescription ?: @"";
	[stack addArrangedSubview:[self labelWithText:_(@"Description")]];
	[stack addArrangedSubview:self.descriptionField];

	self.triggerField = [self textFieldWithPlaceholder:_(@"AssetCreate or AssetMetadataExtraction")];
	self.triggerField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.triggerField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.triggerField.text = self.workflow.trigger.length ? self.workflow.trigger : IMWorkflowAssetCreateTrigger;
	[stack addArrangedSubview:[self labelWithText:_(@"Trigger")]];
	[stack addArrangedSubview:self.triggerField];

	UIStackView *enabledRow = [[UIStackView alloc] init];
	enabledRow.axis = UILayoutConstraintAxisHorizontal;
	enabledRow.alignment = UIStackViewAlignmentCenter;
	enabledRow.spacing = 8;
	UILabel *enabledLabel = [self labelWithText:_(@"Enabled")];
	[enabledRow addArrangedSubview:enabledLabel];
	[enabledRow addArrangedSubview:[[UIView alloc] init]];
	self.enabledSwitch = [[UISwitch alloc] init];
	self.enabledSwitch.on = self.workflow ? self.workflow.isEnabled : YES;
	[enabledRow addArrangedSubview:self.enabledSwitch];
	[stack addArrangedSubview:enabledRow];

	[stack addArrangedSubview:[self labelWithText:_(@"Steps (raw JSON array)")]];
	self.stepsView = [[UITextView alloc] init];
	self.stepsView.translatesAutoresizingMaskIntoConstraints = NO;
	self.stepsView.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
	self.stepsView.autocorrectionType = UITextAutocorrectionTypeNo;
	self.stepsView.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.stepsView.layer.borderWidth = 1.0;
	self.stepsView.layer.cornerRadius = 8.0;
	if (@available(iOS 13.0, *)) {
		self.stepsView.layer.borderColor = UIColor.separatorColor.CGColor;
		self.stepsView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	} else {
		self.stepsView.layer.borderColor = UIColor.lightGrayColor.CGColor;
		self.stepsView.backgroundColor = UIColor.whiteColor;
	}
	[self.stepsView.heightAnchor constraintGreaterThanOrEqualToConstant:220.0].active = YES;
	self.stepsView.text = [self stepsJSONString:self.workflow.steps ?: @[]];
	[stack addArrangedSubview:self.stepsView];

	UILabel *hint = [self labelWithText:_(@"Each step needs a method such as plugin#method. Config must be an object or null; enabled defaults to true.")];
	hint.numberOfLines = 0;
	if (@available(iOS 13.0, *)) hint.textColor = UIColor.secondaryLabelColor;
	[stack addArrangedSubview:hint];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.hidesWhenStopped = YES;
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];
}

- (UILabel *)labelWithText:(NSString *)text {
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
	label.adjustsFontForContentSizeCategory = YES;
	return label;
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder {
	UITextField *field = [[UITextField alloc] init];
	field.placeholder = placeholder;
	field.borderStyle = UITextBorderStyleRoundedRect;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.translatesAutoresizingMaskIntoConstraints = NO;
	[field.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
	if (@available(iOS 13.0, *)) field.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	return field;
}

- (NSString *)stepsJSONString:(NSArray<IMWorkflowStep *> *)steps {
	NSMutableArray<NSDictionary *> *raw = [NSMutableArray arrayWithCapacity:steps.count];
	for (IMWorkflowStep *step in steps) [raw addObject:step.requestDictionary];
	NSData *data = [NSJSONSerialization dataWithJSONObject:raw options:NSJSONWritingPrettyPrinted error:nil];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
}

- (void)cancelTapped {
	if (self.saving) return;
	if (self.navigationController) [self.navigationController popViewControllerAnimated:YES];
	else [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showValidation:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Invalid workflow") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSArray<IMWorkflowStep *> *_Nullable)validatedStepsWithError:(NSString *_Nullable __autoreleasing *)message {
	NSString *text = [self.stepsView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (text.length == 0) text = @"[]";
	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
	NSError *jsonError = nil;
	id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;
	if (![json isKindOfClass:[NSArray class]]) {
		if (message) *message = jsonError.localizedDescription.length ? jsonError.localizedDescription : _(@"Steps must be a JSON array.");
		return nil;
	}
	NSMutableArray<IMWorkflowStep *> *steps = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
	NSUInteger index = 0;
	for (id value in (NSArray *)json) {
		if (![value isKindOfClass:[NSDictionary class]]) {
			if (message) *message = [NSString stringWithFormat:_(@"Step %lu must be an object."), (unsigned long)(index + 1)];
			return nil;
		}
		NSDictionary *dictionary = value;
		id methodValue = dictionary[@"method"];
		if (![methodValue isKindOfClass:[NSString class]] || [(NSString *)methodValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) {
			if (message) *message = [NSString stringWithFormat:_(@"Step %lu needs a method."), (unsigned long)(index + 1)];
			return nil;
		}
		id configValue = dictionary[@"config"];
		if (configValue && ![configValue isKindOfClass:[NSDictionary class]] && ![configValue isKindOfClass:[NSNull class]]) {
			if (message) *message = [NSString stringWithFormat:_(@"Step %lu config must be an object or null."), (unsigned long)(index + 1)];
			return nil;
		}
		id enabledValue = dictionary[@"enabled"];
		if (enabledValue && ![enabledValue isKindOfClass:[NSNumber class]]) {
			if (message) *message = [NSString stringWithFormat:_(@"Step %lu enabled must be true or false."), (unsigned long)(index + 1)];
			return nil;
		}
		NSMutableDictionary *normalized = [dictionary mutableCopy];
		normalized[@"method"] = [(NSString *)methodValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!configValue) normalized[@"config"] = [NSNull null];
		if (!enabledValue) normalized[@"enabled"] = @YES;
		IMWorkflowStep *step = [IMWorkflowStep stepWithResponseDictionary:normalized];
		if (!step) {
			if (message) *message = [NSString stringWithFormat:_(@"Step %lu is invalid."), (unsigned long)(index + 1)];
			return nil;
		}
		[steps addObject:step];
		index++;
	}
	return [steps copy];
}

- (void)saveTapped {
	if (self.saving) return;
	NSString *trigger = [self.triggerField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (![trigger isEqualToString:IMWorkflowAssetCreateTrigger] && ![trigger isEqualToString:IMWorkflowMetadataTrigger]) {
		[self showValidation:_(@"Use AssetCreate or AssetMetadataExtraction as the trigger.")];
		return;
	}
	NSString *stepError = nil;
	NSArray<IMWorkflowStep *> *steps = [self validatedStepsWithError:&stepError];
	if (!steps) {
		[self showValidation:stepError ?: _(@"Check the steps JSON and try again.")];
		return;
	}
	NSString *name = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSString *description = [self.descriptionField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	self.saving = YES;
	self.navigationItem.leftBarButtonItem.enabled = NO;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	void (^completion)(IMWorkflow *, NSError *) = ^(IMWorkflow *workflow, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			IMWorkflowEditorViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.saving = NO;
			[strongSelf.spinner stopAnimating];
			strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
			strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
			if (error || !workflow) {
				NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not save this workflow.");
				UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn't save workflow") message:message preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
				[strongSelf presentViewController:alert animated:YES completion:nil];
				return;
			}
			if (strongSelf.onSaved) strongSelf.onSaved(workflow);
			if (strongSelf.navigationController) [strongSelf.navigationController popViewControllerAnimated:YES];
		});
	};
	if (self.workflow) {
		[IMWorkflowApi updateWorkflowId:self.workflow.workflowId
		                           name:name.length ? name : nil
		                    description:description.length ? description : nil
		                        trigger:trigger
		                        enabled:@(self.enabledSwitch.isOn)
		                          steps:steps
		                     completion:completion];
	} else {
		[IMWorkflowApi createWorkflowWithName:name.length ? name : nil
		                          description:description.length ? description : nil
		                              trigger:trigger
		                              enabled:self.enabledSwitch.isOn
		                                steps:steps
		                           completion:completion];
	}
}

@end

@interface WorkflowsViewController ()
@property (nonatomic, copy) NSArray<IMWorkflow *> *workflows;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL mutating;
- (void)showWorkflowActions:(IMWorkflow *)workflow sourceCell:(nullable UITableViewCell *)sourceCell;
- (void)viewShareForWorkflow:(IMWorkflow *)workflow;
@end

@implementation WorkflowsViewController

- (instancetype)init {
	return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Workflows");
	self.workflows = @[];
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithTitle:_(@"Plugins") style:UIBarButtonItemStylePlain target:self action:@selector(pluginsTapped)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTapped)]
	];
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.userInteractionEnabled = YES;
	if (@available(iOS 13.0, *)) self.statusLabel.textColor = UIColor.secondaryLabelColor;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)]];
	self.tableView.backgroundView = self.statusLabel;
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
	if (!self.workflows.count) self.statusLabel.text = _(@"Loading workflows…");
	__weak typeof(self) weakSelf = self;
	[IMWorkflowApi workflowsWithCompletion:^(NSArray<IMWorkflow *> *workflows, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			WorkflowsViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.loading = NO;
			[strongSelf.refresh endRefreshing];
			if (error || !workflows) {
				if (!strongSelf.workflows.count) strongSelf.statusLabel.text = _(@"Couldn't load workflows. Tap to retry.");
				[strongSelf showError:error];
				return;
			}
			strongSelf.workflows = workflows;
			strongSelf.statusLabel.text = workflows.count ? nil : _(@"No workflows configured.");
			[strongSelf.tableView reloadData];
		});
	}];
}

- (void)showError:(NSError *)error {
	if (!self.viewIfLoaded.window) return;
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not complete this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Workflows") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)addTapped {
	[self openEditor:nil];
}

- (void)pluginsTapped {
	[self.navigationController pushViewController:[[PluginsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
}

- (void)openEditor:(IMWorkflow *)workflow {
	__weak typeof(self) weakSelf = self;
	IMWorkflowEditorViewController *editor = [[IMWorkflowEditorViewController alloc] initWithWorkflow:workflow onSaved:^(IMWorkflow *saved) {
		WorkflowsViewController *strongSelf = weakSelf;
		if (strongSelf) [strongSelf reload];
	}];
	[self.navigationController pushViewController:editor animated:YES];
}

- (void)viewShareForWorkflow:(IMWorkflow *)workflow {
	if (!workflow.workflowId.length || self.loading || self.mutating) return;
	self.loading = YES;
	__weak typeof(self) weakSelf = self;
	[IMWorkflowApi workflowShareWithId:workflow.workflowId completion:^(IMWorkflowShareResponse *response, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			WorkflowsViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.loading = NO;
			if (error || !response) {
				[strongSelf showError:error ?: [NSError errorWithDomain:IMApiErrorDomain
				                                                   code:2
				                                               userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid workflow share.")}]];
				return;
			}
			NSMutableArray<NSDictionary *> *steps = [NSMutableArray arrayWithCapacity:response.steps.count];
			for (IMWorkflowStep *step in response.steps) {
				[steps addObject:step.requestDictionary];
			}
			NSDictionary *payload = @{
				@"name": response.name ?: [NSNull null],
				@"description": response.workflowDescription ?: [NSNull null],
				@"trigger": response.trigger,
				@"steps": steps,
			};
			NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:NULL];
			NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
			UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Workflow Share")
			                                                                 message:json ?: _(@"No share payload was returned.")
			                                                          preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:_(@"Copy JSON") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				if (json.length > 0) [UIPasteboard generalPasteboard].string = json;
			}]];
			[alert addAction:[UIAlertAction actionWithTitle:_(@"Close") style:UIAlertActionStyleCancel handler:nil]];
			[strongSelf presentViewController:alert animated:YES completion:nil];
		});
	}];
}

- (void)showWorkflowActions:(IMWorkflow *)workflow sourceCell:(UITableViewCell *)sourceCell {
	if (!workflow || self.loading || self.mutating) return;
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:workflow.name.length ? workflow.name : _(@"Unnamed workflow")
	                                                                  message:nil
	                                                           preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Edit") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		WorkflowsViewController *strongSelf = weakSelf;
		if (strongSelf) [strongSelf openEditor:workflow];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"View Share JSON") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		WorkflowsViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf viewShareForWorkflow:workflow];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = sourceCell ?: self.view;
	sheet.popoverPresentationController.sourceRect = sourceCell ? sourceCell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (NSString *)summaryForWorkflow:(IMWorkflow *)workflow {
	NSString *trigger = workflow.trigger.length ? workflow.trigger : _(@"Unknown trigger");
	NSString *state = workflow.isEnabled ? _(@"Enabled") : _(@"Disabled");
	return [NSString stringWithFormat:_(@"%@ · %@ · %ld steps"), trigger, state, (long)workflow.steps.count];
}

- (void)workflowSwitchChanged:(UISwitch *)sender {
	NSInteger index = sender.tag;
	if (index < 0 || index >= (NSInteger)self.workflows.count || self.mutating) return;
	IMWorkflow *workflow = self.workflows[index];
	BOOL targetEnabled = sender.isOn;
	sender.enabled = NO;
	self.mutating = YES;
	__weak typeof(self) weakSelf = self;
	[IMWorkflowApi setWorkflowId:workflow.workflowId enabled:targetEnabled completion:^(IMWorkflow *updated, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			WorkflowsViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.mutating = NO;
			if (error || !updated) {
				sender.on = workflow.isEnabled;
				sender.enabled = YES;
				[strongSelf showError:error];
				return;
			}
			sender.enabled = YES;
			if (index < (NSInteger)strongSelf.workflows.count) {
				NSMutableArray *copy = [strongSelf.workflows mutableCopy];
				copy[index] = updated;
				strongSelf.workflows = [copy copy];
				[strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
			}
		});
	}];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.workflows.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.workflows.count ? _(@"Server Workflows") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"workflow";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	IMWorkflow *workflow = self.workflows[indexPath.row];
	cell.textLabel.text = workflow.name.length ? workflow.name : _(@"Unnamed workflow");
	cell.detailTextLabel.text = [self summaryForWorkflow:workflow];
	cell.detailTextLabel.numberOfLines = 2;
	cell.accessoryType = UITableViewCellAccessoryNone;
	UISwitch *toggle = [[UISwitch alloc] init];
	toggle.on = workflow.isEnabled;
	toggle.tag = indexPath.row;
	[toggle addTarget:self action:@selector(workflowSwitchChanged:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = toggle;
	cell.accessibilityLabel = cell.textLabel.text;
	cell.accessibilityValue = workflow.isEnabled ? _(@"Enabled") : _(@"Disabled");
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row < (NSInteger)self.workflows.count && !self.loading && !self.mutating) {
		[self showWorkflowActions:self.workflows[indexPath.row] sourceCell:cell];
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.row >= (NSInteger)self.workflows.count || self.mutating) return;
	IMWorkflow *workflow = self.workflows[indexPath.row];
	NSString *name = workflow.name.length ? workflow.name : _(@"Unnamed workflow");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete workflow?") message:name preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		WorkflowsViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = YES;
		strongSelf.tableView.userInteractionEnabled = NO;
		[IMWorkflowApi deleteWorkflowId:workflow.workflowId completion:^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				WorkflowsViewController *inner = weakSelf;
				if (!inner) return;
				inner.mutating = NO;
				inner.tableView.userInteractionEnabled = YES;
				if (!success || error) [inner showError:error];
				else [inner reload];
			});
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
