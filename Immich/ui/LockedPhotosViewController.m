
#import "LockedPhotosViewController.h"
#import "IMAuthApi.h"
#import "IMAssetApi.h"
#import "AssetGridViewController.h"
#import "IMPrefs.h"
#import "IMSession.h"
#import "IMLockedPINStore.h"
#import "IMThumbCache.h"
#import "common.h"
#import <CommonCrypto/CommonDigest.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/Security.h>

static NSString *const kLockedPINAnonymousAccount = @"anonymous";

static NSString *IMLockedPINAccount(void) {
	NSString *userId = IMSession.shared.userId ?: @"";
	NSString *serverURL = IMSession.shared.baseURL.absoluteString ?: @"";
	if (userId.length == 0 && serverURL.length == 0) {
		return kLockedPINAnonymousAccount;
	}
	NSString *scope = [NSString stringWithFormat:@"%@|%@", userId, serverURL];
	NSData *scopeData = [scope dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(scopeData.bytes, (CC_LONG)scopeData.length, digest);
	NSMutableString *account = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
		[account appendFormat:@"%02x", digest[index]];
	}
	return account;
}

static NSMutableDictionary *IMLockedPINKeychainQuery(NSString *account) {
	return [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: IMLockedPINKeychainService,
		(__bridge id)kSecAttrAccount: account.length > 0 ? account : kLockedPINAnonymousAccount,
	} mutableCopy];
}

static BOOL IMStoreLockedPIN(NSString *pin) {
	if (pin.length == 0) {
		return NO;
	}
	if (!IMSession.shared.isLoggedIn) {
		return NO;
	}
	NSMutableDictionary *deleteQuery = IMLockedPINKeychainQuery(IMLockedPINAccount());
	SecItemDelete((__bridge CFDictionaryRef)deleteQuery);

	CFErrorRef accessError = NULL;
	SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
		kCFAllocatorDefault,
		kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
		kSecAccessControlUserPresence,
		&accessError);
	if (accessControl == NULL) {
		if (accessError != NULL) {
			CFRelease(accessError);
		}
		return NO;
	}

	NSMutableDictionary *addQuery = IMLockedPINKeychainQuery(IMLockedPINAccount());
	addQuery[(__bridge id)kSecAttrAccessControl] = (__bridge id)accessControl;
	addQuery[(__bridge id)kSecValueData] = [pin dataUsingEncoding:NSUTF8StringEncoding];
	OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
	CFRelease(accessControl);
	return status == errSecSuccess;
}

static void IMDeleteLockedPIN(void) {
	NSMutableDictionary *query = IMLockedPINKeychainQuery(IMLockedPINAccount());
	SecItemDelete((__bridge CFDictionaryRef)query);
}

static NSString *_Nullable IMReadLockedPIN(LAContext *context) {
	if (!IMSession.shared.isLoggedIn) {
		return nil;
	}
	NSMutableDictionary *query = IMLockedPINKeychainQuery(IMLockedPINAccount());
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	if (context != nil) {
		query[(__bridge id)kSecUseAuthenticationContext] = context;
	}
	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status != errSecSuccess || result == NULL) {
		if (result != NULL) {
			CFRelease(result);
		}
		return nil;
	}
	NSData *data = (__bridge_transfer NSData *)result;
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@interface LockedPhotosViewController ()
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UIButton *unlockButton;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong,nullable) LAContext *authenticationContext;
@property(nonatomic) BOOL elevated;
@property(nonatomic) BOOL localAuthenticated;
@property(nonatomic) BOOL authenticating;
@property(nonatomic) BOOL loadingAssets;
@property(nonatomic) BOOL assetGridPresented;
@property(nonatomic) BOOL observingTabSelection;
@property(nonatomic) BOOL pinConfigured;
@property(nonatomic) NSUInteger accessEpoch;
@property(nonatomic) BOOL serverLockInFlight;
@property(nonatomic) BOOL statusRefreshPending;
@property(nonatomic) BOOL autoPromptedForAppearance;
@property(nonatomic,strong) NSMutableSet<NSString *> *lockedAssetIDs;
@property(nonatomic,weak,nullable) UIAlertController *pinAlert;
@end

@implementation LockedPhotosViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Locked Photos");
	self.lockedAssetIDs = [NSMutableSet set];
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}

	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.text = _(@"Locked photos are protected by your Immich PIN.");
	if (@available(iOS 13.0, *)) {
		self.statusLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.statusLabel.textColor = UIColor.grayColor;
	}

	self.unlockButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.unlockButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.unlockButton setTitle:_(@"Unlock Locked Photos") forState:UIControlStateNormal];
	self.unlockButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
	[self.unlockButton addTarget:self action:@selector(unlockTapped) forControlEvents:UIControlEventTouchUpInside];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.spinner.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:self.statusLabel];
	[self.view addSubview:self.unlockButton];
	[self.view addSubview:self.spinner];
	[NSLayoutConstraint activateConstraints:@[
		[self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.statusLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-50],
		[self.statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:30],
		[self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-30],
		[self.unlockButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.unlockButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:24],
		[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.spinner.topAnchor constraintEqualToAnchor:self.unlockButton.bottomAnchor constant:20],
	]];

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self
	           selector:@selector(appDidEnterBackground:)
	               name:UIApplicationDidEnterBackgroundNotification
	             object:nil];
	[center addObserver:self
	           selector:@selector(sessionDidChange:)
	               name:IMSessionDidChangeNotification
	             object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	self.autoPromptedForAppearance = NO;
	UITabBarController *tabs = self.tabBarController;
	if (tabs != nil && !self.observingTabSelection) {
		[tabs addObserver:self forKeyPath:@"selectedIndex" options:NSKeyValueObservingOptionNew context:NULL];
		self.observingTabSelection = YES;
	}
	if (self.assetGridPresented && self.navigationController.topViewController == self) {
		self.assetGridPresented = NO;
		[self revokeAccessAndPopGrid];
	}
	[self refreshStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	BOOL pushingAssetGrid = self.navigationController.topViewController != self;
	BOOL presentingModal = self.presentedViewController != nil;
	if (!pushingAssetGrid && !presentingModal) {
		[self revokeAccessAndPopGrid];
	}
}

- (void)appDidEnterBackground:(NSNotification *)note {
	(void)note;
	[self revokeAccessAndPopGrid];
}

- (void)sessionDidChange:(NSNotification *)note {
	(void)note;
	if (!IMSession.shared.isLoggedIn) {
		[IMLockedPINStore deleteAllRememberedPINs];
		[self revokeAccessAndPopGrid];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath
	                  ofObject:(id)object
	                    change:(NSDictionary<NSKeyValueChangeKey,id> *)change
	                   context:(void *)context {
	if (![keyPath isEqualToString:@"selectedIndex"] || object != self.tabBarController) {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
		return;
	}
	NSNumber *selected = change[NSKeyValueChangeNewKey];
	UITabBarController *tabs = self.tabBarController;
	NSUInteger ownIndex = [tabs.viewControllers indexOfObject:self.navigationController];
	if ([selected isKindOfClass:[NSNumber class]] && ownIndex != NSNotFound &&
	    selected.integerValue != (NSInteger)ownIndex) {
		[self revokeAccessAndPopGrid];
	}
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self invalidateLockedThumbnails];
	if (self.authenticationContext != nil) {
		[self.authenticationContext invalidate];
	}
	if (self.observingTabSelection && self.tabBarController != nil) {
		[self.tabBarController removeObserver:self forKeyPath:@"selectedIndex"];
	}
}

#pragma mark - Status and local authentication

- (void)refreshStatus {
	if (self.serverLockInFlight) {
		self.statusRefreshPending = YES;
		return;
	}
	self.statusRefreshPending = NO;
	if (!IMPrefs.shared.lockedPhotosBiometricEnabled) {
		IMDeleteLockedPIN();
	}
	NSUInteger epoch = self.accessEpoch;
	__weak typeof(self) weakSelf = self;
	[IMAuthApi authStatusWithCompletion:^(BOOL pinConfigured, BOOL elevated, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			LockedPhotosViewController *strongSelf = weakSelf;
			if (strongSelf == nil || epoch != strongSelf.accessEpoch) {
				return;
			}
			if (error != nil) {
				[strongSelf cancelAuthentication];
				strongSelf.elevated = NO;
				strongSelf.pinConfigured = NO;
				strongSelf.statusLabel.text = _(@"Unable to check locked-photo access.");
				strongSelf.unlockButton.hidden = NO;
				return;
			}

			strongSelf.pinConfigured = pinConfigured;
			strongSelf.elevated = elevated;
			if (!pinConfigured) {
				strongSelf.localAuthenticated = NO;
				IMDeleteLockedPIN();
				strongSelf.unlockButton.hidden = YES;
				strongSelf.statusLabel.text = _(@"No Immich PIN is configured. Set one in the Immich web application first.");
				[strongSelf cancelAuthentication];
				return;
			}

			if (elevated) {
				if (!strongSelf.localAuthenticated && IMPrefs.shared.lockedPhotosBiometricEnabled) {
					strongSelf.autoPromptedForAppearance = YES;
					[strongSelf authenticateLocallyForExistingElevation];
				} else if (!strongSelf.localAuthenticated) {
					strongSelf.elevated = NO;
					strongSelf.unlockButton.hidden = NO;
					if (!strongSelf.autoPromptedForAppearance) {
						strongSelf.autoPromptedForAppearance = YES;
						[strongSelf beginUnlockFlow];
					}
				} else {
					[strongSelf loadAssets];
				}
			} else {
				strongSelf.unlockButton.hidden = NO;
				strongSelf.unlockButton.enabled = !strongSelf.authenticating && !strongSelf.loadingAssets;
				strongSelf.statusLabel.text = IMPrefs.shared.lockedPhotosBiometricEnabled
				    ? _(@"Authenticate with Face ID, Touch ID, or your device passcode, then enter your Immich PIN.")
				    : _(@"Locked photos are protected by your Immich PIN.");
				if (IMPrefs.shared.lockedPhotosBiometricEnabled &&
				    !strongSelf.localAuthenticated && !strongSelf.autoPromptedForAppearance) {
					strongSelf.autoPromptedForAppearance = YES;
					[strongSelf beginUnlockFlow];
				}
			}
		});
	}];
}

- (NSString *)biometricReason {
	return _(@"Authenticate to open Locked Photos.");
}

- (void)authenticateLocallyForExistingElevation {
	if (self.authenticating || self.localAuthenticated || self.loadingAssets) {
		return;
	}
	[self evaluateDeviceOwnerAuthenticationWithCompletion:^(BOOL success, LAContext *context) {
		if (success) {
			self.localAuthenticated = YES;
			[self loadAssets];
			return;
		}
		self.elevated = NO;
		[self presentPINPromptWithMessage:_(@"Enter your six-digit Immich PIN to continue.")];
	}];
}

- (void)evaluateDeviceOwnerAuthenticationWithCompletion:(void (^)(BOOL success, LAContext *_Nullable context))completion {
	LAContext *context = [[LAContext alloc] init];
	context.localizedFallbackTitle = _(@"Enter Immich PIN");
	NSError *canEvaluateError = nil;
	if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&canEvaluateError]) {
		completion(NO, nil);
		return;
	}

	self.authenticationContext = context;
	self.authenticating = YES;
	self.unlockButton.enabled = NO;
	self.statusLabel.text = _(@"Waiting for device authentication…");
	[self.spinner startAnimating];
	NSUInteger epoch = self.accessEpoch;
	__weak typeof(self) weakSelf = self;
	[context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
	       localizedReason:[self biometricReason]
	                 reply:^(BOOL success, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			LockedPhotosViewController *strongSelf = weakSelf;
			if (strongSelf == nil || strongSelf.authenticationContext != context || epoch != strongSelf.accessEpoch) {
				return;
			}
			strongSelf.authenticationContext = nil;
			strongSelf.authenticating = NO;
			[strongSelf.spinner stopAnimating];
			strongSelf.unlockButton.enabled = YES;
			completion(success, success ? context : nil);
		});
	}];
}

- (void)cancelAuthentication {
	LAContext *context = self.authenticationContext;
	self.authenticationContext = nil;
	self.authenticating = NO;
	[context invalidate];
	[self.spinner stopAnimating];
	if (!self.loadingAssets) {
		self.unlockButton.enabled = YES;
	}
}

#pragma mark - Unlock and PIN fallback

- (void)unlockTapped {
	[self beginUnlockFlow];
}

- (void)beginUnlockFlow {
	if (!self.pinConfigured) {
		[self refreshStatus];
		return;
	}
	if (self.authenticating || self.loadingAssets) {
		return;
	}
	if (IMPrefs.shared.lockedPhotosBiometricEnabled) {
		[self evaluateDeviceOwnerAuthenticationWithCompletion:^(BOOL success, LAContext *context) {
			if (success) {
				self.localAuthenticated = YES;
				NSString *storedPIN = IMReadLockedPIN(context);
				if (storedPIN.length > 0) {
					[self unlockServerWithPIN:storedPIN remember:YES];
				} else {
					[self presentPINPromptWithMessage:_(@"Device authentication succeeded. Enter your six-digit Immich PIN once to enable biometric unlock.")];
				}
			} else {
				[self presentPINPromptWithMessage:_(@"Biometric or device authentication was unavailable. Enter your six-digit Immich PIN.")];
			}
		}];
		return;
	}
	[self presentPINPromptWithMessage:_(@"Enter your six-digit Immich PIN.")];
}

- (void)presentPINPromptWithMessage:(NSString *)message {
	if (!self.viewIfLoaded.window || self.navigationController.topViewController != self) {
		return;
	}
	if (self.pinAlert != nil) {
		UIViewController *presenter = self.pinAlert.presentingViewController;
		if ((presenter != nil && presenter.presentedViewController == self.pinAlert) ||
		    self.presentedViewController == self.pinAlert) {
			return;
		}
		self.pinAlert = nil;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Unlock Locked Photos")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = _(@"Six-digit PIN");
		field.keyboardType = UIKeyboardTypeNumberPad;
		field.secureTextEntry = YES;
		field.textContentType = UITextContentTypeOneTimeCode;
	}];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Unlock")
	                                   style:UIAlertActionStyleDefault
	                                 handler:^(UIAlertAction *action) {
		(void)action;
		LockedPhotosViewController *strongSelf = weakSelf;
		if (strongSelf == nil) {
			return;
		}
		NSString *pin = alert.textFields.firstObject.text ?: @"";
		NSCharacterSet *nonDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
		if (pin.length != 6 || [pin rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
			strongSelf.statusLabel.text = _(@"Enter a six-digit PIN.");
			return;
		}
		[strongSelf unlockServerWithPIN:pin remember:IMPrefs.shared.lockedPhotosBiometricEnabled];
	}]];
	self.pinAlert = alert;
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)unlockServerWithPIN:(NSString *)pin remember:(BOOL)remember {
	if (pin.length == 0 || self.loadingAssets) {
		return;
	}
	NSUInteger epoch = self.accessEpoch;
	self.unlockButton.enabled = NO;
	self.statusLabel.text = _(@"Unlocking locked photos…");
	[self.spinner startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMAuthApi unlockSessionWithPIN:pin completion:^(BOOL success, NSError *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			LockedPhotosViewController *strongSelf = weakSelf;
			if (strongSelf == nil || epoch != strongSelf.accessEpoch) {
				if (success && IMSession.shared.isLoggedIn) {
					[IMAuthApi lockSessionWithCompletion:^(BOOL ignored, NSError *ignoredError) {
						(void)ignored;
						(void)ignoredError;
					}];
				}
				return;
			}
			[strongSelf.spinner stopAnimating];
			if (!success) {
				BOOL hadLocalAuthentication = strongSelf.localAuthenticated;
				strongSelf.localAuthenticated = NO;
				strongSelf.unlockButton.enabled = YES;
				strongSelf.elevated = NO;
				if (remember) {
					IMDeleteLockedPIN();
				}
				if (remember && hadLocalAuthentication) {
					[strongSelf presentPINPromptWithMessage:_(@"Enter your six-digit Immich PIN.")];
				} else {
					[strongSelf showError:error ?: [NSError errorWithDomain:@"ImmichLockedPhotos"
					                                                   code:2
					                                               userInfo:@{NSLocalizedDescriptionKey: _(@"The PIN was rejected.")}]];
				}
				return;
			}
			if (remember) {
				(void)IMStoreLockedPIN(pin);
			}
			strongSelf.elevated = YES;
			strongSelf.localAuthenticated = YES;
			[strongSelf loadAssets];
		});
	}];
}

- (void)revokeAccessAndPopGrid {
	UIAlertController *pinAlert = self.pinAlert;
	self.pinAlert = nil;
	UIViewController *pinAlertPresenter = pinAlert.presentingViewController;
	if (pinAlert != nil) {
		if (self.presentedViewController == pinAlert) {
			[self dismissViewControllerAnimated:NO completion:nil];
		} else if (pinAlertPresenter != nil && pinAlertPresenter.presentedViewController == pinAlert) {
			[pinAlertPresenter dismissViewControllerAnimated:NO completion:nil];
		}
	}
	self.accessEpoch += 1;
	[self cancelAuthentication];
	self.localAuthenticated = NO;
	self.autoPromptedForAppearance = NO;
	[self invalidateLockedThumbnails];
	BOOL shouldLockServer = self.elevated || self.loadingAssets;
	self.elevated = NO;
	self.loadingAssets = NO;
	self.unlockButton.hidden = NO;
	self.unlockButton.enabled = YES;
	[self.spinner stopAnimating];
	if (shouldLockServer && IMSession.shared.isLoggedIn && !self.serverLockInFlight) {
		self.serverLockInFlight = YES;
		__weak typeof(self) weakSelf = self;
		[IMAuthApi lockSessionWithCompletion:^(BOOL success, NSError *error) {
			(void)success;
			(void)error;
			dispatch_async(dispatch_get_main_queue(), ^{
				LockedPhotosViewController *strongSelf = weakSelf;
				if (strongSelf == nil) {
					return;
				}
				strongSelf.serverLockInFlight = NO;
				if (strongSelf.statusRefreshPending &&
				    strongSelf.viewIfLoaded.window != nil &&
				    UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
					strongSelf.statusRefreshPending = NO;
					[strongSelf refreshStatus];
				}
			});
		}];
	}
	if (self.navigationController.topViewController != self) {
		[self.navigationController popToViewController:self animated:NO];
	}
}

#pragma mark - Locked asset loading

- (void)loadAssets {
	if (!self.elevated || self.loadingAssets) {
		return;
	}
	if ([self.navigationController.topViewController isKindOfClass:[AssetGridViewController class]]) {
		return;
	}
	self.loadingAssets = YES;
	self.unlockButton.hidden = YES;
	self.statusLabel.text = _(@"Loading locked photos…");
	[self.spinner startAnimating];
	NSUInteger epoch = self.accessEpoch;
	__weak typeof(self) weakSelf = self;
	[IMAssetApi timeBucketsWithVisibility:@"locked"
	                            completion:^(NSArray<NSString *> *dates,
	                                         NSArray<NSNumber *> *counts,
	                                         NSError *bucketError) {
		(void)counts;
		if (bucketError != nil || dates.count == 0) {
			dispatch_async(dispatch_get_main_queue(), ^{
				LockedPhotosViewController *strongSelf = weakSelf;
				if (strongSelf == nil || epoch != strongSelf.accessEpoch) {
					return;
				}
				strongSelf.loadingAssets = NO;
				[strongSelf.spinner stopAnimating];
				strongSelf.unlockButton.hidden = NO;
				strongSelf.statusLabel.text = bucketError ? _(@"Couldn't load locked photos.") : _(@"No locked photos");
				if (bucketError != nil) {
					[strongSelf showError:bucketError];
				}
			});
			return;
		}

		dispatch_group_t group = dispatch_group_create();
		NSMutableArray<IMAsset *> *allAssets = [NSMutableArray array];
		__block NSError *firstError = nil;
		for (NSString *date in dates) {
			dispatch_group_enter(group);
			[IMAssetApi assetsInTimeBucket:date
			                    visibility:@"locked"
			                    completion:^(NSArray<IMAsset *> *assets, NSError *error) {
				if (error != nil) {
					@synchronized (allAssets) {
						if (firstError == nil) {
							firstError = error;
						}
					}
				} else if (assets.count > 0) {
					@synchronized (allAssets) {
						[allAssets addObjectsFromArray:assets];
					}
				}
				dispatch_group_leave(group);
			}];
		}
		dispatch_group_notify(group, dispatch_get_main_queue(), ^{
			LockedPhotosViewController *strongSelf = weakSelf;
			if (strongSelf == nil || epoch != strongSelf.accessEpoch) {
				return;
			}
			strongSelf.loadingAssets = NO;
			[strongSelf.spinner stopAnimating];
			if (firstError != nil) {
				strongSelf.unlockButton.hidden = NO;
				strongSelf.statusLabel.text = _(@"Couldn't load locked photos.");
				[strongSelf showError:firstError];
				return;
			}
			strongSelf.statusLabel.text = allAssets.count > 0
			    ? [NSString stringWithFormat:_(@"%ld locked photos"), (long)allAssets.count]
			    : _(@"No locked photos");
			if (allAssets.count == 0) {
				strongSelf.unlockButton.hidden = NO;
				return;
			}
			AssetGridViewController *grid = [AssetGridViewController gridWithTitle:_(@"Locked Photos")
		                                                                       assets:allAssets];
			for (IMAsset *asset in allAssets) {
				if (asset.assetId.length > 0) {
					[strongSelf.lockedAssetIDs addObject:asset.assetId];
				}
			}
			strongSelf.assetGridPresented = YES;
			[strongSelf.navigationController pushViewController:grid animated:YES];
		});
	}];
}

- (void)invalidateLockedThumbnails {
	NSSet<NSString *> *assetIDs = [self.lockedAssetIDs copy];
	[self.lockedAssetIDs removeAllObjects];
	if (assetIDs.count == 0) {
		return;
	}
	[[IMThumbCache shared] invalidateThumbnailsForAssetIds:assetIDs completion:^{}];
}

- (void)showError:(NSError *)error {
	NSString *message = error.localizedDescription ?: _(@"The PIN was rejected.");
	if (!self.viewIfLoaded.window || self.navigationController.topViewController != self) {
		self.statusLabel.text = message;
		return;
	}
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Unlock Failed")
	                                                                 message:message
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
