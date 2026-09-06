#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMUserPreferences : NSObject

@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *rawDictionary;

@property (nonatomic, readonly) BOOL emailEnabled;
@property (nonatomic, readonly) BOOL emailAlbumInvite;
@property (nonatomic, readonly) BOOL emailAlbumUpdate;
@property (nonatomic, readonly) BOOL gCastEnabled;
@property (nonatomic, readonly) NSInteger archiveSize;
@property (nonatomic, readonly) BOOL includeEmbeddedVideos;
@property (nonatomic, readonly) BOOL memoriesEnabled;
@property (nonatomic, readonly) NSInteger memoriesDuration;
@property (nonatomic, readonly) BOOL peopleEnabled;
@property (nonatomic, readonly) NSInteger peopleMinimumFaces;
@property (nonatomic, readonly) BOOL peopleSidebarWeb;
@property (nonatomic, readonly) BOOL sharedLinksEnabled;
@property (nonatomic, readonly) BOOL sharedLinksSidebarWeb;
@property (nonatomic, readonly) BOOL tagsEnabled;
@property (nonatomic, readonly) BOOL tagsSidebarWeb;
@property (nonatomic, readonly) BOOL foldersEnabled;
@property (nonatomic, readonly) BOOL foldersSidebarWeb;
@property (nonatomic, readonly) BOOL ratingsEnabled;
@property (nonatomic, readonly) BOOL recentlyAddedSidebarWeb;
@property (nonatomic, copy, readonly) NSString *defaultAlbumAssetOrder;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
