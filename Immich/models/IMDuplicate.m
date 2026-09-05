#import "IMDuplicate.h"

static id IMDuplicateValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMDuplicate ()
@property (nonatomic, copy) NSString *duplicateId;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@property (nonatomic, copy) NSArray<NSString *> *suggestedKeepAssetIds;
@end

@implementation IMDuplicate

+ (nullable instancetype)duplicateWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}

	id rawID = IMDuplicateValueOrNil(dictionary[@"duplicateId"]);
	if (![rawID isKindOfClass:[NSString class]] || [rawID length] == 0) {
		return nil;
	}

	id rawAssets = IMDuplicateValueOrNil(dictionary[@"assets"]);
	NSArray<IMAsset *> *assets = [rawAssets isKindOfClass:[NSArray class]]
	    ? [IMAsset assetsWithResponseArray:(NSArray *)rawAssets]
	    : @[];
	NSMutableArray<NSString *> *suggested = [NSMutableArray array];
	id rawSuggested = IMDuplicateValueOrNil(dictionary[@"suggestedKeepAssetIds"]);
	if ([rawSuggested isKindOfClass:[NSArray class]]) {
		for (id value in (NSArray *)rawSuggested) {
			if ([value isKindOfClass:[NSString class]] && [value length] > 0 && ![suggested containsObject:value]) {
				[suggested addObject:value];
			}
		}
	}

	IMDuplicate *duplicate = [[self alloc] init];
	duplicate.duplicateId = rawID;
	duplicate.assets = assets;
	duplicate.suggestedKeepAssetIds = suggested;
	return duplicate;
}

+ (NSArray<IMDuplicate *> *)duplicatesWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMDuplicate *> *duplicates = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMDuplicate *duplicate = [self duplicateWithResponseDictionary:value];
		if (duplicate) {
			[duplicates addObject:duplicate];
		}
	}
	return duplicates;
}

- (NSArray<NSString *> *)assetIdsToKeep {
	NSMutableSet<NSString *> *assetIDs = [NSMutableSet set];
	for (IMAsset *asset in self.assets) {
		if (asset.assetId.length > 0) {
			[assetIDs addObject:asset.assetId];
		}
	}

	NSMutableArray<NSString *> *keep = [NSMutableArray array];
	for (NSString *assetID in self.suggestedKeepAssetIds) {
		if ([assetIDs containsObject:assetID] && ![keep containsObject:assetID]) {
			[keep addObject:assetID];
		}
	}
	if (keep.count == 0) {
		for (IMAsset *asset in self.assets) {
			if (asset.assetId.length > 0) {
				[keep addObject:asset.assetId];
				break;
			}
		}
	}
	return keep.copy;
}

- (NSArray<NSString *> *)assetIdsToTrash {
	NSSet<NSString *> *keep = [NSSet setWithArray:[self assetIdsToKeep]];
	NSMutableArray<NSString *> *trash = [NSMutableArray array];
	for (IMAsset *asset in self.assets) {
		if (asset.assetId.length > 0 && ![keep containsObject:asset.assetId]) {
			[trash addObject:asset.assetId];
		}
	}
	return trash.copy;
}

@end
