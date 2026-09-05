#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAPIKey : NSObject
@property (nonatomic, copy, readonly) NSString *keyId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSArray<NSString *> *permissions;
@property (nonatomic, copy, readonly) NSString *createdAt;
@property (nonatomic, copy, readonly) NSString *updatedAt;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMAPIKey *> *)keysWithArray:(NSArray *)array;
@end

NS_ASSUME_NONNULL_END
