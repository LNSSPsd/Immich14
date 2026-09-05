#import <Foundation/Foundation.h>
#import "IMUser.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, IMActivityType) {
	IMActivityTypeComment = 0,
	IMActivityTypeLike = 1,
};

@interface IMActivity : NSObject

@property (nonatomic, copy, readonly) NSString *activityId;
@property (nonatomic, copy, readonly, nullable) NSString *assetId;
@property (nonatomic, copy, readonly) NSString *type;
@property (nonatomic, copy, readonly, nullable) NSString *comment;
@property (nonatomic, strong, readonly) IMUser *user;
@property (nonatomic, strong, readonly) NSDate *createdAt;

+ (nullable instancetype)activityWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMActivity *> *)activitiesWithArray:(NSArray *)array;

- (BOOL)isLike;
- (BOOL)isComment;

@end

NS_ASSUME_NONNULL_END
