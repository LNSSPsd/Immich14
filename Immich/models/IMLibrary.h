#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMLibrary : NSObject
@property (nonatomic, copy, readonly) NSString *libraryId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *ownerId;
@property (nonatomic, copy, readonly) NSArray<NSString *> *importPaths;
@property (nonatomic, copy, readonly) NSArray<NSString *> *exclusionPatterns;
@property (nonatomic, copy, readonly, nullable) NSString *createdAt;
@property (nonatomic, copy, readonly, nullable) NSString *updatedAt;
@property (nonatomic, copy, readonly, nullable) NSString *refreshedAt;
@property (nonatomic, readonly) NSInteger assetCount;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMLibraryStats : NSObject
@property (nonatomic, readonly) NSInteger photos;
@property (nonatomic, readonly) NSInteger videos;
@property (nonatomic, readonly) NSInteger total;
@property (nonatomic, readonly) unsigned long long usage;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

@interface IMLibraryValidation : NSObject
@property (nonatomic, copy, readonly) NSString *importPath;
@property (nonatomic, readonly) BOOL valid;
@property (nonatomic, copy, readonly, nullable) NSString *message;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
