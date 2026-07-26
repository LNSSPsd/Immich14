#import "IMSearchApi.h"
#import "IMApiClient.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@implementation IMSearchApi

static NSArray<IMPerson *> *sCachedPeople;
static NSArray<IMAsset *> *sCachedPlaceAssets;
static NSArray<NSString *> *sCachedPlaceCityNames;

static const NSInteger kIMSearchPageSize = 100;
static const NSInteger kIMPeoplePageSize = 1000;

#pragma mark - Asset search

+ (nullable NSURLSessionTask *)postSearch:(NSString *)path
                                      body:(NSDictionary *)body
                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [[IMApiClient shared] POST:path
	                              body:body
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    id assetsValue = IMValueOrNil(((NSDictionary *)json)[@"assets"]);
		    NSDictionary *assetsDict = [assetsValue isKindOfClass:[NSDictionary class]] ? assetsValue : nil;
		    id items = IMValueOrNil(assetsDict[@"items"]);
		    completion([IMAsset assetsWithResponseArray:[items isKindOfClass:[NSArray class]] ? items : @[]], nil);
	    }];
}

+ (nullable NSURLSessionTask *)postSearch:(NSString *)path
                                      body:(NSDictionary *)body
                                      page:(NSInteger)page
                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                                     NSString *_Nullable nextPage,
                                                     NSError *_Nullable error))completion {
	NSMutableDictionary *pagedBody = [body mutableCopy];
	pagedBody[@"page"] = @(page < 1 ? 1 : page);
	pagedBody[@"size"] = @(kIMSearchPageSize);
	return [[IMApiClient shared] POST:path
	                              body:pagedBody
	                        completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, nil, error);
			    return;
		    }
		    id assetsValue = IMValueOrNil(((NSDictionary *)json)[@"assets"]);
		    NSDictionary *assetsDict = [assetsValue isKindOfClass:[NSDictionary class]] ? assetsValue : nil;
		    id items = IMValueOrNil(assetsDict[@"items"]);
		    id nextPage = IMValueOrNil(assetsDict[@"nextPage"]);
		    completion([IMAsset assetsWithResponseArray:[items isKindOfClass:[NSArray class]] ? items : @[]],
		               [nextPage isKindOfClass:[NSString class]] ? nextPage : nil,
		               nil);
	    }];
}

+ (nullable NSURLSessionTask *)smartSearchWithQuery:(NSString *)query
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/smart" body:@{ @"query": query } completion:completion];
}

+ (nullable NSURLSessionTask *)smartSearchWithQuery:(NSString *)query
                                                page:(NSInteger)page
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/smart" body:@{ @"query": query } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithOcr:(NSString *)ocrText
                                           completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"ocr": ocrText } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithOcr:(NSString *)ocrText
                                                 page:(NSInteger)page
                                           completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"ocr": ocrText } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithFilename:(NSString *)filename
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"originalFileName": filename } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithFilename:(NSString *)filename
                                                      page:(NSInteger)page
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"originalFileName": filename } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithDescription:(NSString *)description
                                                   completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"description": description } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithDescription:(NSString *)description
                                                         page:(NSInteger)page
                                                   completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"description": description } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithPersonId:(NSString *)personId
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"personIds": @[ personId ] } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithPersonId:(NSString *)personId
                                                      page:(NSInteger)page
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"personIds": @[ personId ] } page:page completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithCity:(NSString *)city
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"city": city } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithCity:(NSString *)city
                                                  page:(NSInteger)page
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSString *_Nullable nextPage, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"city": city } page:page completion:completion];
}

#pragma mark - People

+ (void)peopleAtPage:(NSInteger)page
          completion:(void (^)(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error))completion {
	NSInteger requestPage = page < 1 ? 1 : page;
	[[IMApiClient shared] GET:@"/people"
	                     query:@{
		                     @"size": [NSString stringWithFormat:@"%ld", (long)kIMPeoplePageSize],
		                     @"page": [NSString stringWithFormat:@"%ld", (long)requestPage],
	                     }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, NO, error);
			    return;
		    }
		    NSDictionary *dict = (NSDictionary *)json;
		    id peopleValue = IMValueOrNil(dict[@"people"]);
		    NSArray<IMPerson *> *people = [IMPerson peopleWithArray:[peopleValue isKindOfClass:[NSArray class]] ? peopleValue : @[]];
		    id hasNextValue = IMValueOrNil(dict[@"hasNextPage"]);
		    BOOL hasNext;
		    if ([hasNextValue isKindOfClass:[NSNumber class]]) {
			    hasNext = [hasNextValue boolValue];
		    } else {
			    id totalValue = IMValueOrNil(dict[@"total"]);
			    NSInteger total = [totalValue isKindOfClass:[NSNumber class]] ? [totalValue integerValue] : 0;
			    hasNext = requestPage * kIMPeoplePageSize < total;
		    }
		    if (requestPage == 1) {
			    sCachedPeople = people;
		    }
		    completion(people, hasNext, nil);
	    }];
}

+ (void)allPeopleWithCompletion:(void (^)(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error))completion {
	[self peopleAtPage:1 completion:^(NSArray<IMPerson *> *_Nullable people, BOOL hasNextPage, NSError *_Nullable error) {
		completion(people, error);
	}];
}

+ (NSArray<IMPerson *> *)cachedPeople {
	return sCachedPeople ?: @[];
}

+ (nullable NSURLSessionTask *)thumbnailDataForPersonId:(NSString *)personId
                                              completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion {
	NSString *path = [NSString stringWithFormat:@"/people/%@/thumbnail", personId];
	return [[IMApiClient shared] getData:path query:nil completion:completion];
}

#pragma mark - Places

+ (void)assetsByCityWithCompletion:(void (^)(NSArray<IMAsset *> *_Nullable assets,
                                             NSArray<NSString *> *_Nullable cityNames,
                                             NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/search/cities"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSArray class]]) {
			    completion(nil, nil, error);
			    return;
		    }
		    NSMutableArray<IMAsset *> *assets = [NSMutableArray array];
		    NSMutableArray<NSString *> *cities = [NSMutableArray array];
		    for (NSDictionary *dict in (NSArray *)json) {
			    if (![dict isKindOfClass:[NSDictionary class]]) {
				    continue;
			    }
			    id exifValue = IMValueOrNil(dict[@"exifInfo"]);
			    NSDictionary *exif = [exifValue isKindOfClass:[NSDictionary class]] ? exifValue : nil;
			    NSString *city = IMValueOrNil(exif[@"city"]);
			    if (city.length == 0) {
				    continue;
			    }
			    IMAsset *asset = [IMAsset assetWithResponseDictionary:dict];
			    if (!asset) {
				    continue;
			    }
			    [assets addObject:asset];
			    [cities addObject:city];
		    }
		    sCachedPlaceAssets = assets;
		    sCachedPlaceCityNames = cities;
		    completion(assets, cities, nil);
	    }];
}

+ (NSArray<IMAsset *> *)cachedPlaceAssets {
	return sCachedPlaceAssets ?: @[];
}

+ (NSArray<NSString *> *)cachedPlaceCityNames {
	return sCachedPlaceCityNames ?: @[];
}

@end
