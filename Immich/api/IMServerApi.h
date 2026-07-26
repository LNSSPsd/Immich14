#import <Foundation/Foundation.h>
#import "IMServerStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMServerApi : NSObject

+ (void)serverVersionWithCompletion:(void (^)(NSString *_Nullable versionString, NSError *_Nullable error))completion;
+ (nullable NSString *)cachedServerVersion;

+ (void)serverStorageWithCompletion:(void (^)(IMServerStorage *_Nullable storage, NSError *_Nullable error))completion;
+ (nullable IMServerStorage *)cachedServerStorage;

+ (void)clearCached;

@end

NS_ASSUME_NONNULL_END
