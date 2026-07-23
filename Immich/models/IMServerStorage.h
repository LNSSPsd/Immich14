#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMServerStorage : NSObject

@property (nonatomic, copy, readonly) NSString *diskUse;  
@property (nonatomic, copy, readonly) NSString *diskSize; 
@property (nonatomic, readonly) double diskUsagePercentage;

+ (nullable instancetype)storageWithDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
