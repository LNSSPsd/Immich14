#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAssetDetail : NSObject

@property (nonatomic, copy, readonly) NSString *assetId;
@property (nonatomic, readonly, getter=isVideo) BOOL video; 
@property (nonatomic, copy, readonly) NSString *originalFileName;
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;
@property (nonatomic, copy, readonly, nullable) NSString *fileCreatedAt; 

@property (nonatomic, copy, readonly, nullable) NSString *cameraMake;
@property (nonatomic, copy, readonly, nullable) NSString *cameraModel;
@property (nonatomic, copy, readonly, nullable) NSString *lensModel;
@property (nonatomic, copy, readonly, nullable) NSNumber *fNumber;
@property (nonatomic, copy, readonly, nullable) NSString *exposureTime;
@property (nonatomic, copy, readonly, nullable) NSNumber *iso;
@property (nonatomic, copy, readonly, nullable) NSNumber *focalLength;
@property (nonatomic, copy, readonly, nullable) NSString *city;
@property (nonatomic, copy, readonly, nullable) NSString *state;
@property (nonatomic, copy, readonly, nullable) NSString *country;
@property (nonatomic, copy, readonly, nullable) NSString *exifDescription;

@property (nonatomic, copy, readonly) NSArray<NSString *> *peopleNames;
@property (nonatomic, copy, readonly) NSArray<NSString *> *tagNames;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
