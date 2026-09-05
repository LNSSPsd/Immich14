#import "MemoryDetailViewController.h"
#import "AssetGridViewController.h"
#import "IMMemoryApi.h"
#import "MemoryEditorViewController.h"
#import "common.h"

@interface MemoryDetailViewController ()
@property (nonatomic, strong) IMMemory *memory;
@property (nonatomic, strong) UIBarButtonItem *saveButton;
@property (nonatomic, strong) UIBarButtonItem *editButton;
@property (nonatomic, strong) AssetGridViewController *grid;
@property (nonatomic) NSUInteger loadGeneration;
@end

@implementation MemoryDetailViewController

+ (instancetype)viewControllerForMemory:(IMMemory *)memory {
	MemoryDetailViewController *vc = [[self alloc] init];
	vc.memory = memory;
	return vc;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Memory");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}
	self.saveButton = [[UIBarButtonItem alloc] initWithImage:nil
	                                                     style:UIBarButtonItemStylePlain
	                                                    target:self
	                                                    action:@selector(toggleSaved)];
	self.editButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit
	                                                                    target:self
	                                                                    action:@selector(editMemory)];
	self.navigationItem.rightBarButtonItems = @[
		self.editButton,
		self.saveButton,
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(deleteMemory)],
	];
	[self updateSaveButton];
	[self installGrid];
}

- (void)installGrid {
	if (self.grid) {
		[self.grid willMoveToParentViewController:nil];
		[self.grid.view removeFromSuperview];
		[self.grid removeFromParentViewController];
	}
	self.grid = [AssetGridViewController gridWithTitle:@"" assets:self.memory.assets ?: @[]];
	[self addChildViewController:self.grid];
	self.grid.view.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.grid.view];
	[NSLayoutConstraint activateConstraints:@[
		[self.grid.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.grid.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.grid.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.grid.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
	[self.grid didMoveToParentViewController:self];
}

- (void)updateSaveButton {
	if (@available(iOS 13.0, *)) {
		self.saveButton.image = [UIImage systemImageNamed:self.memory.isSaved ? @"bookmark.fill" : @"bookmark"];
	} else {
		self.saveButton.title = self.memory.isSaved ? _(@"Saved") : _(@"Save");
	}
	self.saveButton.accessibilityLabel = self.memory.isSaved ? _(@"Unsave memory") : _(@"Save memory");
}

- (void)toggleSaved {
	self.saveButton.enabled = NO;
	BOOL saved = !self.memory.isSaved;
	__weak typeof(self) weakSelf = self;
	[IMMemoryApi updateMemoryId:self.memory.memoryId
	                    isSaved:saved
	                 completion:^(IMMemory *_Nullable memory, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.saveButton.enabled = YES;
		if (memory) {
			strongSelf.memory = memory;
			[strongSelf updateSaveButton];
			return;
		}
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn't update memory")
		                                                                 message:error.localizedDescription
		                                                          preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		[strongSelf presentViewController:alert animated:YES completion:nil];
	}];
}

- (void)editMemory {
	if (!self.memory || self.navigationController.topViewController != self) return;
	MemoryEditorViewController *editor = [[MemoryEditorViewController alloc] initWithMemory:self.memory];
	__weak typeof(self) weakSelf = self;
	editor.onSaved = ^(IMMemory *memory) {
		MemoryDetailViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.memory = memory;
		[strongSelf updateSaveButton];
		[strongSelf installGrid];
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)deleteMemory {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Delete memory?")
	                                                                 message:_(@"The photos will stay in your library.")
	                                                          preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		strongSelf.navigationItem.rightBarButtonItems = @[];
		[IMMemoryApi deleteMemoryId:strongSelf.memory.memoryId completion:^(BOOL success, NSError *_Nullable error) {
			if (success) {
				[strongSelf.navigationController popViewControllerAnimated:YES];
				return;
			}
			strongSelf.navigationItem.rightBarButtonItems = @[
				strongSelf.saveButton,
				[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
				                                                target:strongSelf
				                                                action:@selector(deleteMemory)],
			];
			UIAlertController *failure = [UIAlertController alertControllerWithTitle:_(@"Couldn't delete memory")
			                                                                    message:error.localizedDescription
			                                                             preferredStyle:UIAlertControllerStyleAlert];
			[failure addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
			[strongSelf presentViewController:failure animated:YES completion:nil];
		}];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
