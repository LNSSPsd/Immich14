#import <Foundation/Foundation.h>
#import "IMAsset.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMFolderApi : NSObject
+ (nullable NSURLSessionTask *)uniquePathsWithCompletion:(void (^)(NSArray<NSString *> *_Nullable paths, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)assetsForOriginalPath:(NSString *)path
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
