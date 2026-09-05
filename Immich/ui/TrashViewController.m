#import "TrashViewController.h"
#import "IMAssetApi.h"
#import "IMAssetManagementApi.h"
#import "AssetGridViewController.h"
#import "common.h"

@interface TrashViewController ()
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UIButton *browseButton;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) NSArray<IMAsset *> *assets;
@end

@implementation TrashViewController
- (void)viewDidLoad {
 [super viewDidLoad]; self.title = _(@"Trash"); self.assets = @[];
 self.view.backgroundColor = UIColor.systemBackgroundColor;
 self.statusLabel = [[UILabel alloc] init]; self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO; self.statusLabel.textAlignment = NSTextAlignmentCenter; self.statusLabel.numberOfLines = 0;
 self.browseButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.browseButton.translatesAutoresizingMaskIntoConstraints = NO; [self.browseButton setTitle:_(@"Browse Deleted Photos") forState:UIControlStateNormal]; [self.browseButton addTarget:self action:@selector(browse) forControlEvents:UIControlEventTouchUpInside];
 self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
 [self.view addSubview:self.statusLabel]; [self.view addSubview:self.browseButton]; [self.view addSubview:self.spinner];
 [NSLayoutConstraint activateConstraints:@[[self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[self.statusLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-60],[self.statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],[self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],[self.browseButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[self.browseButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:20],[self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[self.spinner.topAnchor constraintEqualToAnchor:self.browseButton.bottomAnchor constant:16]]];
 self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_(@"Actions") style:UIBarButtonItemStylePlain target:self action:@selector(actions)];
 [self reload];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; }
- (void)reload {
 [self.spinner startAnimating]; __weak typeof(self) weakSelf = self;
 [IMAssetApi timeBucketsWithVisibility:nil isTrashed:YES completion:^(NSArray<NSString *> *dates, NSArray<NSNumber *> *counts, NSError *error) {
  if (error || dates.count == 0) { dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.assets=@[]; [weakSelf.spinner stopAnimating]; weakSelf.statusLabel.text=error ? _(@"Unable to load Trash.") : _(@"Trash is empty"); weakSelf.browseButton.hidden=YES; if(error)[weakSelf showError:error]; }); return; }
  dispatch_group_t group=dispatch_group_create(); NSMutableArray *all=[NSMutableArray array]; __block NSError *firstError;
  for(NSString *date in dates){ dispatch_group_enter(group); [IMAssetApi assetsInTimeBucket:date visibility:nil isTrashed:YES completion:^(NSArray<IMAsset *> *a,NSError *e){ if(e) firstError=e; else @synchronized(all){[all addObjectsFromArray:a ?: @[]];} dispatch_group_leave(group);}]; }
  dispatch_group_notify(group, dispatch_get_main_queue(), ^{ weakSelf.assets=all; [weakSelf.spinner stopAnimating]; weakSelf.statusLabel.text=[NSString stringWithFormat:_(@"%ld deleted photos"),(long)all.count]; weakSelf.browseButton.hidden=all.count==0; if(firstError)[weakSelf showError:firstError]; });
 }];
}
- (void)browse { if(self.assets.count) [self.navigationController pushViewController:[AssetGridViewController gridWithTitle:_(@"Trash") assets:self.assets] animated:YES]; }
- (void)actions {
 UIAlertController *a=[UIAlertController alertControllerWithTitle:_(@"Trash") message:nil preferredStyle:UIAlertControllerStyleActionSheet]; __weak typeof(self) w=self;
 [a addAction:[UIAlertAction actionWithTitle:_(@"Restore All") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [IMAssetManagementApi restoreAllTrashWithCompletion:^(BOOL ok,NSError *e){ dispatch_async(dispatch_get_main_queue(), ^{ if(!ok)[w showError:e]; [w reload]; }); }]; }]];
 [a addAction:[UIAlertAction actionWithTitle:_(@"Empty Trash") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){ [IMAssetManagementApi emptyTrashWithCompletion:^(BOOL ok,NSError *e){ dispatch_async(dispatch_get_main_queue(), ^{ if(!ok)[w showError:e]; [w reload]; }); }]; }]];
 [a addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]]; if(a.popoverPresentationController){a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMaxY(self.view.bounds),1,1);} [self presentViewController:a animated:YES completion:nil];
}
- (void)showError:(NSError *)error { UIAlertController *a=[UIAlertController alertControllerWithTitle:_(@"Trash") message:error.localizedDescription ?: _(@"Request failed") preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end
