#import "MapViewController.h"
#import <MapKit/MapKit.h>
#import "IMMapApi.h"
#import "IMAssetApi.h"
#import "AssetViewController.h"
#import "common.h"

@interface IMMapAnnotation : MKPointAnnotation
@property (nonatomic, copy) NSString *assetId;
@end

@implementation IMMapAnnotation
@end

@interface MapViewController () <MKMapViewDelegate>
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSArray<IMMapMarker *> *markers;
@property (nonatomic) BOOL usesPreloadedMarkers;
@property (nonatomic, strong, nullable) UIAlertController *loadingAlert;
@property (nonatomic, strong) NSMutableSet<NSString *> *openingAssetIds;
@property (nonatomic) BOOL reverseGeocoding;
@end

@implementation MapViewController

- (instancetype)init {
	self = [super init];
	if (self) {
		_markers = @[];
		_openingAssetIds = [NSMutableSet set];
	}
	return self;
}

+ (instancetype)mapViewControllerWithMarkers:(NSArray<IMMapMarker *> *)markers
	                                      title:(nullable NSString *)title {
	MapViewController *controller = [[self alloc] init];
	controller.markers = [markers isKindOfClass:[NSArray class]] ? [markers copy] : @[];
	controller.usesPreloadedMarkers = YES;
	if (title.length > 0) controller.title = title;
	return controller;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	if (self.title.length == 0) self.title = _(@"Map");
	if (@available(iOS 13.0, *)) {
		self.view.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		self.view.backgroundColor = UIColor.whiteColor;
	}

	if (!self.usesPreloadedMarkers) {
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
		                                                                                          target:self
		                                                                                          action:@selector(reloadMarkers)];
	}

	self.mapView = [[MKMapView alloc] initWithFrame:CGRectZero];
	self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
	self.mapView.delegate = self;
	self.mapView.showsCompass = YES;
	self.mapView.showsScale = YES;
	self.mapView.accessibilityHint = _(@"Long press a location to look up its place name.");
	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
	                                                                                           action:@selector(mapLongPressed:)];
	longPress.minimumPressDuration = 0.55;
	[self.mapView addGestureRecognizer:longPress];
	[self.view addSubview:self.mapView];

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.text = _(@"No geotagged photos yet.");
	if (@available(iOS 13.0, *)) {
		self.emptyLabel.textColor = UIColor.secondaryLabelColor;
	} else {
		self.emptyLabel.textColor = UIColor.grayColor;
	}
	self.emptyLabel.hidden = YES;
	[self.view addSubview:self.emptyLabel];

	if (@available(iOS 13.0, *)) {
		self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	} else {
		self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	}
	self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
	self.activityIndicator.hidesWhenStopped = YES;
	[self.view addSubview:self.activityIndicator];

	[NSLayoutConstraint activateConstraints:@[
		[self.mapView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.mapView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
		[self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32],
		[self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32],
		[self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
	]];

	if (self.usesPreloadedMarkers) {
		[self replaceAnnotationsAndFitMap];
	} else {
		[self reloadMarkers];
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!self.usesPreloadedMarkers && self.mapView && self.markers.count > 0) {
		[self reloadMarkers];
	}
}

- (void)reloadMarkers {
	if (!self.mapView) {
		return;
	}
	[self.activityIndicator startAnimating];
	self.navigationItem.rightBarButtonItem.enabled = NO;
	__weak typeof(self) weakSelf = self;
	[IMMapApi markersWithCompletion:^(NSArray<IMMapMarker *> *_Nullable markers, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[strongSelf.activityIndicator stopAnimating];
		strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
		if (error || !markers) {
			if (strongSelf.markers.count == 0) {
				strongSelf.emptyLabel.text = _(@"Couldn't load the map. Tap refresh to retry.");
				strongSelf.emptyLabel.hidden = NO;
			}
			return;
		}
		strongSelf.markers = markers;
		[strongSelf replaceAnnotationsAndFitMap];
	}];
}

- (void)replaceAnnotationsAndFitMap {
	[self.mapView removeAnnotations:self.mapView.annotations];
	NSMutableArray<IMMapAnnotation *> *annotations = [NSMutableArray arrayWithCapacity:self.markers.count];
	for (IMMapMarker *marker in self.markers) {
		CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(marker.latitude, marker.longitude);
		if (!CLLocationCoordinate2DIsValid(coordinate)) {
			continue;
		}
		IMMapAnnotation *annotation = [[IMMapAnnotation alloc] init];
		annotation.coordinate = coordinate;
		annotation.assetId = marker.assetId;
		NSString *place = [self placeNameForMarker:marker];
		annotation.title = place.length > 0 ? place : _(@"Photo");
		annotation.subtitle = _(@"Tap the disclosure button to view");
		[annotations addObject:annotation];
	}
	[self.mapView addAnnotations:annotations];
	self.emptyLabel.hidden = annotations.count > 0;
	if (annotations.count == 0) {
		return;
	}
	if (annotations.count == 1) {
		[self.mapView setRegion:MKCoordinateRegionMake(annotations.firstObject.coordinate,
		                                                MKCoordinateSpanMake(0.12, 0.12))
		                animated:NO];
		return;
	}
	MKMapRect rect = MKMapRectNull;
	for (IMMapAnnotation *annotation in annotations) {
		MKMapPoint point = MKMapPointForCoordinate(annotation.coordinate);
		MKMapRect pointRect = MKMapRectMake(point.x, point.y, 0.0, 0.0);
		rect = MKMapRectIsNull(rect) ? pointRect : MKMapRectUnion(rect, pointRect);
	}
	if (!MKMapRectIsNull(rect)) {
		[self.mapView setVisibleMapRect:rect
		                    edgePadding:UIEdgeInsetsMake(48.0, 24.0, 48.0, 24.0)
		                       animated:NO];
	}
}

- (NSString *)placeNameForMarker:(IMMapMarker *)marker {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	if (marker.city.length > 0) {
		[parts addObject:marker.city];
	}
	if (marker.state.length > 0 && ![marker.state isEqualToString:marker.city]) {
		[parts addObject:marker.state];
	}
	if (marker.country.length > 0 && ![parts containsObject:marker.country]) {
		[parts addObject:marker.country];
	}
	return [parts componentsJoinedByString:@", "];
}

- (void)mapLongPressed:(UILongPressGestureRecognizer *)gesture {
	if (gesture.state != UIGestureRecognizerStateBegan || self.reverseGeocoding) {
		return;
	}
	CGPoint point = [gesture locationInView:self.mapView];
	CLLocationCoordinate2D coordinate = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];
	if (!CLLocationCoordinate2DIsValid(coordinate)) {
		return;
	}
	self.reverseGeocoding = YES;
	[self.activityIndicator startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMMapApi reverseGeocodeLatitude:coordinate.latitude
	                       longitude:coordinate.longitude
	                      completion:^(NSArray<IMMapReverseGeocode *> *_Nullable results, NSError *_Nullable error) {
		 typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) {
			 return;
		 }
		 strongSelf.reverseGeocoding = NO;
		 [strongSelf.activityIndicator stopAnimating];
		 NSString *message = nil;
		if (error) {
			 message = error.localizedDescription ?: _(@"The server could not look up this location.");
		} else {
			 NSMutableArray<NSString *> *names = [NSMutableArray array];
			 for (IMMapReverseGeocode *result in results) {
				 NSString *name = result.displayName;
				 if (name.length > 0 && ![names containsObject:name]) {
					 [names addObject:name];
				 }
			 }
			 NSString *place = names.count > 0 ? [names componentsJoinedByString:@"\n"] : _(@"No named place was found at this location.");
			 message = [NSString stringWithFormat:_(@"%@\n\n%.5f, %.5f"), place, coordinate.latitude, coordinate.longitude];
		}
		 UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Location")
		                                                                  message:message
		                                                           preferredStyle:UIAlertControllerStyleAlert];
		 [alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
		 [strongSelf presentViewController:alert animated:YES completion:nil];
	}];
}

#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
	if ([annotation isKindOfClass:[MKUserLocation class]]) {
		return nil;
	}
	static NSString *const reuseIdentifier = @"IMMapMarker";
	MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:reuseIdentifier];
	if (!view) {
		view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
		view.canShowCallout = YES;
		view.clusteringIdentifier = @"asset";
		if (@available(iOS 13.0, *)) {
			view.glyphImage = [UIImage systemImageNamed:@"photo"];
		}
		view.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
	} else {
		view.annotation = annotation;
	}
	return view;
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForClusterAnnotation:(MKClusterAnnotation *)cluster {
	static NSString *const reuseIdentifier = @"IMMapCluster";
	MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:reuseIdentifier];
	if (!view) {
		view = [[MKMarkerAnnotationView alloc] initWithAnnotation:cluster reuseIdentifier:reuseIdentifier];
		view.canShowCallout = YES;
		if (@available(iOS 13.0, *)) {
			view.glyphImage = [UIImage systemImageNamed:@"square.stack.3d.up"];
		}
	} else {
		view.annotation = cluster;
	}
	view.glyphText = [NSString stringWithFormat:@"%lu", (unsigned long)cluster.memberAnnotations.count];
	return view;
}

- (void)mapView:(MKMapView *)mapView
	 annotationView:(MKAnnotationView *)view
	calloutAccessoryControlTapped:(UIControl *)control {
	if (![view.annotation isKindOfClass:[IMMapAnnotation class]]) {
		return;
	}
	[self openAssetForMapAnnotation:(IMMapAnnotation *)view.annotation];
}

- (void)openAssetForMapAnnotation:(IMMapAnnotation *)annotation {
	if (annotation.assetId.length == 0 || [self.openingAssetIds containsObject:annotation.assetId]) {
		return;
	}
	[self.openingAssetIds addObject:annotation.assetId];
	[self.activityIndicator startAnimating];
	__weak typeof(self) weakSelf = self;
	[IMAssetApi assetForAssetId:annotation.assetId
	                 completion:^(IMAsset *_Nullable asset, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		[strongSelf.openingAssetIds removeObject:annotation.assetId];
		[strongSelf.activityIndicator stopAnimating];
		if (error || !asset) {
			UIAlertController *alert = [UIAlertController alertControllerWithTitle:_(@"Couldn't open photo")
			                                                                 message:error.localizedDescription ?: _(@"The asset is no longer available.")
			                                                          preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:_(@"OK") style:UIAlertActionStyleDefault handler:nil]];
			[strongSelf presentViewController:alert animated:YES completion:nil];
			return;
		}
		AssetViewController *viewer = [AssetViewController viewerWithAssets:@[ asset ] startIndex:0];
		[strongSelf presentViewController:viewer animated:YES completion:nil];
	}];
}

@end
