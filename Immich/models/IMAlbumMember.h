#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface IMAlbumMember : NSObject
@property (nonatomic, copy, readonly) NSString *userId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *email;
@property (nonatomic, copy, readonly) NSString *role;
+ (nullable instancetype)memberWithUser:(NSDictionary *)user role:(nullable NSString *)role;
@end
NS_ASSUME_NONNULL_END
