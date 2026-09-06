#import <Foundation/Foundation.h>
#import "IMAsset.h"
#import "IMPerson.h"
#import "IMSearchStatistics.h"
#import "IMSearchExploreGroup.h"
#import "IMSearchPlace.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const IMPeopleDidChangeNotification;

FOUNDATION_EXPORT NSString *const IMSearchSuggestionTypeCountry;
FOUNDATION_EXPORT NSString *const IMSearchSuggestionTypeState;
FOUNDATION_EXPORT NSString *const IMSearchSuggestionTypeCity;
FOUNDATION_EXPORT NSString *const IMSearchSuggestionTypeCameraMake;
FOUNDATION_EXPORT NSString *const IMSearchSuggestionTypeCameraModel;
FOUNDATION_EXPORT NSString *const IMSearchSuggestionTypeCameraLensModel;

@interface IMSearchApi : NSObject


+ (nullable NSURLSessionTask *)smartSearchWithQuery:(NSString *)query
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)metadataSearchWithOcr:(NSString *)ocrText
                                           completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)metadataSearchWithFilename:(NSString *)filename
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)metadataSearchWithDescription:(NSString *)description
                                                   completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)metadataSearchWithPersonId:(NSString *)personId
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)metadataSearchWithCity:(NSString *)city
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)smartSearchWithQuery:(NSString *)query
                                                page:(NSInteger)page
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)metadataSearchWithOcr:(NSString *)ocrText
                                                 page:(NSInteger)page
                                           completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)metadataSearchWithFilename:(NSString *)filename
                                                      page:(NSInteger)page
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)metadataSearchWithDescription:(NSString *)description
                                                         page:(NSInteger)page
                                                   completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)metadataSearchWithPersonId:(NSString *)personId
                                                      page:(NSInteger)page
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)metadataSearchWithCity:(NSString *)city
                                                  page:(NSInteger)page
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)metadataSearchWithMake:(NSString *)make
                                                  page:(NSInteger)page
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)metadataSearchWithTagId:(NSString *)tagId
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion;
+ (nullable NSURLSessionTask *)metadataSearchWithTagId:(NSString *)tagId
                                                page:(NSInteger)page
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)metadataSearchWithFavorite:(BOOL)favorite
                                                      page:(NSInteger)page
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion;

+ (void)peopleAtPage:(NSInteger)page
          completion:(void (^)(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)peopleAtPage:(NSInteger)page
                              includeHidden:(BOOL)includeHidden
                                 completion:(void (^)(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)searchPeopleNamed:(NSString *)name
                                   includeHidden:(BOOL)includeHidden
                                      completion:(void (^)(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)updatePersonId:(NSString *)personId
                                        name:(nullable NSString *)name
                                      hidden:(nullable NSNumber *)hidden
                                  completion:(void (^)(IMPerson *_Nullable person, NSError *_Nullable error))completion;

+ (void)allPeopleWithCompletion:(void (^)(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error))completion;

+ (NSArray<IMPerson *> *)cachedPeople;

+ (nullable NSURLSessionTask *)thumbnailDataForPersonId:(NSString *)personId
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (void)assetsByCityWithCompletion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                             NSArray<NSString *> *_Nullable cityNames,
                                             NSError *_Nullable error))completion;

+ (NSArray<IMAsset *> *)cachedPlaceAssets;
+ (NSArray<NSString *> *)cachedPlaceCityNames;

+ (nullable NSURLSessionTask *)exploreDataWithCompletion:(void (^)(NSArray<IMSearchExploreGroup *> *_Nullable groups,
                                                                    NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)placesNamed:(NSString *)name
                                completion:(void (^)(NSArray<IMSearchPlace *> *_Nullable places,
                                                      NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)searchSuggestionsForType:(NSString *)type
                                               country:(nullable NSString *)country
                                                  state:(nullable NSString *)state
                                                  make:(nullable NSString *)make
                                                 model:(nullable NSString *)model
                                             lensModel:(nullable NSString *)lensModel
                                           includeNull:(BOOL)includeNull
                                            completion:(void (^)(NSArray<NSString *> *_Nullable suggestions,
                                                                  NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)randomAssetsWithCriteria:(nullable NSDictionary<NSString *, id> *)criteria
                                             completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                                                   NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)largeAssetsWithCriteria:(nullable NSDictionary<NSString *, id> *)criteria
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                                                  NSError *_Nullable error))completion;

+ (nullable NSURLSessionTask *)searchStatisticsWithCriteria:(nullable NSDictionary<NSString *, id> *)criteria
                                                  completion:(void (^)(IMSearchStatistics *_Nullable statistics,
                                                                        NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
