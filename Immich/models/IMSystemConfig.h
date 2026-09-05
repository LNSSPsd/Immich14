#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSystemConfig : NSObject

@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *rawDictionary;

@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSDictionary *> *sections;

@property (nonatomic, readonly) BOOL mapEnabled;
@property (nonatomic, readonly) BOOL reverseGeocodingEnabled;
@property (nonatomic, readonly) BOOL machineLearningEnabled;
@property (nonatomic, readonly) BOOL libraryWatchEnabled;
@property (nonatomic, readonly) BOOL newVersionCheckEnabled;
@property (nonatomic, readonly) BOOL passwordLoginEnabled;
@property (nonatomic, readonly) BOOL serverPublicUsers;
@property (nonatomic, readonly) BOOL trashEnabled;
@property (nonatomic, readonly) NSInteger trashDays;
@property (nonatomic, readonly) BOOL storageTemplateEnabled;
@property (nonatomic, readonly) BOOL storageHashVerificationEnabled;
@property (nonatomic, copy, readonly) NSString *externalDomain;
@property (nonatomic, copy, readonly) NSString *loginPageMessage;
@property (nonatomic, copy, readonly) NSString *storageTemplate;

+ (nullable instancetype)configWithDictionary:(NSDictionary *)dictionary;

- (nullable instancetype)initWithDictionary:(NSDictionary *)dictionary NS_DESIGNATED_INITIALIZER;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

+ (NSArray<NSString *> *)requiredSectionNames;

@end

NS_ASSUME_NONNULL_END
