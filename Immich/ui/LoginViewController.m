#import "LoginViewController.h"
#import "common.h"
#import "IMAuthApi.h"

static NSString *const kLastServerURLDefaultsKey = @"IMLastServerURL";

@interface IMLoginTextField : UITextField
@end

@implementation IMLoginTextField

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		if (@available(iOS 13.0, *)) {
			self.backgroundColor = UIColor.tertiarySystemBackgroundColor;
		} else {
			self.backgroundColor = UIColor.groupTableViewBackgroundColor;
		}
		self.layer.cornerRadius = 12;
		self.font = [UIFont systemFontOfSize:16];
		self.leftViewMode = UITextFieldViewModeAlways;
		self.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
	}
	return self;
}

- (void)setLeftSymbolName:(NSString *)symbolName {
	if (@available(iOS 13.0, *)) {
		UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(14, 12, 20, 20)];
		iconView.image = [UIImage systemImageNamed:symbolName];
		iconView.tintColor = UIColor.secondaryLabelColor;
		iconView.contentMode = UIViewContentModeScaleAspectFit;
		UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 44)];
		[container addSubview:iconView];
		self.leftView = container;
	}
}

- (CGRect)textRectForBounds:(CGRect)bounds {
	return CGRectMake(48, 0, bounds.size.width - 48 - 12, bounds.size.height);
}
- (CGRect)editingRectForBounds:(CGRect)bounds {
	return [self textRectForBounds:bounds];
}
- (CGRect)placeholderRectForBounds:(CGRect)bounds {
	return [self textRectForBounds:bounds];
}

@end

@interface LoginViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) IMLoginTextField *serverField;
@property (nonatomic, strong) IMLoginTextField *emailField;
@property (nonatomic, strong) IMLoginTextField *passwordField;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation LoginViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = nil;
	self.navigationController.navigationBarHidden = YES;
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}

	self.scrollView = [[UIScrollView alloc] init];
	self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	[self.view addSubview:self.scrollView];

	self.contentView = [[UIView alloc] init];
	self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.scrollView addSubview:self.contentView];

	UIView *badge = [self appIconBadge];
	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	titleLabel.text = _(@"Immich 14");
	titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
	titleLabel.textAlignment = NSTextAlignmentCenter;

	UILabel *subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	subtitleLabel.text = _(@"Sign in to your server");
	subtitleLabel.font = [UIFont systemFontOfSize:15];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	if (@available(iOS 13.0, *)) {
		subtitleLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		subtitleLabel.textColor = UIColor.grayColor;
	}

	self.serverField = [[IMLoginTextField alloc] init];
	self.serverField.placeholder = _(@"Server URL (e.g. 192.168.1.50:2283)");
	[self.serverField setLeftSymbolName:@"server.rack"];
	self.serverField.keyboardType = UIKeyboardTypeURL;
	self.serverField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.serverField.text = [[NSUserDefaults standardUserDefaults] stringForKey:kLastServerURLDefaultsKey];
	[self configureField:self.serverField];

	self.emailField = [[IMLoginTextField alloc] init];
	self.emailField.placeholder = _(@"Email");
	[self.emailField setLeftSymbolName:@"envelope"];
	self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
	self.emailField.autocorrectionType = UITextAutocorrectionTypeNo;
	[self configureField:self.emailField];

	self.passwordField = [[IMLoginTextField alloc] init];
	self.passwordField.placeholder = _(@"Password");
	[self.passwordField setLeftSymbolName:@"lock"];
	self.passwordField.secureTextEntry = YES;
	self.passwordField.returnKeyType = UIReturnKeyGo;
	[self configureField:self.passwordField];

	UIStackView *fieldStack = [[UIStackView alloc] initWithArrangedSubviews:@[
		self.serverField, self.emailField, self.passwordField
	]];
	fieldStack.axis = UILayoutConstraintAxisVertical;
	fieldStack.spacing = 12;
	fieldStack.translatesAutoresizingMaskIntoConstraints = NO;

	self.errorLabel = [[UILabel alloc] init];
	self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
	if (@available(iOS 13.0, *)) {
		self.errorLabel.textColor = UIColor.systemRedColor;
	} else {
		self.errorLabel.textColor = UIColor.redColor;
	}
	self.errorLabel.numberOfLines = 0;
	self.errorLabel.textAlignment = NSTextAlignmentCenter;
	self.errorLabel.font = [UIFont systemFontOfSize:13];

	self.loginButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[self.loginButton setTitle:_(@"Log In") forState:UIControlStateNormal];
	self.loginButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.loginButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
	[self.loginButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
	[self.loginButton setTitleColor:UIColor.whiteColor forState:UIControlStateHighlighted];
	if (@available(iOS 13.0, *)) {
		self.loginButton.backgroundColor = UIColor.systemBlueColor;
	} else {
		self.loginButton.backgroundColor = [UIColor colorWithRed:0 green:0.478 blue:1 alpha:1];
	}
	self.loginButton.layer.cornerRadius = 12;
	[self.loginButton.heightAnchor constraintEqualToConstant:50].active = YES;
	[self.loginButton addTarget:self action:@selector(loginTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.loginButton addTarget:self action:@selector(loginButtonTouchDown:) forControlEvents:UIControlEventTouchDown];
	[self.loginButton addTarget:self
	                      action:@selector(loginButtonTouchUp:)
	            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
	                              UIControlEventTouchCancel | UIControlEventTouchDragExit];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
	self.spinner.hidesWhenStopped = YES;
	self.spinner.color = UIColor.whiteColor;
	[self.loginButton addSubview:self.spinner];
	[self.spinner.centerXAnchor constraintEqualToAnchor:self.loginButton.centerXAnchor].active = YES;
	[self.spinner.centerYAnchor constraintEqualToAnchor:self.loginButton.centerYAnchor].active = YES;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
		badge, titleLabel, subtitleLabel, fieldStack, self.errorLabel, self.loginButton
	]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.alignment = UIStackViewAlignmentFill;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[stack setCustomSpacing:16 afterView:badge];
	[stack setCustomSpacing:4 afterView:titleLabel];
	[stack setCustomSpacing:36 afterView:subtitleLabel];
	[stack setCustomSpacing:8 afterView:fieldStack];
	[stack setCustomSpacing:20 afterView:self.errorLabel];
	[self.contentView addSubview:stack];

	[NSLayoutConstraint activateConstraints:@[
		[self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

		[self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
		[self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
		[self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
		[self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
		[self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],
		[self.contentView.heightAnchor constraintGreaterThanOrEqualToAnchor:self.scrollView.heightAnchor],

		[badge.widthAnchor constraintEqualToConstant:72],
		[badge.heightAnchor constraintEqualToConstant:72],

		[stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:32],
		[stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-32],
		[stack.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:40],
		[stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-24],
	]];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(keyboardWillChangeFrame:)
	                                              name:UIKeyboardWillChangeFrameNotification
	                                            object:nil];

	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
	[self.scrollView addGestureRecognizer:tap];
}

- (UIView *)appIconBadge {
	UIImageView *icon = [[UIImageView alloc] init];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.contentMode = UIViewContentModeScaleAspectFit;
	if (@available(iOS 13.0, *)) {
		icon.tintColor = UIColor.systemBlueColor;
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightSemibold];
		icon.image = [UIImage systemImageNamed:@"photo.on.rectangle" withConfiguration:config];
	}
	return icon;
}

- (void)configureField:(IMLoginTextField *)field {
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	field.returnKeyType = UIReturnKeyNext;
	field.delegate = self;
	[field.heightAnchor constraintEqualToConstant:48].active = YES;
}

- (void)keyboardWillChangeFrame:(NSNotification *)note {
	CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect localFrame = [self.view convertRect:endFrame fromView:nil];
	CGFloat overlap = MAX(0, CGRectGetMaxY(self.scrollView.frame) - localFrame.origin.y);
	self.scrollView.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
	self.scrollView.scrollIndicatorInsets = self.scrollView.contentInset;
}

- (void)dismissKeyboard {
	[self.view endEditing:YES];
}

- (void)loginButtonTouchDown:(UIButton *)sender {
	sender.alpha = 0.7; 
}

- (void)loginButtonTouchUp:(UIButton *)sender {
	[UIView animateWithDuration:0.12 animations:^{
		sender.alpha = 1.0;
	}];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	if (textField == self.serverField) {
		[self.emailField becomeFirstResponder];
	} else if (textField == self.emailField) {
		[self.passwordField becomeFirstResponder];
	} else {
		[self loginTapped];
	}
	return YES;
}

#pragma mark - Login

- (nullable NSURL *)normalizedBaseURLFromInput:(NSString *)raw {
	NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (trimmed.length == 0) {
		return nil;
	}
	if (![trimmed hasPrefix:@"http://"] && ![trimmed hasPrefix:@"https://"]) {
		trimmed = [@"http://" stringByAppendingString:trimmed];
	}
	while ([trimmed hasSuffix:@"/"]) {
		trimmed = [trimmed substringToIndex:trimmed.length - 1];
	}
	if (![trimmed hasSuffix:@"/api"]) {
		trimmed = [trimmed stringByAppendingString:@"/api"];
	}
	return [NSURL URLWithString:trimmed];
}

- (void)loginTapped {
	[self dismissKeyboard];

	NSURL *baseURL = [self normalizedBaseURLFromInput:self.serverField.text ?: @""];
	NSString *email = [self.emailField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *password = self.passwordField.text ?: @"";

	if (!baseURL) {
		self.errorLabel.text = _(@"Enter a server URL.");
		return;
	}
	if (email.length == 0 || password.length == 0) {
		self.errorLabel.text = _(@"Enter email and password.");
		return;
	}

	self.errorLabel.text = @"";
	self.loginButton.enabled = NO;
	[self.loginButton setTitle:@"" forState:UIControlStateNormal];
	[self.spinner startAnimating];

	__weak typeof(self) weakSelf = self;
	[IMAuthApi loginWithBaseURL:baseURL
	                       email:email
	                    password:password
	                  completion:^(BOOL success, NSError *_Nullable error) {
		    typeof(self) strongSelf = weakSelf;
		    if (!strongSelf) {
			    return;
		    }
		    [strongSelf.spinner stopAnimating];
		    strongSelf.loginButton.enabled = YES;
		    [strongSelf.loginButton setTitle:_(@"Log In") forState:UIControlStateNormal];
		    if (!success) {
			    strongSelf.errorLabel.text = error.localizedDescription ?: _(@"Login failed.");
			    return;
		    }
		    [[NSUserDefaults standardUserDefaults] setObject:strongSelf.serverField.text
		                                               forKey:kLastServerURLDefaultsKey];
	    }];
}

@end
