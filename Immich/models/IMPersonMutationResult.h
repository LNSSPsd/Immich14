#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPersonMutationResult : NSObject
@property (nonatomic, copy, readonly) NSString *resultId;
@property (nonatomic, readonly) BOOL success;
@property (nonatomic, copy, readonly, nullable) NSString *error;
@property (nonatomic, copy, readonly, nullable) NSString *errorMessage;
+ (nullable instancetype)resultWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMPersonMutationResult *> *)resultsWithResponseArray:(NSArray *)array;
+ (nullable NSArray<IMPersonMutationResult *> *)strictResultsWithResponseArray:(NSArray *)array;
@end

NS_ASSUME_NONNULL_END
