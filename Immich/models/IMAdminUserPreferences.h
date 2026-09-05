#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAdminUserPreferences : NSObject

@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *rawDictionary;

@property (nonatomic, copy, readonly) NSString *defaultAlbumAssetOrder;
@property (nonatomic, readonly) BOOL gCastEnabled;
@property (nonatomic, readonly) NSInteger archiveSize;
@property (nonatomic, readonly) BOOL includeEmbeddedVideos;

@property (nonatomic, readonly) BOOL emailAlbumInvite;
@property (nonatomic, readonly) BOOL emailAlbumUpdate;
@property (nonatomic, readonly) BOOL emailEnabled;
@property (nonatomic, readonly) BOOL foldersEnabled;
@property (nonatomic, readonly) BOOL foldersSidebarWeb;
@property (nonatomic, readonly) NSInteger memoriesDuration;
@property (nonatomic, readonly) BOOL memoriesEnabled;
@property (nonatomic, readonly) BOOL peopleEnabled;
@property (nonatomic, readonly) NSInteger peopleMinimumFaces;
@property (nonatomic, readonly) BOOL peopleSidebarWeb;
@property (nonatomic, copy, readonly) NSString *hideBuyButtonUntil;
@property (nonatomic, readonly) BOOL showSupportBadge;
@property (nonatomic, readonly) BOOL ratingsEnabled;
@property (nonatomic, readonly) BOOL recentlyAddedSidebarWeb;
@property (nonatomic, readonly) BOOL sharedLinksEnabled;
@property (nonatomic, readonly) BOOL sharedLinksSidebarWeb;
@property (nonatomic, readonly) BOOL tagsEnabled;
@property (nonatomic, readonly) BOOL tagsSidebarWeb;

+ (nullable instancetype)preferencesWithDictionary:(NSDictionary *)dictionary;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

+ (BOOL)validateUpdateDictionary:(NSDictionary *)dictionary error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
