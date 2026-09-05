#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMPersonProfile : NSObject

@property (nonatomic, copy, readonly) NSString *personId;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly, nullable) NSString *birthDate;
@property (nonatomic, copy, readonly) NSString *thumbnailPath;
@property (nonatomic, readonly, getter=isHidden) BOOL hidden;
@property (nonatomic, readonly, getter=isFavorite) BOOL favorite;
@property (nonatomic, copy, readonly, nullable) NSString *color;
@property (nonatomic, copy, readonly, nullable) NSString *updatedAt;

+ (nullable instancetype)personWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMPersonProfile *> *)peopleWithResponseArray:(NSArray *)array;

@end

NS_ASSUME_NONNULL_END
