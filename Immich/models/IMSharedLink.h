#import <Foundation/Foundation.h>
#import "IMAsset.h"
#import "IMAlbum.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMSharedLink : NSObject

@property (nonatomic, copy, readonly) NSString *linkId;
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, readonly, nullable) NSString *slug;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *linkDescription;
@property (nonatomic, copy, readonly, nullable) NSString *expiresAt;
@property (nonatomic, copy, readonly, nullable) NSString *password;
@property (nonatomic, copy, readonly) NSString *type; 
@property (nonatomic, copy, readonly, nullable) NSString *createdAt;
@property (nonatomic, copy, readonly, nullable) NSString *userId;
@property (nonatomic, readonly) BOOL allowDownload;
@property (nonatomic, readonly) BOOL allowUpload;
@property (nonatomic, readonly) BOOL showMetadata;
@property (nonatomic, copy, readonly) NSArray<IMAsset *> *assets;
@property (nonatomic, strong, readonly, nullable) IMAlbum *album;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMSharedLink *> *)linksFromArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
