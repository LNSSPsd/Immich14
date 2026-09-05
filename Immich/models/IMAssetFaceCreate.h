#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAssetFaceCreate : NSObject

@property (nonatomic, copy, readonly) NSString *assetId;
@property (nonatomic, copy, readonly) NSString *personId;
@property (nonatomic, readonly) NSInteger imageWidth;
@property (nonatomic, readonly) NSInteger imageHeight;
@property (nonatomic, readonly) NSInteger x;
@property (nonatomic, readonly) NSInteger y;
@property (nonatomic, readonly) NSInteger width;
@property (nonatomic, readonly) NSInteger height;

+ (nullable instancetype)requestWithAssetId:(NSString *)assetId
                                    personId:(NSString *)personId
                                 imageWidth:(NSInteger)imageWidth
                                imageHeight:(NSInteger)imageHeight
                                          x:(NSInteger)x
                                          y:(NSInteger)y
                                       width:(NSInteger)width
                                      height:(NSInteger)height;
+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary<NSString *, id> *)requestDictionary;

@end

NS_ASSUME_NONNULL_END
