#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPerson : NSObject

@property (nonatomic, copy, readonly) NSString *personId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) BOOL isHidden;

+ (nullable instancetype)personWithDictionary:(NSDictionary *)dict;
+ (NSArray<IMPerson *> *)peopleWithArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
