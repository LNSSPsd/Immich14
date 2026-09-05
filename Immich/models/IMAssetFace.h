#import <Foundation/Foundation.h>
#import "IMPerson.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMAssetFace : NSObject

@property (nonatomic, copy, readonly) NSString *faceId;
@property (nonatomic, readonly) NSInteger imageWidth;
@property (nonatomic, readonly) NSInteger imageHeight;
@property (nonatomic, readonly) NSInteger boundingBoxX1;
@property (nonatomic, readonly) NSInteger boundingBoxX2;
@property (nonatomic, readonly) NSInteger boundingBoxY1;
@property (nonatomic, readonly) NSInteger boundingBoxY2;
@property (nonatomic, copy, readonly, nullable) NSString *sourceType;
@property (nonatomic, strong, readonly, nullable) IMPerson *person;

+ (nullable instancetype)faceWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMAssetFace *> *)facesWithResponseArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
