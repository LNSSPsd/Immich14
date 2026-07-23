#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMOcrLine : NSObject

@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, readonly) CGRect normalizedRect;

+ (nullable instancetype)lineWithDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
