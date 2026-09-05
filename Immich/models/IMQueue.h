#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMQueue : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) BOOL paused;
@property (nonatomic, readonly) NSInteger active;
@property (nonatomic, readonly) NSInteger completed;
@property (nonatomic, readonly) NSInteger delayed;
@property (nonatomic, readonly) NSInteger failed;
@property (nonatomic, readonly) NSInteger waiting;
@property (nonatomic, readonly) NSInteger pausedCount;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMQueue *> *)queuesWithArray:(NSArray *)array;
@end

NS_ASSUME_NONNULL_END
