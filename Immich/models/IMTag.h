#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMTag : NSObject
@property (nonatomic, copy, readonly) NSString *tagId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *value;
@property (nonatomic, copy, readonly, nullable) NSString *color;
@property (nonatomic, copy, readonly, nullable) NSString *parentId;
@property (nonatomic, copy, readonly) NSString *createdAt;
@property (nonatomic, copy, readonly) NSString *updatedAt;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMTag *> *)tagsWithArray:(NSArray *)array;
@end

NS_ASSUME_NONNULL_END
