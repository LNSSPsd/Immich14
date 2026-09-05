#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMServerApkLinks : NSObject

@property (nonatomic, copy, readonly) NSString *arm64v8a;
@property (nonatomic, copy, readonly) NSString *armeabiv7a;
@property (nonatomic, copy, readonly) NSString *universal;
@property (nonatomic, copy, readonly) NSString *x86_64;

+ (nullable instancetype)linksWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
