#import "IMSharedLink.h"
#import "common.h"

static id IMSharedLinkValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMSharedLink ()
@property (nonatomic, copy) NSString *linkId;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy, nullable) NSString *slug;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *linkDescription;
@property (nonatomic, copy, nullable) NSString *expiresAt;
@property (nonatomic, copy, nullable) NSString *password;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy, nullable) NSString *createdAt;
@property (nonatomic, copy, nullable) NSString *userId;
@property (nonatomic) BOOL allowDownload;
@property (nonatomic) BOOL allowUpload;
@property (nonatomic) BOOL showMetadata;
@property (nonatomic, copy) NSArray<IMAsset *> *assets;
@property (nonatomic, strong, nullable) IMAlbum *album;
@end

@implementation IMSharedLink
- (instancetype)initWithDictionary:(NSDictionary *)d {
	if ((self = [super init])) {
		id v = IMSharedLinkValueOrNil(d[@"id"]);
		_linkId = [v isKindOfClass:[NSString class]] ? v : @"";
		v = IMSharedLinkValueOrNil(d[@"key"]);
		_key = [v isKindOfClass:[NSString class]] ? v : @"";
		v = IMSharedLinkValueOrNil(d[@"slug"]);
		_slug = [v isKindOfClass:[NSString class]] && [v length] > 0 ? v : nil;
		v = IMSharedLinkValueOrNil(d[@"description"]);
		_linkDescription = [v isKindOfClass:[NSString class]] && [v length] > 0 ? v : nil;
		v = IMSharedLinkValueOrNil(d[@"expiresAt"]);
		_expiresAt = [v isKindOfClass:[NSString class]] && [v length] > 0 ? v : nil;
		v = IMSharedLinkValueOrNil(d[@"password"]);
		_password = [v isKindOfClass:[NSString class]] && [v length] > 0 ? v : nil;
		v = IMSharedLinkValueOrNil(d[@"type"]);
		_type = [v isKindOfClass:[NSString class]] ? v : @"INDIVIDUAL";
		v = IMSharedLinkValueOrNil(d[@"createdAt"]);
		_createdAt = [v isKindOfClass:[NSString class]] ? v : nil;
		v = IMSharedLinkValueOrNil(d[@"userId"]);
		_userId = [v isKindOfClass:[NSString class]] ? v : nil;
		_allowDownload = [d[@"allowDownload"] respondsToSelector:@selector(boolValue)] ? [d[@"allowDownload"] boolValue] : YES;
		_allowUpload = [d[@"allowUpload"] respondsToSelector:@selector(boolValue)] ? [d[@"allowUpload"] boolValue] : NO;
		_showMetadata = [d[@"showMetadata"] respondsToSelector:@selector(boolValue)] ? [d[@"showMetadata"] boolValue] : YES;
		id assetsValue = IMSharedLinkValueOrNil(d[@"assets"]);
		_assets = [IMAsset assetsWithResponseArray:[assetsValue isKindOfClass:[NSArray class]] ? assetsValue : @[]];
		id albumValue = IMSharedLinkValueOrNil(d[@"album"]);
		_album = [albumValue isKindOfClass:[NSDictionary class]] ? [IMAlbum albumWithDictionary:albumValue] : nil;
		_title = _album.name.length ? _album.name : (_linkDescription.length ? _linkDescription : _(@"Shared link"));
	}
	return self;
}
+ (NSArray<IMSharedLink *> *)linksFromArray:(NSArray *)array { NSMutableArray *r=[NSMutableArray array]; for(id d in array) if([d isKindOfClass:[NSDictionary class]]) [r addObject:[[self alloc] initWithDictionary:d]]; return r; }
@end
