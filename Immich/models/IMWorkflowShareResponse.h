#import <Foundation/Foundation.h>
#import "IMWorkflowStep.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMWorkflowShareResponse : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSString *workflowDescription;
@property (nonatomic, copy, readonly) NSString *trigger;
@property (nonatomic, copy, readonly) NSArray<IMWorkflowStep *> *steps;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
