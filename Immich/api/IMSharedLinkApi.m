#import "IMSharedLinkApi.h"
#import "IMApiClient.h"
#import "IMSession.h"
#import "common.h"

static NSError *IMSharedLinkError(NSString *message) {
	return [NSError errorWithDomain:@"IMSharedLinkError"
	                           code:1
	                       userInfo:@{ NSLocalizedDescriptionKey : message }];
}

static NSError *IMSharedLinkMalformedResponse(NSString *message) {
	return IMSharedLinkError(message ?: _(@"The server returned an invalid shared-link response."));
}

static IMSharedLink *IMSharedLinkFromResponse(id json) {
	if (![json isKindOfClass:NSDictionary.class]) {
		return nil;
	}
	IMSharedLink *link = [[IMSharedLink alloc] initWithDictionary:json];
	return (link.linkId.length > 0 || link.key.length > 0) ? link : nil;
}

static BOOL IMSharedLinkAssetIDsValid(NSArray<NSString *> *assetIds) {
	if (![assetIds isKindOfClass:[NSArray class]] || assetIds.count == 0) {
		return NO;
	}
	for (id value in assetIds) {
		if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
			return NO;
		}
	}
	return YES;
}

static BOOL IMSharedLinkIdentifierValid(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
	return [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

static NSArray<NSURLQueryItem *> *IMSharedLinkIdentifierQuery(NSString *key, NSString *slug, NSError **error) {
	BOOL hasKey = IMSharedLinkIdentifierValid(key);
	BOOL hasSlug = IMSharedLinkIdentifierValid(slug);
	if (!hasKey && !hasSlug) {
		if (error) *error = IMSharedLinkError(_(@"A shared-link key or slug is required."));
		return nil;
	}
	NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithCapacity:2];
	if (hasKey) [items addObject:[NSURLQueryItem queryItemWithName:@"key" value:key]];
	if (hasSlug) [items addObject:[NSURLQueryItem queryItemWithName:@"slug" value:slug]];
	return items;
}

static NSURL *IMSharedLinkAPIBaseURL(NSURL *publicURL, NSError **error) {
	if (![publicURL isKindOfClass:[NSURL class]]) {
		if (error) *error = IMSharedLinkError(_(@"A public-link URL is required."));
		return nil;
	}
	NSURLComponents *components = [NSURLComponents componentsWithURL:publicURL resolvingAgainstBaseURL:NO];
	if (![components.scheme.lowercaseString isEqualToString:@"http"] &&
	    ![components.scheme.lowercaseString isEqualToString:@"https"] ||
	    components.host.length == 0 || components.user.length > 0 || components.password.length > 0) {
		if (error) *error = IMSharedLinkError(_(@"The public-link URL must use http or https."));
		return nil;
	}
	NSArray<NSString *> *rawComponents = components.path.pathComponents;
	NSMutableArray<NSString *> *segments = [NSMutableArray array];
	for (NSString *segment in rawComponents) {
		if (![segment isEqualToString:@"/"] && segment.length > 0) {
			if ([segment rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
				if (error) *error = IMSharedLinkError(_(@"The public-link URL contains invalid characters."));
				return nil;
			}
			[segments addObject:segment];
		}
	}
	NSInteger routeIndex = -1;
	for (NSInteger index = (NSInteger)segments.count - 2; index >= 0; index--) {
		NSString *segment = segments[(NSUInteger)index].lowercaseString;
		if ([segment isEqualToString:@"share"] || [segment isEqualToString:@"s"]) {
			routeIndex = index;
			break;
		}
	}
	if (routeIndex < 0 || routeIndex + 1 >= (NSInteger)segments.count) {
		if (error) *error = IMSharedLinkError(_(@"The URL is not an Immich public link."));
		return nil;
	}
	NSMutableArray<NSString *> *prefix = [segments subarrayWithRange:NSMakeRange(0, (NSUInteger)routeIndex)].mutableCopy;
	if (prefix.lastObject.lowercaseString.length > 0 && [prefix.lastObject.lowercaseString isEqualToString:@"api"]) {
	} else {
		[prefix addObject:@"api"];
	}
	NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
	    @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
	NSMutableArray<NSString *> *encoded = [NSMutableArray arrayWithCapacity:prefix.count];
	for (NSString *segment in prefix) {
		NSString *value = [segment stringByAddingPercentEncodingWithAllowedCharacters:unreserved];
		if (!value) {
			if (error) *error = IMSharedLinkError(_(@"The public-link URL contains an invalid server path."));
			return nil;
		}
		[encoded addObject:value];
	}
	components.percentEncodedPath = encoded.count ? [@"/" stringByAppendingString:[encoded componentsJoinedByString:@"/"]] : @"/api";
	components.query = nil;
	components.fragment = nil;
	return components.URL;
}

static BOOL IMSharedLinkIdentifiersFromPublicURL(NSURL *publicURL, NSString **key, NSString **slug, NSError **error) {
	NSURLComponents *components = [NSURLComponents componentsWithURL:publicURL resolvingAgainstBaseURL:NO];
	NSArray<NSString *> *rawComponents = components.path.pathComponents;
	NSMutableArray<NSString *> *segments = [NSMutableArray array];
	for (NSString *segment in rawComponents) if (![segment isEqualToString:@"/"] && segment.length > 0) [segments addObject:segment];
	for (NSInteger index = (NSInteger)segments.count - 2; index >= 0; index--) {
		NSString *route = segments[(NSUInteger)index].lowercaseString;
		if (![route isEqualToString:@"share"] && ![route isEqualToString:@"s"]) continue;
		NSString *identifier = segments[(NSUInteger)index + 1];
		if (!IMSharedLinkIdentifierValid(identifier)) break;
		if ([route isEqualToString:@"s"]) {
			if (slug) *slug = identifier;
		} else if (key) {
			if (key) *key = identifier;
		}
		return YES;
	}
	if (error) *error = IMSharedLinkError(_(@"The URL is not an Immich public link."));
	return NO;
}

static IMApiClient *IMSharedLinkStoredGuestClient(NSError **error) {
	NSURL *baseURL = IMSession.shared.baseURL;
	if (!baseURL) {
		NSString *raw = [[NSUserDefaults standardUserDefaults] stringForKey:@"IMLastServerURL"];
		NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (trimmed.length > 0 && ![trimmed hasPrefix:@"http://"] && ![trimmed hasPrefix:@"https://"]) {
			trimmed = [@"http://" stringByAppendingString:trimmed];
		}
		if (trimmed.length > 0) {
			NSURL *candidate = [NSURL URLWithString:trimmed];
			NSURLComponents *components = [NSURLComponents componentsWithURL:candidate resolvingAgainstBaseURL:NO];
			NSString *scheme = components.scheme.lowercaseString;
			if (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) &&
			    components.host.length > 0 && components.user.length == 0 && components.password.length == 0) {
				NSString *path = components.path ?: @"";
				while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
				if (![path.lowercaseString hasSuffix:@"/api"]) path = path.length ? [path stringByAppendingString:@"/api"] : @"/api";
				components.path = path;
				components.query = nil;
				components.fragment = nil;
				baseURL = components.URL;
			}
		}
	}
	if (!baseURL) {
		if (error) *error = IMSharedLinkError(_(@"Enter a server URL before opening a public link."));
		return nil;
	}
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	client.anonymous = YES;
	return client;
}

static BOOL IMSharedLinkUUIDv4Valid(id value) {
	if (![value isKindOfClass:[NSString class]] || [value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = [(NSString *)value lowercaseString];
	return [raw isEqualToString:canonical] && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static BOOL IMSharedLinkNullableStringFieldValid(NSDictionary *dictionary, NSString *key) {
	if (!dictionary[key]) return NO; 
	id value = dictionary[key];
	return value == [NSNull null] || [value isKindOfClass:[NSString class]];
}

static BOOL IMSharedLinkGuestResponseValid(id value) {
	if (![value isKindOfClass:[NSDictionary class]]) return NO;
	NSDictionary *dictionary = (NSDictionary *)value;
	if (!IMSharedLinkUUIDv4Valid(dictionary[@"id"]) ||
	    ![dictionary[@"key"] isKindOfClass:[NSString class]] || [dictionary[@"key"] length] == 0 ||
	    ![dictionary[@"type"] isKindOfClass:[NSString class]] ||
	    !([dictionary[@"type"] isEqualToString:@"ALBUM"] || [dictionary[@"type"] isEqualToString:@"INDIVIDUAL"]) ||
	    !IMSharedLinkUUIDv4Valid(dictionary[@"userId"]) ||
	    ![dictionary[@"createdAt"] isKindOfClass:[NSString class]] ||
	    !IMDateFromServerTimestamp(dictionary[@"createdAt"]) ||
	    ![dictionary[@"allowDownload"] isKindOfClass:[NSNumber class]] ||
	    ![dictionary[@"allowUpload"] isKindOfClass:[NSNumber class]] ||
	    ![dictionary[@"showMetadata"] isKindOfClass:[NSNumber class]] ||
	    ![dictionary[@"assets"] isKindOfClass:[NSArray class]] ||
	    !IMSharedLinkNullableStringFieldValid(dictionary, @"description") ||
	    !IMSharedLinkNullableStringFieldValid(dictionary, @"expiresAt") ||
	    !IMSharedLinkNullableStringFieldValid(dictionary, @"password") ||
	    !IMSharedLinkNullableStringFieldValid(dictionary, @"slug")) {
		return NO;
	}
	NSArray *assets = dictionary[@"assets"];
	for (id raw in assets) {
		if (![raw isKindOfClass:[NSDictionary class]] || ![IMAsset assetWithResponseDictionary:raw]) return NO;
	}
	id album = dictionary[@"album"];
	if (album && album != [NSNull null] && (![album isKindOfClass:[NSDictionary class]] || ![IMAlbum albumWithDictionary:album])) return NO;
	return YES;
}

static NSError *IMSharedLinkGuestMalformedError(void) {
	return IMSharedLinkMalformedResponse(_(@"The server returned an invalid public-link response."));
}

static NSError *IMSharedLinkBulkResponseError(id json, NSArray<NSString *> *requestedIds) {
	if (![json isKindOfClass:[NSArray class]] || [(NSArray *)json count] != requestedIds.count) {
		return IMSharedLinkMalformedResponse(_(@"The server returned an invalid shared-link membership response."));
	}
	NSMutableSet<NSString *> *expected = [NSMutableSet setWithArray:requestedIds];
	for (id raw in (NSArray *)json) {
		if (![raw isKindOfClass:[NSDictionary class]]) {
			return IMSharedLinkMalformedResponse(_(@"The server returned an invalid shared-link membership response."));
		}
		NSDictionary *entry = (NSDictionary *)raw;
		id identifier = entry[@"assetId"] ?: entry[@"id"];
		id success = entry[@"success"];
		if (![identifier isKindOfClass:[NSString class]] || [identifier length] == 0 ||
		    ![success isKindOfClass:[NSNumber class]] || ![expected containsObject:identifier]) {
			return IMSharedLinkMalformedResponse(_(@"The server returned an invalid shared-link membership response."));
		}
		[expected removeObject:identifier];
		if (![success boolValue]) {
			NSString *reason = [entry[@"errorMessage"] isKindOfClass:[NSString class]] ? entry[@"errorMessage"] : nil;
			if (reason.length == 0 && [entry[@"error"] isKindOfClass:[NSString class]]) {
				reason = entry[@"error"];
			}
			return IMSharedLinkError(reason.length ? reason : _(@"The server could not update shared-link membership."));
		}
	}
	return expected.count == 0 ? nil : IMSharedLinkMalformedResponse(_(@"The server returned an incomplete shared-link membership response."));
}

static NSURL *IMSharedLinkURL(NSURL *base, NSString *key, NSString *slug) {
	if (!base) return nil;
	BOOL hasSlug = [slug isKindOfClass:NSString.class] && slug.length > 0;
	NSString *identifier = hasSlug ? slug : key;
	if (![identifier isKindOfClass:NSString.class] || !identifier.length) return nil;
	NSURLComponents *components = [NSURLComponents componentsWithURL:base resolvingAgainstBaseURL:NO];
	NSString *path = components.percentEncodedPath ?: @"";
	while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
	if ([path hasSuffix:@"/api"]) path = [path substringToIndex:path.length - 4];
	NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
	    @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
	NSString *segment = [identifier stringByAddingPercentEncodingWithAllowedCharacters:unreserved];
	components.percentEncodedPath = [NSString stringWithFormat:@"%@/%@/%@", path, hasSlug ? @"s" : @"share", segment];
	components.query = nil;
	components.fragment = nil;
	return components.URL;
}

static NSArray<NSString *> *IMSharedLinkOptionKeys(void) {
	return @[ @"description", @"password", @"slug", @"expiresAt", @"allowDownload", @"allowUpload", @"showMetadata" ];
}

@implementation IMSharedLinkApi

+ (NSURL *)publicURLForLink:(IMSharedLink *)link {
	return IMSharedLinkURL(IMSession.shared.baseURL, link.key, link.slug);
}

#pragma mark - Creation

+ (void)createLinkWithBody:(NSDictionary *)body
                completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	[[IMApiClient shared] POST:@"/shared-links" body:body completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMSharedLink *link = IMSharedLinkFromResponse(json);
		if (!link) {
			completion(nil, IMSharedLinkMalformedResponse(_(@"The server returned an invalid shared link.")));
			return;
		}
		completion(link, nil);
	}];
}

+ (NSDictionary *)normalizedOptions:(NSDictionary *)options defaults:(NSDictionary *)defaults {
	NSMutableDictionary *body = [defaults mutableCopy];
	if ([options isKindOfClass:NSDictionary.class]) {
		[options enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
			if (![key isKindOfClass:NSString.class] || !value) return;
			if ([IMSharedLinkOptionKeys() containsObject:key]) body[key] = value;
		}];
	}
	if ([body[@"showMetadata"] respondsToSelector:@selector(boolValue)] && ![body[@"showMetadata"] boolValue]) {
		body[@"allowDownload"] = @NO;
	}
	return body;
}

+ (void)createLinkForAssetIds:(NSArray<NSString *> *)assetIds
                      options:(NSDictionary<NSString *,id> *)options
                   completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	if (!IMSharedLinkAssetIDsValid(assetIds)) {
		completion(nil, IMSharedLinkError(_(@"No assets selected.")));
		return;
	}
	NSDictionary *body = [self normalizedOptions:options
	                                     defaults:@{ @"type" : @"INDIVIDUAL",
	                                                 @"assetIds" : assetIds,
	                                                 @"allowDownload" : @YES,
	                                                 @"allowUpload" : @NO,
	                                                 @"showMetadata" : @YES }];
	[self createLinkWithBody:body completion:completion];
}

+ (void)createAlbumLinkForAlbumId:(NSString *)albumId
                           options:(NSDictionary<NSString *,id> *)options
                        completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	if (!albumId.length) {
		completion(nil, IMSharedLinkError(_(@"No album selected.")));
		return;
	}
	NSDictionary *body = [self normalizedOptions:options
	                                     defaults:@{ @"type" : @"ALBUM",
	                                                 @"albumId" : albumId,
	                                                 @"allowDownload" : @YES,
	                                                 @"allowUpload" : @NO,
	                                                 @"showMetadata" : @YES }];
	[self createLinkWithBody:body completion:completion];
}

+ (void)createAlbumLinkForAlbumId:(NSString *)albumId completion:(void (^)(NSURL *_Nullable url, NSError *_Nullable error))completion {
	[self createAlbumLinkForAlbumId:albumId options:nil completion:^(IMSharedLink *link, NSError *error) {
		completion(link ? [self publicURLForLink:link] : nil, error);
	}];
}

+ (void)createLinkForAssetIds:(NSArray<NSString *> *)assetIds completion:(void (^)(NSURL *_Nullable url, NSError *_Nullable error))completion {
	[self createLinkForAssetIds:assetIds options:nil completion:^(IMSharedLink *link, NSError *error) {
		completion(link ? [self publicURLForLink:link] : nil, error);
	}];
}

#pragma mark - Retrieval and editing

+ (void)allLinksWithCompletion:(void (^)(NSArray<IMSharedLink *> *_Nullable links, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/shared-links" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:NSArray.class]) {
			completion(nil, error ?: IMSharedLinkMalformedResponse(_(@"The server returned an invalid shared-link list.")));
			return;
		}
		NSMutableArray<IMSharedLink *> *links = [NSMutableArray arrayWithCapacity:[(NSArray *)json count]];
		for (id raw in (NSArray *)json) {
			IMSharedLink *link = IMSharedLinkFromResponse(raw);
			if (!link) {
				completion(nil, IMSharedLinkMalformedResponse(_(@"The server returned an invalid shared-link list.")));
				return;
			}
			[links addObject:link];
		}
		completion(links, nil);
	}];
}

+ (void)linkForId:(NSString *)linkId completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	if (!linkId.length) {
		completion(nil, IMSharedLinkError(_(@"No shared link selected.")));
		return;
	}
	[[IMApiClient shared] GET:[NSString stringWithFormat:@"/shared-links/%@", linkId]
	                       query:nil
	                  completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMSharedLink *link = IMSharedLinkFromResponse(json);
		completion(link, link ? nil : IMSharedLinkMalformedResponse(_(@"The server returned an invalid shared link.")));
	}];
}

+ (void)removeLinkId:(NSString *)linkId completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (!linkId.length) {
		completion(NO, IMSharedLinkError(_(@"No shared link selected.")));
		return;
	}
	[[IMApiClient shared] DELETE:[NSString stringWithFormat:@"/shared-links/%@", linkId]
	                          body:nil
	                    completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (void)updateLinkId:(NSString *)linkId
               fields:(NSDictionary<NSString *,id> *)fields
       linkCompletion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	if (!linkId.length) {
		completion(nil, IMSharedLinkError(_(@"No shared link selected.")));
		return;
	}
	NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
	for (NSString *key in IMSharedLinkOptionKeys()) {
		id value = fields[key];
		if (value) normalized[key] = value;
	}
	if ([normalized[@"showMetadata"] respondsToSelector:@selector(boolValue)] && ![normalized[@"showMetadata"] boolValue]) {
		normalized[@"allowDownload"] = @NO;
	}
	[[IMApiClient shared] PATCH:[NSString stringWithFormat:@"/shared-links/%@", linkId]
	                          body:normalized
	                    completion:^(id json, NSError *error) {
		if (error) {
			completion(nil, error);
			return;
		}
		IMSharedLink *link = IMSharedLinkFromResponse(json);
		completion(link, link ? nil : IMSharedLinkMalformedResponse(_(@"The server returned an invalid shared link.")));
	}];
}

+ (void)updateLinkId:(NSString *)linkId
               fields:(NSDictionary<NSString *,id> *)fields
          completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	[self updateLinkId:linkId fields:fields linkCompletion:^(IMSharedLink *link, NSError *error) {
		completion(link != nil && error == nil, error);
	}];
}

#pragma mark - Membership

+ (void)addAssetIds:(NSArray<NSString *> *)assetIds
           toLinkId:(NSString *)linkId
         completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (!IMSharedLinkAssetIDsValid(assetIds) || !linkId.length) {
		completion(NO, IMSharedLinkError(_(@"No assets selected.")));
		return;
	}
	[[IMApiClient shared] PUT:[NSString stringWithFormat:@"/shared-links/%@/assets", linkId]
	                       body:@{ @"assetIds" : assetIds }
	                 completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
			return;
		}
		NSError *responseError = IMSharedLinkBulkResponseError(json, assetIds);
		completion(responseError == nil, responseError);
	}];
}

+ (void)removeAssetIds:(NSArray<NSString *> *)assetIds
              fromLinkId:(NSString *)linkId
             completion:(void (^)(BOOL success, NSError *_Nullable error))completion {
	if (!IMSharedLinkAssetIDsValid(assetIds) || !linkId.length) {
		completion(NO, IMSharedLinkError(_(@"No assets selected.")));
		return;
	}
	[[IMApiClient shared] DELETE:[NSString stringWithFormat:@"/shared-links/%@/assets", linkId]
	                          body:@{ @"assetIds" : assetIds }
	                    completion:^(id json, NSError *error) {
		if (error) {
			completion(NO, error);
			return;
		}
		NSError *responseError = IMSharedLinkBulkResponseError(json, assetIds);
		completion(responseError == nil, responseError);
	}];
}

#pragma mark - Public-link guest access

+ (void)loginWithKey:(NSString *)key
                slug:(NSString *)slug
            password:(NSString *)password
          completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	NSError *identifierError = nil;
	NSArray<NSURLQueryItem *> *queryItems = IMSharedLinkIdentifierQuery(key, slug, &identifierError);
	NSString *trimmedPassword = [password isKindOfClass:[NSString class]]
	    ? [password stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
	    : @"";
	if (!queryItems || trimmedPassword.length == 0) {
		NSError *error = identifierError ?: IMSharedLinkError(_(@"A shared-link password is required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return;
	}
	IMApiClient *client = nil;
	if (IMSession.shared.isLoggedIn) {
		client = [IMApiClient shared];
	} else {
		client = IMSharedLinkStoredGuestClient(&identifierError);
	}
	if (!client) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, identifierError ?: IMSharedLinkError(_(@"No server URL is configured."))); });
		return;
	}
	BOOL disposableClient = client != [IMApiClient shared];
	[client POST:@"/shared-links/login"
	   queryItems:queryItems
	         body:@{ @"password" : trimmedPassword }
	   completion:^(id json, NSError *error) {
		if (disposableClient) [client invalidate];
		if (error) {
			completion(nil, error);
			return;
		}
		if (!IMSharedLinkGuestResponseValid(json)) {
			completion(nil, IMSharedLinkGuestMalformedError());
			return;
		}
		IMSharedLink *link = IMSharedLinkFromResponse(json);
		completion(link, link ? nil : IMSharedLinkGuestMalformedError());
	}];
}

+ (void)linkForKey:(NSString *)key
              slug:(NSString *)slug
        completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	NSError *identifierError = nil;
	NSArray<NSURLQueryItem *> *queryItems = IMSharedLinkIdentifierQuery(key, slug, &identifierError);
	if (!queryItems) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, identifierError); });
		return;
	}
	IMApiClient *client = nil;
	if (IMSession.shared.isLoggedIn) {
		client = [IMApiClient shared];
	} else {
		client = IMSharedLinkStoredGuestClient(&identifierError);
	}
	if (!client) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, identifierError ?: IMSharedLinkError(_(@"No server URL is configured."))); });
		return;
	}
	BOOL disposableClient = client != [IMApiClient shared];
	[client GET:@"/shared-links/me"
	  queryItems:queryItems
	  completion:^(id json, NSError *error) {
		if (disposableClient) [client invalidate];
		if (error) {
			completion(nil, error);
			return;
		}
		if (!IMSharedLinkGuestResponseValid(json)) {
			completion(nil, IMSharedLinkGuestMalformedError());
			return;
		}
		IMSharedLink *link = IMSharedLinkFromResponse(json);
		completion(link, link ? nil : IMSharedLinkGuestMalformedError());
	}];
}

+ (void)linkForPublicURL:(NSURL *)publicURL
              completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	NSError *parseError = nil;
	NSURL *baseURL = IMSharedLinkAPIBaseURL(publicURL, &parseError);
	NSString *key = nil;
	NSString *slug = nil;
	if (!baseURL || !IMSharedLinkIdentifiersFromPublicURL(publicURL, &key, &slug, &parseError)) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parseError ?: IMSharedLinkError(_(@"The public-link URL is invalid."))); });
		return;
	}
	NSArray<NSURLQueryItem *> *queryItems = IMSharedLinkIdentifierQuery(key, slug, &parseError);
	if (!queryItems) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parseError); });
		return;
	}
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	client.anonymous = YES;
	[client GET:@"/shared-links/me" queryItems:queryItems completion:^(id json, NSError *error) {
		[client invalidate];
		if (error) { completion(nil, error); return; }
		if (!IMSharedLinkGuestResponseValid(json)) {
			completion(nil, IMSharedLinkGuestMalformedError());
			return;
		}
		IMSharedLink *link = IMSharedLinkFromResponse(json);
		completion(link, link ? nil : IMSharedLinkGuestMalformedError());
	}];
}

+ (void)loginForPublicURL:(NSURL *)publicURL
                 password:(NSString *)password
               completion:(void (^)(IMSharedLink *_Nullable link, NSError *_Nullable error))completion {
	NSError *parseError = nil;
	NSURL *baseURL = IMSharedLinkAPIBaseURL(publicURL, &parseError);
	NSString *key = nil;
	NSString *slug = nil;
	if (!baseURL || !IMSharedLinkIdentifiersFromPublicURL(publicURL, &key, &slug, &parseError)) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parseError ?: IMSharedLinkError(_(@"The public-link URL is invalid."))); });
		return;
	}
	NSArray<NSURLQueryItem *> *queryItems = IMSharedLinkIdentifierQuery(key, slug, &parseError);
	NSString *trimmedPassword = [password isKindOfClass:[NSString class]]
	    ? [password stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
	if (!queryItems || trimmedPassword.length == 0) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parseError ?: IMSharedLinkError(_(@"A shared-link password is required."))); });
		return;
	}
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	client.anonymous = YES;
	[client POST:@"/shared-links/login"
	   queryItems:queryItems
	         body:@{ @"password": trimmedPassword }
	   completion:^(id json, NSError *error) {
		[client invalidate];
		if (error) { completion(nil, error); return; }
		if (!IMSharedLinkGuestResponseValid(json)) {
			completion(nil, IMSharedLinkGuestMalformedError());
			return;
		}
		IMSharedLink *link = IMSharedLinkFromResponse(json);
		completion(link, link ? nil : IMSharedLinkGuestMalformedError());
	}];
}

#pragma mark - Public media

+ (NSURLSessionTask *)guestThumbnailDataForAssetId:(NSString *)assetId
                                          publicURL:(NSURL *)publicURL
                                               size:(NSString *)size
                                         completion:(void (^)(NSData *_Nullable data,
                                                              NSError *_Nullable error))completion {
	if (!IMSharedLinkUUIDv4Valid(assetId) || ![size isKindOfClass:[NSString class]] || size.length == 0 ||
	    [size rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) {
		NSError *error = IMSharedLinkError(_(@"A valid asset ID and thumbnail size are required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	NSError *parseError = nil;
	NSURL *baseURL = IMSharedLinkAPIBaseURL(publicURL, &parseError);
	NSString *key = nil;
	NSString *slug = nil;
	if (!baseURL || !IMSharedLinkIdentifiersFromPublicURL(publicURL, &key, &slug, &parseError)) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parseError ?: IMSharedLinkError(_(@"The public-link URL is invalid."))); });
		return nil;
	}
	NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
	query[@"size"] = size;
	if (key.length) query[@"key"] = key;
	if (slug.length) query[@"slug"] = slug;
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	client.anonymous = YES;
	NSString *path = [NSString stringWithFormat:@"/assets/%@/thumbnail", assetId];
	NSURLSessionTask *task = [client getData:path query:query completion:^(NSData *data, NSError *error) {
		[client invalidate];
		completion(data, error);
	}];
	if (!task) [client invalidate];
	return task;
}

+ (NSURLSessionTask *)guestOriginalFileForAssetId:(NSString *)assetId
                                         publicURL:(NSURL *)publicURL
                                    destinationURL:(NSURL *)destinationURL
                                        completion:(void (^)(NSURL *_Nullable fileURL,
                                                             NSError *_Nullable error))completion {
	if (!IMSharedLinkUUIDv4Valid(assetId) || ![destinationURL isKindOfClass:[NSURL class]] ||
	    !destinationURL.isFileURL || destinationURL.path.length == 0) {
		NSError *error = IMSharedLinkError(_(@"A valid asset ID and local destination file are required."));
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	NSError *parseError = nil;
	NSURL *baseURL = IMSharedLinkAPIBaseURL(publicURL, &parseError);
	NSString *key = nil;
	NSString *slug = nil;
	if (!baseURL || !IMSharedLinkIdentifiersFromPublicURL(publicURL, &key, &slug, &parseError)) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, parseError ?: IMSharedLinkError(_(@"The public-link URL is invalid."))); });
		return nil;
	}
	NSMutableDictionary<NSString *, NSString *> *query = [NSMutableDictionary dictionary];
	if (key.length) query[@"key"] = key;
	if (slug.length) query[@"slug"] = slug;
	IMApiClient *client = [[IMApiClient alloc] initWithBaseURL:baseURL];
	client.anonymous = YES;
	NSString *path = [NSString stringWithFormat:@"/assets/%@/original", assetId];
	NSURLSessionTask *task = [client downloadFile:path
	                                        query:query
	                               destinationURL:destinationURL
	                                    completion:^(NSURL *fileURL, NSError *error) {
		[client invalidate];
		completion(fileURL, error);
	}];
	if (!task) [client invalidate];
	return task;
}

@end
