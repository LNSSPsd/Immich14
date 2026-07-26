#import <Foundation/Foundation.h>
#import "IMAsset.h"
#import "IMPerson.h"

NS_ASSUME_NONNULL_BEGIN

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

+ (void)peopleAtPage:(NSInteger)page
          completion:(void (^)(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error))completion;

+ (void)allPeopleWithCompletion:(void (^)(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error))completion;

+ (NSArray<IMPerson *> *)cachedPeople;

+ (nullable NSURLSessionTask *)thumbnailDataForPersonId:(NSString *)personId
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;

+ (void)assetsByCityWithCompletion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                             NSArray<NSString *> *_Nullable cityNames,
                                             NSError *_Nullable error))completion;

+ (NSArray<IMAsset *> *)cachedPlaceAssets;
+ (NSArray<NSString *> *)cachedPlaceCityNames;

@end

NS_ASSUME_NONNULL_END
