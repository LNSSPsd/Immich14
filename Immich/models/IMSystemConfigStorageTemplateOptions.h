#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMSystemConfigStorageTemplateOptions : NSObject
@property (nonatomic, copy, readonly) NSArray<NSString *> *dayOptions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *hourOptions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *minuteOptions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *monthOptions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *presetOptions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *secondOptions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *weekOptions;
@property (nonatomic, copy, readonly) NSArray<NSString *> *yearOptions;

+ (nullable instancetype)optionsWithDictionary:(NSDictionary *)dictionary;
@end

NS_ASSUME_NONNULL_END
