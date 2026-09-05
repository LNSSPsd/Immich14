#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTestEmailResponse : NSObject

@property (nonatomic, copy, readonly) NSString *messageId;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
