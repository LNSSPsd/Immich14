#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMServerAbout : NSObject
@property (nonatomic, copy, readonly) NSString *version;
@property (nonatomic, copy, readonly) NSString *versionURL;
@property (nonatomic, readonly) BOOL licensed;
@property (nonatomic, copy, readonly, nullable) NSString *build;
@property (nonatomic, copy, readonly, nullable) NSString *buildImage;
@property (nonatomic, copy, readonly, nullable) NSString *buildImageURL;
@property (nonatomic, copy, readonly, nullable) NSString *buildURL;
@property (nonatomic, copy, readonly, nullable) NSString *repository;
@property (nonatomic, copy, readonly, nullable) NSString *repositoryURL;
@property (nonatomic, copy, readonly, nullable) NSString *sourceCommit;
@property (nonatomic, copy, readonly, nullable) NSString *sourceRef;
@property (nonatomic, copy, readonly, nullable) NSString *sourceURL;
@property (nonatomic, copy, readonly, nullable) NSString *nodeJSVersion;
@property (nonatomic, copy, readonly, nullable) NSString *ffmpegVersion;
@property (nonatomic, copy, readonly, nullable) NSString *exiftoolVersion;
@property (nonatomic, copy, readonly, nullable) NSString *imagemagickVersion;
@property (nonatomic, copy, readonly, nullable) NSString *libvipsVersion;
+ (nullable instancetype)aboutWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMServerFeatures : NSObject
@property (nonatomic, readonly) BOOL configFile;
@property (nonatomic, readonly) BOOL duplicateDetection;
@property (nonatomic, readonly) BOOL email;
@property (nonatomic, readonly) BOOL facialRecognition;
@property (nonatomic, readonly) BOOL importFaces;
@property (nonatomic, readonly) BOOL map;
@property (nonatomic, readonly) BOOL oauth;
@property (nonatomic, readonly) BOOL oauthAutoLaunch;
@property (nonatomic, readonly) BOOL ocr;
@property (nonatomic, readonly) BOOL passwordLogin;
@property (nonatomic, readonly) BOOL realtimeTranscoding;
@property (nonatomic, readonly) BOOL reverseGeocoding;
@property (nonatomic, readonly) BOOL search;
@property (nonatomic, readonly) BOOL sidecar;
@property (nonatomic, readonly) BOOL smartSearch;
@property (nonatomic, readonly) BOOL trash;
+ (nullable instancetype)featuresWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMServerConfig : NSObject
@property (nonatomic, copy, readonly) NSString *externalDomain;
@property (nonatomic, readonly) BOOL initialized;
@property (nonatomic, readonly) BOOL onboarded;
@property (nonatomic, copy, readonly) NSString *loginPageMessage;
@property (nonatomic, readonly) BOOL maintenanceMode;
@property (nonatomic, copy, readonly) NSString *mapDarkStyleURL;
@property (nonatomic, copy, readonly) NSString *mapLightStyleURL;
@property (nonatomic, readonly) NSInteger minFaces;
@property (nonatomic, copy, readonly) NSString *oauthButtonText;
@property (nonatomic, readonly) BOOL publicUsers;
@property (nonatomic, readonly) NSInteger trashDays;
@property (nonatomic, readonly) NSInteger userDeleteDelay;
+ (nullable instancetype)configWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMServerMediaTypes : NSObject
@property (nonatomic, copy, readonly) NSArray<NSString *> *image;
@property (nonatomic, copy, readonly) NSArray<NSString *> *video;
@property (nonatomic, copy, readonly) NSArray<NSString *> *sidecar;
+ (nullable instancetype)mediaTypesWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMServerVersionCheck : NSObject
@property (nonatomic, copy, readonly, nullable) NSString *checkedAt;
@property (nonatomic, copy, readonly, nullable) NSString *releaseVersion;
+ (nullable instancetype)versionCheckWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMServerVersionHistoryEntry : NSObject
@property (nonatomic, copy, readonly) NSString *entryId;
@property (nonatomic, copy, readonly) NSString *version;
@property (nonatomic, copy, readonly) NSString *createdAt;
+ (nullable instancetype)entryWithDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
