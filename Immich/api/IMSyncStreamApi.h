#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSyncStreamApi : NSObject

+ (instancetype)shared;

- (void)pollAssetChangesWithCompletion:(void (^)(NSSet<NSString *> *_Nullable changedBuckets,
                                                  BOOL sawDeletes,
                                                  NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
