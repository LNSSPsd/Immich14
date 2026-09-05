#import "IMAlbum.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMAlbum ()
@property (nonatomic, copy) NSString *albumId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger assetCount;
@property (nonatomic, copy, nullable) NSString *thumbnailAssetId;
@property (nonatomic, copy, nullable) NSString *order;
@property (nonatomic, copy) NSString *albumDescription;
@property (nonatomic) BOOL activityEnabled;
@property (nonatomic) BOOL shared;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *rolesByUserId;
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
	NSString *order = IMValueOrNil(dict[@"order"]);
	if ([order isKindOfClass:[NSString class]] && ([order isEqualToString:@"asc"] || [order isEqualToString:@"desc"])) {
		album.order = order;
	}
	id description = IMValueOrNil(dict[@"description"]);
	album.albumDescription = [description isKindOfClass:[NSString class]] ? description : @"";
	id activity = IMValueOrNil(dict[@"isActivityEnabled"]);
	album.activityEnabled = [activity isKindOfClass:[NSNumber class]] ? [activity boolValue] : YES;
	id shared = IMValueOrNil(dict[@"shared"]);
	album.shared = [shared isKindOfClass:[NSNumber class]] ? [shared boolValue] : NO;
	NSMutableDictionary *roles = [NSMutableDictionary dictionary];
	NSArray *members = [dict[@"albumUsers"] isKindOfClass:NSArray.class] ? dict[@"albumUsers"] : @[];
	for (id member in members) {
		if (![member isKindOfClass:NSDictionary.class] || ![member[@"user"] isKindOfClass:NSDictionary.class]) continue;
		id userId = member[@"user"][@"id"], role = member[@"role"];
		if ([userId isKindOfClass:NSString.class] && [role isKindOfClass:NSString.class]) roles[userId] = role;
	}
	album.rolesByUserId = roles;
	return album;
}

- (NSString *)roleForUserId:(NSString *)userId {
	return userId.length ? self.rolesByUserId[userId] : nil;
}

- (instancetype)albumByAdjustingAssetCount:(NSInteger)delta {
	IMAlbum *album = [[IMAlbum alloc] init];
	album.albumId = self.albumId;
	album.name = self.name;
	album.assetCount = MAX((NSInteger)0, self.assetCount + delta);
	album.thumbnailAssetId = self.thumbnailAssetId;
	album.order = self.order;
	album.albumDescription = self.albumDescription;
	album.activityEnabled = self.activityEnabled;
	album.shared = self.shared;
	album.rolesByUserId = self.rolesByUserId;
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
