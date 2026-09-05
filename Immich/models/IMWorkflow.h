#import <Foundation/Foundation.h>
#import "IMWorkflowStep.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMWorkflow : NSObject

@property (nonatomic, copy, readonly) NSString *workflowId;
@property (nonatomic, copy, readonly, nullable) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSString *workflowDescription;
@property (nonatomic, copy, readonly) NSString *trigger;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, copy, readonly, nullable) NSString *createdAt;
@property (nonatomic, copy, readonly, nullable) NSString *updatedAt;
@property (nonatomic, copy, readonly) NSArray<IMWorkflowStep *> *steps;

+ (nullable instancetype)workflowWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMWorkflow *> *)workflowsWithResponseArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
