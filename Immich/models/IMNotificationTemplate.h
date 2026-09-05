#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMNotificationTemplateRequest : NSObject

@property (nonatomic, copy, readonly) NSString *template;

+ (nullable instancetype)requestWithTemplate:(NSString *)template;
+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary<NSString *, id> *)requestDictionary;

@end

@interface IMNotificationTemplateResponse : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *html;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
