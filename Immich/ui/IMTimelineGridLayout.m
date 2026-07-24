#import "IMTimelineGridLayout.h"

typedef struct {
	NSInteger columns;
	CGFloat itemWidth;
	CGFloat itemHeight;
	CGFloat xStep; 
	CGFloat yStep; 
} IMGridGeometry;

@implementation IMTimelineGridLayout {
	NSInteger _sectionCount;
	CGFloat _width;
	NSInteger *_counts;      
	CGFloat *_originsFrom;   
	CGFloat *_originsTo;
	IMGridGeometry _geometryFrom;
	IMGridGeometry _geometryTo;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_fromColumns = 1;
		_toColumns = 1;
		_progress = 0;
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
	free(_originsFrom);
	free(_originsTo);
	_counts = NULL;
	_originsFrom = NULL;
	_originsTo = NULL;
	_sectionCount = 0;
}

- (void)setFromColumns:(NSInteger)fromColumns toColumns:(NSInteger)toColumns progress:(CGFloat)progress {
	NSInteger from = MAX(1, fromColumns);
	NSInteger to = MAX(1, toColumns);
	CGFloat clamped = MAX(0, MIN(1, progress));
	if (from == _fromColumns && to == _toColumns && clamped == _progress) {
		return;
	}
	_fromColumns = from;
	_toColumns = to;
	_progress = clamped;
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

#pragma mark - Geometry

- (IMGridGeometry)geometryForColumns:(NSInteger)columns {
	IMGridGeometry geometry;
	if (self.rowMode) {
		geometry.columns = 1;
		geometry.itemWidth = _width;
		geometry.itemHeight = self.rowHeight;
	} else {
		geometry.columns = MAX(1, columns);
		geometry.itemWidth = (_width - (geometry.columns - 1) * self.spacing) / geometry.columns;
		geometry.itemHeight = geometry.itemWidth;
	}
	geometry.xStep = geometry.itemWidth + self.spacing;
	geometry.yStep = geometry.itemHeight + self.spacing;
	return geometry;
}

static inline CGFloat IMGridSectionHeight(IMGridGeometry geometry, NSInteger count) {
	if (count <= 0) {
		return 0;
	}
	NSInteger rows = (count + geometry.columns - 1) / geometry.columns;
	return rows * geometry.yStep; 
}

static inline CGRect IMGridItemFrame(IMGridGeometry geometry, CGFloat sectionOrigin, NSInteger item) {
	NSInteger row = item / geometry.columns;
	NSInteger column = item % geometry.columns;
	return CGRectMake(column * geometry.xStep,
	                  sectionOrigin + row * geometry.yStep,
	                  geometry.itemWidth,
	                  geometry.itemHeight);
}

- (CGFloat)lerp:(CGFloat)from to:(CGFloat)to {
	return from + (to - from) * self.progress;
}

- (CGRect)interpolatedFrameForSection:(NSInteger)section item:(NSInteger)item {
	CGRect a = IMGridItemFrame(_geometryFrom, _originsFrom[section], item);
	CGRect b = IMGridItemFrame(_geometryTo, _originsTo[section], item);
	return CGRectMake([self lerp:CGRectGetMinX(a) to:CGRectGetMinX(b)],
	                  [self lerp:CGRectGetMinY(a) to:CGRectGetMinY(b)],
	                  [self lerp:a.size.width to:b.size.width],
	                  [self lerp:a.size.height to:b.size.height]);
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
	if (sections <= 0 || _width <= 0) {
		return;
	}
	_sectionCount = sections;
	_counts = malloc(sizeof(NSInteger) * (size_t)sections);
	_originsFrom = malloc(sizeof(CGFloat) * (size_t)(sections + 1));
	_originsTo = malloc(sizeof(CGFloat) * (size_t)(sections + 1));
	_geometryFrom = [self geometryForColumns:self.fromColumns];
	_geometryTo = [self geometryForColumns:self.toColumns];

	CGFloat yFrom = 0;
	CGFloat yTo = 0;
	for (NSInteger section = 0; section < sections; section++) {
		NSInteger count = [collectionView numberOfItemsInSection:section];
		_counts[section] = count;
		_originsFrom[section] = yFrom;
		_originsTo[section] = yTo;
		yFrom += IMGridSectionHeight(_geometryFrom, count);
		yTo += IMGridSectionHeight(_geometryTo, count);
	}
	_originsFrom[sections] = yFrom;
	_originsTo[sections] = yTo;
}

- (CGSize)collectionViewContentSize {
	if (_sectionCount <= 0) {
		return CGSizeMake(_width, 0);
	}
	CGFloat height = [self lerp:_originsFrom[_sectionCount] to:_originsTo[_sectionCount]];
	return CGSizeMake(_width, MAX(0, height - self.spacing) + self.footerHeight);
}

- (nullable UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section < 0 || indexPath.section >= _sectionCount) {
		return nil;
	}
	if (indexPath.item < 0 || indexPath.item >= _counts[indexPath.section]) {
		return nil;
	}
	UICollectionViewLayoutAttributes *attributes =
	    [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
	attributes.frame = [self interpolatedFrameForSection:indexPath.section item:indexPath.item];
	return attributes;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
	NSMutableArray<UICollectionViewLayoutAttributes *> *result = [NSMutableArray array];
	if (_sectionCount <= 0) {
		return result;
	}
	CGFloat minY = CGRectGetMinY(rect);
	CGFloat maxY = CGRectGetMaxY(rect);

	for (NSInteger section = 0; section < _sectionCount; section++) {
		CGFloat top = [self lerp:_originsFrom[section] to:_originsTo[section]];
		CGFloat bottom = [self lerp:_originsFrom[section + 1] to:_originsTo[section + 1]];
		if (bottom < minY) {
			continue;
		}
		if (top > maxY) {
			break;
		}
		NSInteger count = _counts[section];
		if (count <= 0) {
			continue;
		}

		NSInteger lo = 0;
		NSInteger hi = count - 1;
		NSInteger first = count;
		while (lo <= hi) {
			NSInteger mid = (lo + hi) / 2;
			CGRect frame = [self interpolatedFrameForSection:section item:mid];
			if (CGRectGetMaxY(frame) >= minY) {
				first = mid;
				hi = mid - 1;
			} else {
				lo = mid + 1;
			}
		}
		if (first >= count) {
			continue;
		}

		lo = first;
		hi = count - 1;
		NSInteger last = first;
		while (lo <= hi) {
			NSInteger mid = (lo + hi) / 2;
			CGRect frame = [self interpolatedFrameForSection:section item:mid];
			if (CGRectGetMinY(frame) <= maxY) {
				last = mid;
				lo = mid + 1;
			} else {
				hi = mid - 1;
			}
		}

		for (NSInteger item = first; item <= last; item++) {
			UICollectionViewLayoutAttributes *attributes =
			    [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:[NSIndexPath indexPathForItem:item inSection:section]];
			attributes.frame = [self interpolatedFrameForSection:section item:item];
			[result addObject:attributes];
		}
	}
	return result;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
	return newBounds.size.width != _width;
}

@end
