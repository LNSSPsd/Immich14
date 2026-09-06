#import <Foundation/Foundation.h>
#import "IMTag.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMTagApi : NSObject
+ (void)allTagsWithCompletion:(void (^)(NSArray<IMTag *> *_Nullable tags, NSError *_Nullable error))completion;
+ (void)createTagNamed:(NSString *)name color:(nullable NSString *)color completion:(void (^)(IMTag *_Nullable tag, NSError *_Nullable error))completion;
+ (void)createTagNamed:(NSString *)name color:(nullable NSString *)color parentId:(nullable NSString *)parentId completion:(void (^)(IMTag *_Nullable tag, NSError *_Nullable error))completion;
+ (void)upsertTagsNamed:(NSArray<NSString *> *)names completion:(void (^)(NSArray<IMTag *> *_Nullable tags, NSError *_Nullable error))completion;
+ (void)updateTagId:(NSString *)tagId color:(nullable NSString *)color completion:(void (^)(IMTag *_Nullable tag, NSError *_Nullable error))completion;
+ (void)deleteTagId:(NSString *)tagId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)tagId:(NSString *)tagId assetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(NSError *_Nullable error))completion;
+ (void)untagId:(NSString *)tagId assetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(NSError *_Nullable error))completion;

+ (void)bulkTagIds:(NSArray<NSString *> *)tagIds
          assetIds:(NSArray<NSString *> *)assetIds
        completion:(void (^)(NSInteger count, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
