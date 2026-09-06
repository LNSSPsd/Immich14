#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPartner : NSObject
@property (nonatomic, copy, readonly) NSString *partnerId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *email;
@property (nonatomic, copy, readonly) NSString *profileImagePath;
@property (nonatomic, copy, readonly) NSString *avatarColor;
@property (nonatomic, copy, readonly) NSString *profileChangedAt;
@property (nonatomic, readonly) BOOL inTimeline;
+ (nullable instancetype)partnerWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMPartner *> *)partnersWithArray:(NSArray *)array;
@end

NS_ASSUME_NONNULL_END
