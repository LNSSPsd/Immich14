#import <Foundation/Foundation.h>
#import "IMWorkflow.h"
#import "IMWorkflowTrigger.h"
#import "IMWorkflowShareResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMWorkflowApi : NSObject

+ (void)workflowsWithEnabled:(nullable NSNumber *)enabled
                   completion:(void (^)(NSArray<IMWorkflow *> *_Nullable workflows,
                                        NSError *_Nullable error))completion;
+ (void)workflowsWithCompletion:(void (^)(NSArray<IMWorkflow *> *_Nullable workflows,
                                          NSError *_Nullable error))completion;
+ (void)allWorkflowsWithCompletion:(void (^)(NSArray<IMWorkflow *> *_Nullable workflows,
                                             NSError *_Nullable error))completion;

+ (void)workflowWithId:(NSString *)workflowId
            completion:(void (^)(IMWorkflow *_Nullable workflow,
                                 NSError *_Nullable error))completion;
+ (void)workflowShareWithId:(NSString *)workflowId
                  completion:(void (^)(IMWorkflowShareResponse *_Nullable response,
                                       NSError *_Nullable error))completion;
+ (void)workflowTriggersWithCompletion:(void (^)(NSArray<IMWorkflowTrigger *> *_Nullable triggers,
                                                 NSError *_Nullable error))completion;

+ (void)createWorkflowWithName:(nullable NSString *)name
                    description:(nullable NSString *)description
                        trigger:(NSString *)trigger
                        enabled:(BOOL)enabled
                          steps:(NSArray<IMWorkflowStep *> *)steps
                     completion:(void (^)(IMWorkflow *_Nullable workflow,
                                          NSError *_Nullable error))completion;

+ (void)updateWorkflowId:(NSString *)workflowId
                     name:(nullable NSString *)name
              description:(nullable NSString *)description
                  trigger:(nullable NSString *)trigger
                  enabled:(nullable NSNumber *)enabled
                    steps:(nullable NSArray<IMWorkflowStep *> *)steps
               completion:(void (^)(IMWorkflow *_Nullable workflow,
                                    NSError *_Nullable error))completion;

+ (void)setWorkflowId:(NSString *)workflowId
              enabled:(BOOL)enabled
           completion:(void (^)(IMWorkflow *_Nullable workflow,
                                NSError *_Nullable error))completion;
+ (void)deleteWorkflowId:(NSString *)workflowId
               completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
