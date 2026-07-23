#import "IMAlbum.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMAlbum ()
@property (nonatomic, copy) NSString *albumId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger assetCount;
@property (nonatomic, copy, nullable) NSString *thumbnailAssetId;
@end

@implementation IMAlbum

+ (nullable instancetype)albumWithDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSString *albumId = IMValueOrNil(dict[@"id"]);
	if (![albumId isKindOfClass:[NSString class]] || albumId.length == 0) {
		return nil;
	}
	IMAlbum *album = [[IMAlbum alloc] init];
	album.albumId = albumId;
	NSString *name = IMValueOrNil(dict[@"albumName"]);
	album.name = [name isKindOfClass:[NSString class]] ? name : @"";
	id count = IMValueOrNil(dict[@"assetCount"]);
	album.assetCount = [count isKindOfClass:[NSNumber class]] ? [count integerValue] : 0;
	NSString *thumbnailAssetId = IMValueOrNil(dict[@"albumThumbnailAssetId"]);
	album.thumbnailAssetId = [thumbnailAssetId isKindOfClass:[NSString class]] ? thumbnailAssetId : nil;
	return album;
}

+ (NSArray<IMAlbum *> *)albumsWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMAlbum *> *albums = [NSMutableArray arrayWithCapacity:array.count];
	for (NSDictionary *dict in array) {
		IMAlbum *album = [IMAlbum albumWithDictionary:dict];
		if (album) {
			[albums addObject:album];
		}
	}
	return albums;
}

@end
