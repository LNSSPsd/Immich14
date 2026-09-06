#import "WorkflowsViewController.h"
#import "IMWorkflowApi.h"
#import "IMWorkflow.h"
#import "IMWorkflowStep.h"
#import "IMApiClient.h"
#import "IMPluginApi.h"
#import "PluginsViewController.h"
#import "common.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

static NSString *const IMWorkflowAssetCreateTrigger = @"AssetCreate";
static NSString *const IMWorkflowMetadataTrigger = @"AssetMetadataExtraction";

static BOOL IMWorkflowSchemaBoolean(id value) {
	return [value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static BOOL IMWorkflowSchemaNumber(id value) {
	return [value isKindOfClass:[NSNumber class]] && !IMWorkflowSchemaBoolean(value) && isfinite([(NSNumber *)value doubleValue]);
}

static NSString *IMWorkflowSchemaTypeDescription(NSDictionary *schema) {
	if (![schema isKindOfClass:[NSDictionary class]]) return _(@"value");
	BOOL isArray = IMWorkflowSchemaBoolean(schema[@"array"]) && [schema[@"array"] boolValue];
	NSString *type = [schema[@"type"] isKindOfClass:[NSString class]] ? schema[@"type"] : @"object";
	if (isArray) return [NSString stringWithFormat:_(@"array of %@"), type];
	return type;
}

static NSString *IMWorkflowSchemaFieldDescription(NSDictionary *schema) {
	if (![schema isKindOfClass:[NSDictionary class]]) return _(@"value");
	NSMutableString *description = [NSMutableString stringWithString:IMWorkflowSchemaTypeDescription(schema)];
	id enumeration = schema[@"enum"];
	if ([enumeration isKindOfClass:[NSArray class]] && [enumeration count] > 0) {
		NSMutableArray<NSString *> *values = [NSMutableArray array];
		for (id value in (NSArray *)enumeration) {
			if ([value isKindOfClass:[NSString class]]) [values addObject:value];
		}
		if (values.count == [enumeration count]) [description appendFormat:_(@", one of %@"), [values componentsJoinedByString:@", "]];
	}
	return [description copy];
}

static NSString *IMWorkflowSchemaGuidance(NSDictionary *schema) {
	if (![schema isKindOfClass:[NSDictionary class]]) return nil;
	NSDictionary *properties = [schema[@"properties"] isKindOfClass:[NSDictionary class]] ? schema[@"properties"] : nil;
	NSArray *required = [schema[@"required"] isKindOfClass:[NSArray class]] ? schema[@"required"] : nil;
	NSMutableArray<NSString *> *requiredFields = [NSMutableArray array];
	for (id key in required) {
		if (![key isKindOfClass:[NSString class]]) continue;
		NSDictionary *fieldSchema = [properties[key] isKindOfClass:[NSDictionary class]] ? properties[key] : nil;
		NSString *detail = fieldSchema ? IMWorkflowSchemaFieldDescription(fieldSchema) : _(@"value");
		[requiredFields addObject:[NSString stringWithFormat:_(@"%@ (%@)"), key, detail]];
	}
	if (!requiredFields.count) return nil;
	return [NSString stringWithFormat:_(@"Required config fields: %@. Edit the JSON below to provide these values before saving."),
	        [requiredFields componentsJoinedByString:@", "]];
}

static BOOL IMWorkflowSchemaValidateValue(id value,
	                                         NSDictionary *schema,
	                                         NSString *path,
	                                         NSString **message) {
	if (![schema isKindOfClass:[NSDictionary class]]) return YES;
	if ([value isKindOfClass:[NSNull class]] || value == nil) {
		if (message) *message = [NSString stringWithFormat:_(@"%@ must have a value."), path];
		return NO;
	}

	BOOL isArray = IMWorkflowSchemaBoolean(schema[@"array"]) && [schema[@"array"] boolValue];
	if (isArray) {
		if (![value isKindOfClass:[NSArray class]]) {
			if (message) *message = [NSString stringWithFormat:_(@"%@ must be an array."), path];
			return NO;
		}
		NSMutableDictionary *itemSchema = [schema mutableCopy];
		[itemSchema removeObjectForKey:@"array"];
		NSUInteger index = 0;
		for (id item in (NSArray *)value) {
			NSString *itemPath = [NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)index];
			if (!IMWorkflowSchemaValidateValue(item, itemSchema, itemPath, message)) return NO;
			index++;
		}
		return YES;
	}

	NSString *type = [schema[@"type"] isKindOfClass:[NSString class]] ? schema[@"type"] : @"object";
	NSDictionary *properties = [schema[@"properties"] isKindOfClass:[NSDictionary class]] ? schema[@"properties"] : nil;
	BOOL valid = YES;
	if ([type isEqualToString:@"object"]) {
		if (![value isKindOfClass:[NSDictionary class]]) valid = NO;
		if (valid) {
			id required = schema[@"required"];
			if ([required isKindOfClass:[NSArray class]]) {
				for (id requiredKey in (NSArray *)required) {
					if (![requiredKey isKindOfClass:[NSString class]]) continue;
					id requiredValue = ((NSDictionary *)value)[requiredKey];
					if (requiredValue == nil || [requiredValue isKindOfClass:[NSNull class]]) {
						if (message) *message = [NSString stringWithFormat:_(@"%@ is required."), [path stringByAppendingPathComponent:requiredKey]];
						return NO;
					}
				}
			}
			for (NSString *key in properties) {
				id child = ((NSDictionary *)value)[key];
				if (child == nil) continue;
				NSDictionary *childSchema = [properties[key] isKindOfClass:[NSDictionary class]] ? properties[key] : nil;
				if (!childSchema) continue;
				if (!IMWorkflowSchemaValidateValue(child, childSchema, [path stringByAppendingPathComponent:key], message)) return NO;
			}
		}
	} else if ([type isEqualToString:@"string"]) {
		valid = [value isKindOfClass:[NSString class]];
	} else if ([type isEqualToString:@"number"]) {
		valid = IMWorkflowSchemaNumber(value);
	} else if ([type isEqualToString:@"integer"]) {
		valid = IMWorkflowSchemaNumber(value) && floor([(NSNumber *)value doubleValue]) == [(NSNumber *)value doubleValue];
	} else if ([type isEqualToString:@"boolean"]) {
		valid = IMWorkflowSchemaBoolean(value);
	}
	if (!valid) {
		if (message) *message = [NSString stringWithFormat:_(@"%@ has the wrong type."), path];
		return NO;
	}

	id enumeration = schema[@"enum"];
	if ([type isEqualToString:@"string"] && [enumeration isKindOfClass:[NSArray class]]) {
		BOOL stringChoices = YES;
		for (id choice in (NSArray *)enumeration) {
			if (![choice isKindOfClass:[NSString class]]) { stringChoices = NO; break; }
		}
		if (stringChoices && [enumeration count] > 0 && ![(NSArray *)enumeration containsObject:value]) {
			if (message) *message = [NSString stringWithFormat:_(@"%@ must be one of %@."), path, [(NSArray *)enumeration componentsJoinedByString:@", "]];
			return NO;
		}
	}
	if (IMWorkflowSchemaNumber(value)) {
		double number = [(NSNumber *)value doubleValue];
		id minimum = schema[@"minimum"];
		id maximum = schema[@"maximum"];
		if (IMWorkflowSchemaNumber(minimum) && number < [minimum doubleValue]) {
			if (message) *message = [NSString stringWithFormat:_(@"%@ must be at least %@."), path, minimum];
			return NO;
		}
		if (IMWorkflowSchemaNumber(maximum) && number > [maximum doubleValue]) {
			if (message) *message = [NSString stringWithFormat:_(@"%@ must be at most %@."), path, maximum];
			return NO;
		}
	}
	return YES;
}

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
@property (nonatomic, strong) UIButton *insertMethodButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic) BOOL saving;
@property (nonatomic) BOOL loadingMethods;
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

	self.insertMethodButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.insertMethodButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.insertMethodButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	[self.insertMethodButton setTitle:_(@"Insert plugin step…") forState:UIControlStateNormal];
	self.insertMethodButton.accessibilityHint = _(@"Loads enabled plugin methods for the selected trigger and appends one to the raw JSON.");
	[self.insertMethodButton addTarget:self action:@selector(insertMethodTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.insertMethodButton.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
	[stack addArrangedSubview:self.insertMethodButton];

	UILabel *hint = [self labelWithText:_(@"Each step needs a method such as plugin#method. Config must be an object or null; enabled defaults to true. Config values are checked against the selected plugin method schema before saving.")];
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

- (void)insertMethodTapped {
	if (self.saving || self.loadingMethods) return;
	NSString *trigger = [self.triggerField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (![trigger isEqualToString:IMWorkflowAssetCreateTrigger] && ![trigger isEqualToString:IMWorkflowMetadataTrigger]) {
		[self showValidation:_(@"Use AssetCreate or AssetMetadataExtraction as the trigger before choosing a plugin method.")];
		return;
	}
	self.loadingMethods = YES;
	self.insertMethodButton.enabled = NO;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMPluginApi pluginMethodsWithDescription:nil
	                                  enabled:@YES
	                                       id:nil
	                                     name:nil
	                               pluginName:nil
	                            pluginVersion:nil
	                                    title:nil
	                                  trigger:trigger
	                                     type:nil
	                               completion:^(NSArray<IMPluginMethod *> *methods, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			IMWorkflowEditorViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.loadingMethods = NO;
			strongSelf.insertMethodButton.enabled = YES;
			strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
			[strongSelf.spinner stopAnimating];
			if (error || !methods) {
				[strongSelf showValidation:error.localizedDescription.length ? error.localizedDescription : _(@"Couldn't load plugin methods. Check the server connection and try again.")];
				return;
			}
			if (!methods.count) {
				[strongSelf showValidation:_(@"No enabled plugin methods support this trigger.")];
				return;
			}
			[strongSelf presentMethodPicker:methods];
		});
	}];
}

- (void)presentMethodPicker:(NSArray<IMPluginMethod *> *)methods {
	NSArray<IMPluginMethod *> *sorted = [methods sortedArrayUsingComparator:^NSComparisonResult(IMPluginMethod *first, IMPluginMethod *second) {
		NSString *firstName = first.title.length ? first.title : first.key;
		NSString *secondName = second.title.length ? second.title : second.key;
		return [firstName localizedCaseInsensitiveCompare:secondName];
	}];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Insert plugin step")
	                                                                  message:_(@"Choose an enabled method for this workflow trigger.")
	                                                           preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	for (IMPluginMethod *method in sorted) {
		NSString *name = method.title.length ? method.title : method.name;
		NSString *title = [NSString stringWithFormat:_(@"%@ (%@)"), name.length ? name : method.key, method.key];
		[sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
			IMWorkflowEditorViewController *strongSelf = weakSelf;
			if (strongSelf) [strongSelf appendMethod:method];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.insertMethodButton;
	sheet.popoverPresentationController.sourceRect = self.insertMethodButton.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)appendMethod:(IMPluginMethod *)method {
	if (!method.key.length) return;
	NSString *text = [self.stepsView.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!text.length) text = @"[]";
	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
	NSError *error = nil;
	id json = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error] : nil;
	if (![json isKindOfClass:[NSArray class]]) {
		[self showValidation:error.localizedDescription.length ? error.localizedDescription : _(@"Fix the steps JSON before inserting a plugin method.")];
		return;
	}
	NSMutableArray *steps = [NSMutableArray arrayWithArray:(NSArray *)json];
	NSDictionary *schema = method.schema;
	[steps addObject:@{
		@"method": method.key,
		@"config": schema.count ? @{} : [NSNull null],
		@"enabled": @YES,
	}];
	NSData *updatedData = [NSJSONSerialization dataWithJSONObject:steps options:NSJSONWritingPrettyPrinted error:&error];
	if (!updatedData) {
		[self showValidation:error.localizedDescription.length ? error.localizedDescription : _(@"Couldn't update the steps JSON.")];
		return;
	}
	self.stepsView.text = [[NSString alloc] initWithData:updatedData encoding:NSUTF8StringEncoding];
	NSString *guidance = IMWorkflowSchemaGuidance(schema);
	if (guidance.length) {
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Plugin step added") message:guidance preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (void)validateStepMethods:(NSArray<IMWorkflowStep *> *)steps
                    trigger:(NSString *)trigger
                 completion:(void (^)(NSString *_Nullable message))completion {
	[IMPluginApi pluginMethodsWithDescription:nil
	                                  enabled:@YES
	                                       id:nil
	                                     name:nil
	                               pluginName:nil
	                            pluginVersion:nil
	                                    title:nil
	                                  trigger:trigger
	                                     type:nil
	                               completion:^(NSArray<IMPluginMethod *> *methods, NSError *error) {
		if (error || !methods) {
			completion(error.localizedDescription.length ? error.localizedDescription : _(@"Couldn't validate plugin methods. Check the server connection and try again."));
			return;
		}
		NSMutableSet<NSString *> *available = [NSMutableSet setWithCapacity:methods.count];
		NSMutableDictionary<NSString *, IMPluginMethod *> *methodsByKey = [NSMutableDictionary dictionaryWithCapacity:methods.count];
		for (IMPluginMethod *method in methods) {
			if (method.key.length) {
				[available addObject:method.key];
				methodsByKey[method.key] = method;
			}
		}
		NSUInteger index = 0;
		for (IMWorkflowStep *step in steps) {
			index++;
			if (![available containsObject:step.method]) {
				completion([NSString stringWithFormat:_(@"Step %lu uses an unavailable method: %@"), (unsigned long)index, step.method]);
				return;
			}
			IMPluginMethod *method = methodsByKey[step.method];
			if (method.schema.count > 0) {
				NSString *schemaError = nil;
				NSDictionary *config = step.config ?: @{};
				if (!IMWorkflowSchemaValidateValue(config, method.schema, _(@"config"), &schemaError)) {
					completion([NSString stringWithFormat:_(@"Step %lu configuration is invalid: %@"),
					            (unsigned long)index, schemaError ?: _(@"Check the plugin schema.")]);
					return;
				}
			}
		}
		completion(nil);
	}];
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
	[self validateStepMethods:steps trigger:trigger completion:^(NSString *validationError) {
		dispatch_async(dispatch_get_main_queue(), ^{
			IMWorkflowEditorViewController *strongSelf = weakSelf;
			if (!strongSelf) return;
			if (validationError.length) {
				strongSelf.saving = NO;
				[strongSelf.spinner stopAnimating];
				strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
				strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
				[strongSelf showValidation:validationError];
				return;
			}
			if (strongSelf.workflow) {
				[IMWorkflowApi updateWorkflowId:strongSelf.workflow.workflowId
				                           name:name.length ? name : nil
				                    description:description.length ? description : nil
				                        trigger:trigger
				                        enabled:@(strongSelf.enabledSwitch.isOn)
				                          steps:steps
				                     completion:completion];
			} else {
				[IMWorkflowApi createWorkflowWithName:name.length ? name : nil
				                          description:description.length ? description : nil
				                              trigger:trigger
				                              enabled:strongSelf.enabledSwitch.isOn
				                                steps:steps
				                           completion:completion];
			}
		});
	}];
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
