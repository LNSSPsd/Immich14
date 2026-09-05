#import <Foundation/Foundation.h>
#import "IMStack.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMStacksCompletion)(NSArray<IMStack *> *_Nullable stacks, NSError *_Nullable error);

@interface IMStackApi : NSObject
+ (nullable NSURLSessionTask *)stacksWithCompletion:(IMStacksCompletion)completion;
+ (nullable NSURLSessionTask *)stackWithId:(NSString *)stackId completion:(void (^)(IMStack *_Nullable stack, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)createStackWithAssetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(IMStack *_Nullable stack, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)updateStack:(NSString *)stackId primaryAssetId:(NSString *)assetId completion:(void (^)(IMStack *_Nullable stack, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)deleteStack:(NSString *)stackId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)removeAssetId:(NSString *)assetId fromStack:(NSString *)stackId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
