#import "AssetFacesViewController.h"
#import "IMFaceApi.h"
#import "IMSearchApi.h"
#import "common.h"

@interface AssetFacesViewController ()
@property (nonatomic, copy) NSString *assetId;
@property (nonatomic, copy) NSArray<IMAssetFace *> *faces;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong, nullable) NSURLSessionTask *task;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL mutating;
@end

@implementation AssetFacesViewController

- (instancetype)initWithAssetId:(NSString *)assetId {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_assetId = [assetId copy];
		_faces = @[];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = _(@"Faces");
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 58;
	self.refresh = [[UIRefreshControl alloc] init];
	[self.refresh addTarget:self action:@selector(loadFaces) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = self.refresh;
	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.numberOfLines = 0;
	self.statusLabel.textAlignment = NSTextAlignmentCenter;
	self.statusLabel.textColor = UIColor.secondaryLabelColor;
	self.statusLabel.userInteractionEnabled = YES;
	[self.statusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(loadFaces)]];
	self.tableView.backgroundView = self.statusLabel;
	[self loadFaces];
}

- (void)dealloc {
	[self.task cancel];
	self.generation += 1;
}

- (void)loadFaces {
	[self.task cancel];
	self.task = nil;
	NSUInteger generation = ++self.generation;
	self.statusLabel.text = _(@"Loading faces…");
	self.faces = @[];
	[self.tableView reloadData];
	__weak typeof(self) weakSelf = self;
	self.task = [IMFaceApi facesForAssetId:self.assetId completion:^(NSArray<IMAssetFace *> *faces, NSError *error) {
		AssetFacesViewController *strongSelf = weakSelf;
		if (!strongSelf || generation != strongSelf.generation) return;
		strongSelf.task = nil;
		[strongSelf.refresh endRefreshing];
		if (error || !faces) {
			strongSelf.statusLabel.text = _(@"Couldn't load faces. Tap to retry.");
			return;
		}
		strongSelf.faces = faces;
		strongSelf.statusLabel.text = faces.count ? nil : _(@"No detected faces in this photo.");
		[strongSelf.tableView reloadData];
	}];
}

- (void)showError:(NSError *)error title:(NSString *)title {
	NSString *message = error.localizedDescription.length ? error.localizedDescription : _(@"The server could not complete this request.");
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: _(@"Faces") message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)personNameForFace:(IMAssetFace *)face {
	return face.person.name.length ? face.person.name : _(@"Unassigned person");
}

- (void)presentPersonPickerForFace:(IMAssetFace *)face {
	self.mutating = YES;
	__weak typeof(self) weakSelf = self;
	[IMSearchApi peopleAtPage:1 includeHidden:YES completion:^(NSArray<IMPerson *> *people, BOOL hasNextPage, NSError *error) {
		AssetFacesViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		if (error || !people) {
			strongSelf.mutating = NO;
			[strongSelf showError:error title:_(@"Assign Face")];
			return;
		}
		UIAlertController *picker = [UIAlertController alertControllerWithTitle:_(@"Assign Face") message:face.person.name.length ? [NSString stringWithFormat:_(@"Current: %@"), face.person.name] : nil preferredStyle:UIAlertControllerStyleActionSheet];
		for (IMPerson *person in people) {
			if (!person.personId.length) continue;
			NSString *name = person.name.length ? person.name : _(@"Unnamed person");
			[picker addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				[strongSelf assignFace:face toPersonId:person.personId];
			}]];
		}
		[picker addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { strongSelf.mutating = NO; }]];
		picker.popoverPresentationController.sourceView = self.view;
		picker.popoverPresentationController.sourceRect = self.view.bounds;
		[strongSelf presentViewController:picker animated:YES completion:nil];
	}];
}

- (void)assignFace:(IMAssetFace *)face toPersonId:(NSString *)personId {
	__weak typeof(self) weakSelf = self;
	[IMFaceApi reassignFaceId:face.faceId toPersonId:personId completion:^(IMPerson *person, NSError *error) {
		AssetFacesViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = NO;
		if (error || !person) {
			[strongSelf showError:error title:_(@"Assign Face")];
			return;
		}
		[strongSelf loadFaces];
	}];
}

- (void)deleteFace:(IMAssetFace *)face force:(BOOL)force {
	self.mutating = YES;
	__weak typeof(self) weakSelf = self;
	[IMFaceApi deleteFaceId:face.faceId force:force completion:^(BOOL success, NSError *error) {
		AssetFacesViewController *strongSelf = weakSelf;
		if (!strongSelf) return;
		strongSelf.mutating = NO;
		if (success) { [strongSelf loadFaces]; return; }
		if (!force) {
			UIAlertController *retry = [UIAlertController alertControllerWithTitle:_(@"Face is assigned") message:_(@"Deleting this face may remove its person assignment. Force delete it?") preferredStyle:UIAlertControllerStyleAlert];
			[retry addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
			[retry addAction:[UIAlertAction actionWithTitle:_(@"Force Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [strongSelf deleteFace:face force:YES]; }]];
			[strongSelf presentViewController:retry animated:YES completion:nil];
			return;
		}
		[strongSelf showError:error title:_(@"Delete Face")];
	}];
}

- (void)showActionsForFace:(IMAssetFace *)face indexPath:(NSIndexPath *)indexPath {
	NSString *person = [self personNameForFace:face];
	NSString *message = [NSString stringWithFormat:_(@"%@\nBox: %ld, %ld – %ld, %ld"), person,
	                     (long)face.boundingBoxX1, (long)face.boundingBoxY1,
	                     (long)face.boundingBoxX2, (long)face.boundingBoxY2];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:_(@"Face") message:message preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Assign to Person") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[weakSelf presentPersonPickerForFace:face];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Delete Face") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		UIAlertController *confirm = [UIAlertController alertControllerWithTitle:_(@"Delete this face?") message:_(@"The photo will stay in your library.") preferredStyle:UIAlertControllerStyleAlert];
		[confirm addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
		[confirm addAction:[UIAlertAction actionWithTitle:_(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [weakSelf deleteFace:face force:NO]; }]];
		[weakSelf presentViewController:confirm animated:YES completion:nil];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:_(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
	sheet.popoverPresentationController.sourceView = cell ?: self.view;
	sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.faces.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.faces.count ? _(@"Detected faces") : nil; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"face-cell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
	IMAssetFace *face = self.faces[indexPath.row];
	cell.textLabel.text = [self personNameForFace:face];
	cell.detailTextLabel.text = [NSString stringWithFormat:_(@"Box %ld, %ld – %ld, %ld"), (long)face.boundingBoxX1, (long)face.boundingBoxY1, (long)face.boundingBoxX2, (long)face.boundingBoxY2];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.accessibilityLabel = cell.textLabel.text;
	cell.accessibilityValue = cell.detailTextLabel.text;
	return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (self.mutating || indexPath.row >= (NSInteger)self.faces.count) return;
	[self showActionsForFace:self.faces[indexPath.row] indexPath:indexPath];
}

@end
