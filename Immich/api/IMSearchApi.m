#import "IMSearchApi.h"
#import "IMApiClient.h"

static id IMValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@implementation IMSearchApi

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

+ (nullable NSURLSessionTask *)smartSearchWithQuery:(NSString *)query
                                          completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/smart" body:@{ @"query": query } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithOcr:(NSString *)ocrText
                                           completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"ocr": ocrText } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithFilename:(NSString *)filename
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"originalFileName": filename } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithDescription:(NSString *)description
                                                   completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"description": description } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithPersonId:(NSString *)personId
                                                completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"personIds": @[ personId ] } completion:completion];
}

+ (nullable NSURLSessionTask *)metadataSearchWithCity:(NSString *)city
                                            completion:(void (^)(NSArray<IMAsset *> *_Nullable assets, NSError *_Nullable error))completion {
	return [self postSearch:@"/search/metadata" body:@{ @"city": city } completion:completion];
}

#pragma mark - People

+ (void)allPeopleWithCompletion:(void (^)(NSArray<IMPerson *> *_Nullable people, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/people"
	                     query:@{ @"size": @"1000" }
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    id peopleValue = IMValueOrNil(((NSDictionary *)json)[@"people"]);
		    completion([IMPerson peopleWithArray:[peopleValue isKindOfClass:[NSArray class]] ? peopleValue : @[]], nil);
	    }];
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
		    completion(assets, cities, nil);
	    }];
}

@end
