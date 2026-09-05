#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const IMAssetEditActionCrop;
extern NSString *const IMAssetEditActionRotate;
extern NSString *const IMAssetEditActionMirror;
extern NSString *const IMAssetEditMirrorAxisHorizontal;
extern NSString *const IMAssetEditMirrorAxisVertical;

@interface IMAssetEdit : NSObject

@property (nonatomic, copy, readonly) NSString *action;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *parameters;
@property (nonatomic, copy, readonly, nullable) NSString *editId;

+ (nullable instancetype)editWithAction:(NSString *)action
                              parameters:(NSDictionary<NSString *, id> *)parameters;
+ (nullable instancetype)editWithResponseDictionary:(NSDictionary *)dictionary;

- (NSDictionary<NSString *, id> *)requestDictionary;

@end

NS_ASSUME_NONNULL_END
