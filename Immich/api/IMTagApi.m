#import "IMTagApi.h"
#import "IMApiClient.h"
#import "common.h"
#include <math.h>

static NSError *IMTagMutationError(id json, NSError *error) {
	if (error) return error;
	if ([json isKindOfClass:NSArray.class]) {
		for (id entry in json) {
			if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"success"] isEqual:@YES]) {
				return [NSError errorWithDomain:@"IMTagApi" code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"The server could not update this photo's tags.")}];
			}
		}
		if ([json count] > 0) return nil;
	}
	return [NSError errorWithDomain:@"IMTagApi" code:2 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid tag response.")}];
}

static NSError *IMTagMalformedResponse(void) {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:2
	                        userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid tag response.")}];
}

static BOOL IMTagResponseIsValid(id value) {
	if (![value isKindOfClass:[NSDictionary class]]) {
		return NO;
	}
	NSDictionary *tag = (NSDictionary *)value;
	for (NSString *key in @[ @"id", @"name", @"value", @"createdAt", @"updatedAt" ]) {
		if (![tag[key] isKindOfClass:[NSString class]] || [tag[key] length] == 0) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMTagIdentifierArrayIsValid(NSArray<NSString *> *values) {
	if (![values isKindOfClass:[NSArray class]] || values.count == 0) return NO;
	for (id value in values) {
		if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) return NO;
	}
	return YES;
}

@implementation IMTagApi
+ (void)allTagsWithCompletion:(void (^)(NSArray<IMTag *> *, NSError *))completion {
	[[IMApiClient shared] GET:@"/tags" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:[NSArray class]]) { completion(nil, error ?: IMTagMalformedResponse()); return; }
		for (id value in (NSArray *)json) {
			if (!IMTagResponseIsValid(value)) { completion(nil, IMTagMalformedResponse()); return; }
		}
		completion([IMTag tagsWithArray:json], nil);
	}];
}
+ (void)createTagNamed:(NSString *)name color:(NSString *)color completion:(void (^)(IMTag *, NSError *))completion {
	NSMutableDictionary *body = [@{ @"name": name ?: @"" } mutableCopy];
	if (color.length) body[@"color"] = color;
	[[IMApiClient shared] POST:@"/tags" body:body completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSDictionary class]]) { completion(nil, IMTagMalformedResponse()); return; }
		if (!IMTagResponseIsValid(json)) { completion(nil, IMTagMalformedResponse()); return; }
		IMTag *tag = [[IMTag alloc] initWithDictionary:json];
		completion(tag, tag ? nil : IMTagMalformedResponse());
	}];
}
+ (void)upsertTagsNamed:(NSArray<NSString *> *)names completion:(void (^)(NSArray<IMTag *> *, NSError *))completion {
	[[IMApiClient shared] PUT:@"/tags" body:@{ @"tags": names ?: @[] } completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSArray class]]) { completion(nil, IMTagMalformedResponse()); return; }
		for (id value in (NSArray *)json) {
			if (!IMTagResponseIsValid(value)) { completion(nil, IMTagMalformedResponse()); return; }
		}
		completion([IMTag tagsWithArray:json], nil);
	}];
}
+ (void)updateTagId:(NSString *)tagId color:(NSString *)color completion:(void (^)(IMTag *, NSError *))completion {
	NSString *path = [NSString stringWithFormat:@"/tags/%@", tagId ?: @""];
	NSDictionary *body = color.length ? @{ @"color": color } : @{ @"color": [NSNull null] };
	[[IMApiClient shared] PUT:path body:body completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (!IMTagResponseIsValid(json)) { completion(nil, IMTagMalformedResponse()); return; }
		IMTag *tag = [[IMTag alloc] initWithDictionary:json];
		completion(tag, tag ? nil : IMTagMalformedResponse());
	}];
}
+ (void)deleteTagId:(NSString *)tagId completion:(void (^)(BOOL, NSError *))completion {
	NSString *path = [NSString stringWithFormat:@"/tags/%@", tagId ?: @""];
	[[IMApiClient shared] DELETE:path body:nil completion:^(id json, NSError *error) { completion(error == nil, error); }];
}
+ (void)tagId:(NSString *)tagId assetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(NSError *))completion {
	NSString *path = [NSString stringWithFormat:@"/tags/%@/assets", tagId ?: @""];
	[[IMApiClient shared] PUT:path body:@{ @"ids": assetIds ?: @[] } completion:^(id json, NSError *error) { completion(IMTagMutationError(json, error)); }];
}
+ (void)untagId:(NSString *)tagId assetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(NSError *))completion {
	NSString *path = [NSString stringWithFormat:@"/tags/%@/assets", tagId ?: @""];
	[[IMApiClient shared] DELETE:path body:@{ @"ids": assetIds ?: @[] } completion:^(id json, NSError *error) { completion(IMTagMutationError(json, error)); }];
}

+ (void)bulkTagIds:(NSArray<NSString *> *)tagIds
          assetIds:(NSArray<NSString *> *)assetIds
        completion:(void (^)(NSInteger count, NSError *_Nullable error))completion {
	if (!IMTagIdentifierArrayIsValid(tagIds) || !IMTagIdentifierArrayIsValid(assetIds)) {
		completion(0, [NSError errorWithDomain:IMApiErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"Choose at least one tag and photo.")}]);
		return;
	}
	[[IMApiClient shared] PUT:@"/tags/assets"
	                      body:@{ @"tagIds": tagIds, @"assetIds": assetIds }
	                completion:^(id json, NSError *error) {
		if (error) {
			completion(0, error);
			return;
		}
		if (![json isKindOfClass:[NSDictionary class]] || ![json[@"count"] isKindOfClass:[NSNumber class]]) {
			completion(0, IMTagMalformedResponse());
			return;
		}
		NSNumber *number = json[@"count"];
		double count = number.doubleValue;
		if (!isfinite(count) || floor(count) != count || count < 0.0 || count > 9007199254740991.0) {
			completion(0, IMTagMalformedResponse());
			return;
		}
		completion(number.integerValue, nil);
	}];
}
@end
