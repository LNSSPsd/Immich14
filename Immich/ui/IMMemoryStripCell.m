#import "IMMemoryStripCell.h"
#import "IMMemoryCell.h"

NSString *const IMMemoryStripCellReuseIdentifier = @"IMMemoryStripCell";

@interface IMMemoryStripCell () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView *strip;
@end

@implementation IMMemoryStripCell

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		_memories = @[];
		UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
		layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
		layout.minimumLineSpacing = 12;
		layout.sectionInset = UIEdgeInsetsMake(6, 16, 14, 16); 
		self.strip = [[UICollectionView alloc] initWithFrame:self.contentView.bounds collectionViewLayout:layout];
		self.strip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		self.strip.backgroundColor = UIColor.clearColor;
		self.strip.showsHorizontalScrollIndicator = NO;
		self.strip.clipsToBounds = NO;
		self.strip.decelerationRate = UIScrollViewDecelerationRateFast;
		self.strip.dataSource = self;
		self.strip.delegate = self;
		[self.strip registerClass:[IMMemoryCell class] forCellWithReuseIdentifier:IMMemoryCellReuseIdentifier];
		[self.contentView addSubview:self.strip];
	}
	return self;
}

- (void)setMemories:(NSArray<IMMemory *> *)memories {
	BOOL same = [[_memories valueForKey:@"memoryId"] isEqualToArray:[memories valueForKey:@"memoryId"]];
	_memories = [memories copy];
	[self.strip reloadData];
	if (!same) {
		[self.strip setContentOffset:CGPointMake(-self.strip.contentInset.left, 0) animated:NO];
	}
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
	return (NSInteger)self.memories.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
	IMMemoryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:IMMemoryCellReuseIdentifier forIndexPath:indexPath];
	cell.compact = YES;
	[cell configureWithMemory:self.memories[indexPath.item]];
	return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
	CGFloat height = collectionView.bounds.size.height - 20;
	return CGSizeMake(round(height * 0.72), height);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
	IMMemoryCell *cell = (IMMemoryCell *)[collectionView cellForItemAtIndexPath:indexPath];
	if (self.onSelect) {
		self.onSelect(indexPath.item, cell.imageView);
	}
}

@end
