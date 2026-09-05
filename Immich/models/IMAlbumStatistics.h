#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMAlbumStatistics : NSObject

@property (nonatomic, readonly) NSInteger notShared;
@property (nonatomic, readonly) NSInteger owned;
@property (nonatomic, readonly) NSInteger shared;

+ (nullable instancetype)statisticsWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
