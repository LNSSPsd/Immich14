#import "IMTimelineGridLayout.h"

NSString *const IMTimelineGridLayoutBackLayerKind = @"IMTimelineGridLayoutBackLayer";

typedef struct {
	NSInteger columns;
	CGFloat itemWidth;
	CGFloat itemHeight;
	CGFloat xStep; 
	CGFloat yStep; 
	CGFloat *origins; 
	CGFloat contentHeight;
	CGPoint anchorPoint;
	CGFloat scale;
} IMGridLayer;

@implementation IMTimelineGridLayout {
	NSInteger _sectionCount;
	CGFloat _width;
	NSInteger *_counts;
	IMGridLayer _rest;
	IMGridLayer _front;
	IMGridLayer _back;
	NSIndexPath *_anchor;
	CGPoint _anchorFraction;
	CGPoint _target;
	CGPoint _zoomContentOffset;
	CGFloat _zoomContentHeight; 
	CGFloat _normalizedWidth;
	CGFloat _fade;
	CGPoint _blendedTarget;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_columns = 1;
		_spacing = 2;
		_rowHeight = 84;
	}
	return self;
}

- (void)dealloc {
	[self freeBuffers];
}

- (void)freeBuffers {
	free(_counts);
	free(_rest.origins);
	free(_front.origins);
	free(_back.origins);
	_counts = NULL;
	_rest.origins = NULL;
	_front.origins = NULL;
	_back.origins = NULL;
	_sectionCount = 0;
}

- (void)setColumns:(NSInteger)columns {
	NSInteger clamped = MAX(1, columns);
	if (clamped == _columns && !_zooming) {
		return;
	}
	_columns = clamped;
	_zooming = NO;
	_anchor = nil;
	[self invalidateLayout];
}

- (void)setRowMode:(BOOL)rowMode {
	if (_rowMode == rowMode) {
		return;
	}
	_rowMode = rowMode;
	[self invalidateLayout];
}

- (void)setFooterHeight:(CGFloat)footerHeight {
	if (_footerHeight == footerHeight) {
		return;
	}
	_footerHeight = footerHeight;
	[self invalidateLayout];
}

#pragma mark - Zoom

- (void)beginZoomWithAnchor:(NSIndexPath *)anchor
                   fraction:(CGPoint)fraction
                     target:(CGPoint)target
              contentOffset:(CGPoint)contentOffset {
	_zooming = YES;
	_anchor = anchor;
	_anchorFraction = fraction;
	_target = target;
	_zoomContentOffset = contentOffset;
	_zoomContentHeight = MAX(_rest.contentHeight, contentOffset.y + self.collectionView.bounds.size.height);
	_frontColumns = _columns;
	_backColumns = _columns;
	_normalizedWidth = 1.0 / _columns;
	_fade = 0;
	[self invalidateLayout];
}

- (void)setZoomFrontColumns:(NSInteger)frontColumns
                backColumns:(NSInteger)backColumns
            normalizedWidth:(CGFloat)normalizedWidth
                       fade:(CGFloat)fade {
	if (!_zooming) {
		return;
	}
	_frontColumns = MAX(1, frontColumns);
	_backColumns = MAX(1, backColumns);
	_normalizedWidth = normalizedWidth > 0 ? normalizedWidth : 1.0 / _frontColumns;
	_fade = _frontColumns == _backColumns ? 0 : MAX(0, MIN(1, fade));
	[self invalidateLayout];
}

- (void)endZoomAtColumns:(NSInteger)columns {
	_zooming = NO;
	_anchor = nil;
	_columns = MAX(1, columns);
	[self invalidateLayout];
}

- (CGFloat)restingContentOffsetYForColumns:(NSInteger)columns {
	IMGridLayer layer = {0};
	[self buildLayer:&layer columns:columns];
	CGFloat offset = [self clampedOffsetForLayer:&layer];
	free(layer.origins);
	return offset;
}

#pragma mark - Geometry

- (void)buildLayer:(IMGridLayer *)layer columns:(NSInteger)columns {
	free(layer->origins);
	layer->origins = NULL;
	if (self.rowMode) {
		layer->columns = 1;
		layer->itemWidth = _width;
		layer->itemHeight = self.rowHeight;
	} else {
		layer->columns = MAX(1, columns);
		layer->itemWidth = (_width - (layer->columns - 1) * self.spacing) / layer->columns;
		layer->itemHeight = layer->itemWidth;
	}
	layer->xStep = layer->itemWidth + self.spacing;
	layer->yStep = layer->itemHeight + self.spacing;
	layer->scale = 1;
	layer->anchorPoint = CGPointZero;
	if (_sectionCount <= 0) {
		layer->contentHeight = self.footerHeight;
		return;
	}
	layer->origins = malloc(sizeof(CGFloat) * (size_t)(_sectionCount + 1));
	CGFloat y = 0;
	for (NSInteger section = 0; section < _sectionCount; section++) {
		layer->origins[section] = y;
		NSInteger count = _counts[section];
		if (count > 0) {
			NSInteger rows = (count + layer->columns - 1) / layer->columns;
			y += rows * layer->yStep; 
		}
	}
	layer->origins[_sectionCount] = y;
	layer->contentHeight = MAX(0, y - self.spacing) + self.footerHeight;
}

static inline CGRect IMGridItemFrame(const IMGridLayer *layer, NSInteger section, NSInteger item) {
	NSInteger row = item / layer->columns;
	NSInteger column = item % layer->columns;
	return CGRectMake(column * layer->xStep,
	                  layer->origins[section] + row * layer->yStep,
	                  layer->itemWidth,
	                  layer->itemHeight);
}

- (BOOL)resolvedAnchorSection:(NSInteger *)section item:(NSInteger *)item {
	if (!_anchor || _sectionCount <= 0) {
		return NO;
	}
	NSInteger s = MAX(0, MIN(_anchor.section, _sectionCount - 1));
	while (s > 0 && _counts[s] == 0) {
		s--;
	}
	if (_counts[s] == 0) {
		return NO;
	}
	*section = s;
	*item = MAX(0, MIN(_anchor.item, _counts[s] - 1));
	return YES;
}

- (CGPoint)anchorPointInLayer:(const IMGridLayer *)layer {
	NSInteger section = 0;
	NSInteger item = 0;
	if (!layer->origins || ![self resolvedAnchorSection:&section item:&item]) {
		return CGPointZero;
	}
	CGRect frame = IMGridItemFrame(layer, section, item);
	return CGPointMake(frame.origin.x + _anchorFraction.x * frame.size.width,
	                   frame.origin.y + _anchorFraction.y * frame.size.height);
}

- (UIEdgeInsets)scrollInsets {
	UICollectionView *collectionView = self.collectionView;
	if (@available(iOS 11.0, *)) {
		return collectionView.adjustedContentInset;
	}
	return collectionView.contentInset;
}

- (CGFloat)clampedOffsetForLayer:(const IMGridLayer *)layer {
	UIEdgeInsets insets = [self scrollInsets];
	CGFloat height = self.collectionView.bounds.size.height;
	CGFloat desired = [self anchorPointInLayer:layer].y - _target.y;
	CGFloat minOffset = -insets.top;
	CGFloat maxOffset = MAX(minOffset, layer->contentHeight + insets.bottom - height);
	return MAX(minOffset, MIN(maxOffset, desired));
}

- (CGPoint)restingAnchorPositionForLayer:(const IMGridLayer *)layer {
	CGPoint point = [self anchorPointInLayer:layer];
	return CGPointMake(point.x, point.y - [self clampedOffsetForLayer:layer]);
}

- (void)placeLayersForZoom {
	_front.anchorPoint = [self anchorPointInLayer:&_front];
	_back.anchorPoint = [self anchorPointInLayer:&_back];
	_front.scale = _normalizedWidth * _front.columns;
	_back.scale = _normalizedWidth * _back.columns;
	CGPoint frontTarget = [self restingAnchorPositionForLayer:&_front];
	CGPoint backTarget = [self restingAnchorPositionForLayer:&_back];
	_blendedTarget = CGPointMake(frontTarget.x + (backTarget.x - frontTarget.x) * _fade,
	                             frontTarget.y + (backTarget.y - frontTarget.y) * _fade);
}

- (CGRect)zoomFrameForNativeFrame:(CGRect)frame inLayer:(const IMGridLayer *)layer {
	CGFloat s = layer->scale;
	return CGRectMake(_blendedTarget.x + s * (frame.origin.x - layer->anchorPoint.x) + _zoomContentOffset.x,
	                  _blendedTarget.y + s * (frame.origin.y - layer->anchorPoint.y) + _zoomContentOffset.y,
	                  frame.size.width * s,
	                  frame.size.height * s);
}

#pragma mark - UICollectionViewLayout

- (void)prepareLayout {
	[super prepareLayout];
	UICollectionView *collectionView = self.collectionView;
	[self freeBuffers];
	if (!collectionView) {
		return;
	}
	_width = collectionView.bounds.size.width;
	NSInteger sections = collectionView.numberOfSections;
	if (_width <= 0) {
		return;
	}
	_sectionCount = MAX(0, sections);
	if (_sectionCount > 0) {
		_counts = malloc(sizeof(NSInteger) * (size_t)_sectionCount);
		for (NSInteger section = 0; section < _sectionCount; section++) {
			_counts[section] = [collectionView numberOfItemsInSection:section];
		}
	}
	[self buildLayer:&_rest columns:_columns];
	if (_zooming && !self.rowMode) {
		[self buildLayer:&_front columns:_frontColumns];
		[self buildLayer:&_back columns:_backColumns];
		[self placeLayersForZoom];
	}
}

- (BOOL)zoomActive {
	return _zooming && !self.rowMode && _front.origins && _back.origins;
}

- (CGSize)collectionViewContentSize {
	if ([self zoomActive]) {
		return CGSizeMake(_width, _zoomContentHeight);
	}
	return CGSizeMake(_width, _rest.contentHeight);
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section < 0 || indexPath.section >= _sectionCount ||
	    indexPath.item < 0 || indexPath.item >= _counts[indexPath.section]) {
		return nil;
	}
	UICollectionViewLayoutAttributes *attributes =
	    [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
	if ([self zoomActive]) {
		attributes.frame = [self zoomFrameForNativeFrame:IMGridItemFrame(&_front, indexPath.section, indexPath.item)
		                                         inLayer:&_front];
		attributes.alpha = 1 - _fade;
		attributes.zIndex = 1;
	} else {
		attributes.frame = IMGridItemFrame(&_rest, indexPath.section, indexPath.item);
	}
	return attributes;
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind
                                                                              atIndexPath:(NSIndexPath *)indexPath {
	if (![elementKind isEqualToString:IMTimelineGridLayoutBackLayerKind]) {
		return nil;
	}
	UICollectionViewLayoutAttributes *attributes =
	    [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:elementKind withIndexPath:indexPath];
	BOOL valid = indexPath.section >= 0 && indexPath.section < _sectionCount && indexPath.item >= 0 &&
	             indexPath.item < _counts[indexPath.section];
	if (valid && [self zoomActive] && _frontColumns != _backColumns) {
		attributes.frame = [self zoomFrameForNativeFrame:IMGridItemFrame(&_back, indexPath.section, indexPath.item)
		                                         inLayer:&_back];
		attributes.zIndex = 0;
	} else {
		attributes.hidden = YES;
	}
	return attributes;
}

- (void)appendLayer:(const IMGridLayer *)layer
          nativeMinY:(CGFloat)minY
          nativeMaxY:(CGFloat)maxY
                into:(NSMutableArray<UICollectionViewLayoutAttributes *> *)result
                back:(BOOL)back
                zoom:(BOOL)zoom {
	for (NSInteger section = 0; section < _sectionCount; section++) {
		if (layer->origins[section + 1] < minY) {
			continue;
		}
		if (layer->origins[section] > maxY) {
			break;
		}
		NSInteger count = _counts[section];
		if (count <= 0) {
			continue;
		}
		NSInteger firstRow = (NSInteger)floor((minY - layer->origins[section]) / layer->yStep);
		NSInteger lastRow = (NSInteger)floor((maxY - layer->origins[section]) / layer->yStep);
		NSInteger first = MAX(0, firstRow * layer->columns);
		NSInteger last = MIN(count - 1, (lastRow + 1) * layer->columns - 1);
		for (NSInteger item = first; item <= last; item++) {
			NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
			UICollectionViewLayoutAttributes *attributes;
			CGRect native = IMGridItemFrame(layer, section, item);
			if (back) {
				attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:IMTimelineGridLayoutBackLayerKind
				                                                                            withIndexPath:indexPath];
				attributes.zIndex = 0;
			} else {
				attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
				if (zoom) {
					attributes.alpha = 1 - _fade;
					attributes.zIndex = 1;
				}
			}
			attributes.frame = zoom ? [self zoomFrameForNativeFrame:native inLayer:layer] : native;
			[result addObject:attributes];
		}
	}
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
	NSMutableArray<UICollectionViewLayoutAttributes *> *result = [NSMutableArray array];
	if (_sectionCount <= 0 || !_rest.origins) {
		return result;
	}
	if (![self zoomActive]) {
		[self appendLayer:&_rest nativeMinY:CGRectGetMinY(rect) nativeMaxY:CGRectGetMaxY(rect) into:result back:NO zoom:NO];
		return result;
	}
	CGFloat viewMinY = CGRectGetMinY(rect) - _zoomContentOffset.y;
	CGFloat viewMaxY = CGRectGetMaxY(rect) - _zoomContentOffset.y;
	const IMGridLayer *layers[2] = { &_front, &_back };
	NSInteger layerCount = _frontColumns == _backColumns ? 1 : 2;
	for (NSInteger i = 0; i < layerCount; i++) {
		const IMGridLayer *layer = layers[i];
		if (i == 0 && _fade >= 1) {
			continue; 
		}
		CGFloat s = MAX(0.0001, layer->scale);
		CGFloat minY = layer->anchorPoint.y + (viewMinY - _blendedTarget.y) / s;
		CGFloat maxY = layer->anchorPoint.y + (viewMaxY - _blendedTarget.y) / s;
		[self appendLayer:layer nativeMinY:minY nativeMaxY:maxY into:result back:(i == 1) zoom:YES];
	}
	return result;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
	return newBounds.size.width != _width;
}

@end
