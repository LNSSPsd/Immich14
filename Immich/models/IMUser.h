#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMUser : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *email;
@property (nonatomic, readonly) long long quotaUsageInBytes;
@property (nonatomic, readonly) long long quotaSizeInBytes; 

- (instancetype)initWithDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
