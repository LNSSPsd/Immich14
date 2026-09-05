#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMWorkflowStep : NSObject

@property (nonatomic, copy, readonly) NSString *method;
@property (nonatomic, copy, readonly, nullable) NSDictionary *config;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

+ (nullable instancetype)stepWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMWorkflowStep *> *)stepsWithResponseArray:(NSArray *)array;

- (NSDictionary *)requestDictionary;

@end

NS_ASSUME_NONNULL_END
