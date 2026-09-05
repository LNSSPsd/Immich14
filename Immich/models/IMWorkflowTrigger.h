#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMWorkflowTrigger : NSObject

@property (nonatomic, copy, readonly) NSString *trigger;
@property (nonatomic, copy, readonly) NSArray<NSString *> *types;

+ (nullable instancetype)triggerWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMWorkflowTrigger *> *)triggersWithResponseArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
