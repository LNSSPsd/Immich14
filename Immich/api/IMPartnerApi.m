#import "IMPartnerApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMPartnerMalformedResponse(void) {
    return [NSError errorWithDomain:IMApiErrorDomain
                                code:2
                            userInfo:@{NSLocalizedDescriptionKey : _(@"The server returned an invalid partner response.")}];
}

static NSError *IMPartnerValidationError(NSString *message) {
    return [NSError errorWithDomain:IMApiErrorDomain
                                code:1
                            userInfo:@{NSLocalizedDescriptionKey : message ?: _(@"The partner request is invalid.")}];
}

static BOOL IMPartnerUUIDv4(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length != 36) return NO;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
    if (!uuid) return NO;
    NSString *canonical = uuid.UUIDString.lowercaseString;
    return canonical.length == 36 && [canonical characterAtIndex:14] == '4' &&
           ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
            [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

static NSString *IMPartnerPathComponent(NSString *value) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

static BOOL IMPartnerJSONBoolean(id value) {
    return [value isKindOfClass:[NSNumber class]] &&
           ([(NSNumber *)value doubleValue] == 0.0 || [(NSNumber *)value doubleValue] == 1.0);
}

static BOOL IMPartnerAvatarColor(id value) {
	return [value isKindOfClass:[NSString class]] &&
	       [[NSSet setWithArray:@[ @"primary", @"pink", @"red", @"yellow", @"blue", @"green", @"purple", @"orange", @"gray", @"amber" ]] containsObject:value];
}

static BOOL IMPartnerRawUserIsValid(NSDictionary *dictionary, BOOL requireTimeline) {
    if (![dictionary isKindOfClass:[NSDictionary class]] || !IMPartnerUUIDv4(dictionary[@"id"]) ||
        ![dictionary[@"name"] isKindOfClass:[NSString class]] ||
        ![dictionary[@"email"] isKindOfClass:[NSString class]] ||
        ![dictionary[@"profileImagePath"] isKindOfClass:[NSString class]] ||
        !IMPartnerAvatarColor(dictionary[@"avatarColor"]) ||
        ![dictionary[@"profileChangedAt"] isKindOfClass:[NSString class]] ||
        !IMDateFromServerTimestamp(dictionary[@"profileChangedAt"])) return NO;
    return !requireTimeline || IMPartnerJSONBoolean(dictionary[@"inTimeline"]);
}

static BOOL IMPartnerResponseIsValid(IMPartner *partner) {
    return partner != nil && IMPartnerUUIDv4(partner.partnerId) && partner.name != nil &&
           partner.email != nil && partner.profileImagePath != nil && partner.avatarColor != nil &&
           partner.profileChangedAt.length > 0 && IMDateFromServerTimestamp(partner.profileChangedAt);
}

@implementation IMPartnerApi
+ (void)partnersWithDirection:(NSString *)direction completion:(void (^)(NSArray<IMPartner *> *, NSError *))completion {
    if (![direction isKindOfClass:[NSString class]] ||
        (![direction isEqualToString:@"shared-with"] && ![direction isEqualToString:@"shared-by"])) {
        completion(nil, IMPartnerValidationError(_(@"Choose a valid partner direction.")));
        return;
    }
    [[IMApiClient shared] GET:@"/partners" query:@{ @"direction": direction } completion:^(id json, NSError *error) {
        if (error || ![json isKindOfClass:[NSArray class]]) { completion(nil,error ?: IMPartnerMalformedResponse()); return; }
        for (id raw in (NSArray *)json) if (!IMPartnerRawUserIsValid(raw, YES)) { completion(nil, IMPartnerMalformedResponse()); return; }
        NSArray<IMPartner *> *partners = [IMPartner partnersWithArray:json];
        if (partners.count != [(NSArray *)json count]) { completion(nil, IMPartnerMalformedResponse()); return; }
        for (IMPartner *partner in partners) if (!IMPartnerResponseIsValid(partner)) { completion(nil, IMPartnerMalformedResponse()); return; }
        completion(partners,nil);
    }];
}
+ (void)usersWithCompletion:(void (^)(NSArray<IMPartner *> *, NSError *))completion {
    [[IMApiClient shared] GET:@"/users" query:nil completion:^(id json, NSError *error) {
        if (error || ![json isKindOfClass:[NSArray class]]) {
            completion(nil, error ?: IMPartnerMalformedResponse());
            return;
        }
        for (id raw in (NSArray *)json) if (!IMPartnerRawUserIsValid(raw, NO)) { completion(nil, IMPartnerMalformedResponse()); return; }
        NSArray<IMPartner *> *partners = [IMPartner partnersWithArray:json];
        if (partners.count != [(NSArray *)json count]) { completion(nil, IMPartnerMalformedResponse()); return; }
        for (IMPartner *partner in partners) if (!IMPartnerUUIDv4(partner.partnerId)) { completion(nil, IMPartnerMalformedResponse()); return; }
        completion(partners, nil);
    }];
}
+ (void)createPartnerWithUserId:(NSString *)userId completion:(void (^)(IMPartner *, NSError *))completion {
    if (!IMPartnerUUIDv4(userId)) {
        completion(nil, IMPartnerValidationError(_(@"A valid user ID is required.")));
        return;
    }
    [[IMApiClient shared] POST:@"/partners" body:@{ @"sharedWithId": userId } completion:^(id json,NSError *error) {
        if (error) { completion(nil, error); return; }
        if (![json isKindOfClass:[NSDictionary class]]) { completion(nil, IMPartnerMalformedResponse()); return; }
        if (!IMPartnerRawUserIsValid(json, YES)) { completion(nil, IMPartnerMalformedResponse()); return; }
        IMPartner *partner = [IMPartner partnerWithDictionary:json];
        completion(partner, IMPartnerResponseIsValid(partner) ? nil : IMPartnerMalformedResponse());
    }];
}
+ (void)updatePartnerId:(NSString *)partnerId inTimeline:(BOOL)inTimeline completion:(void (^)(IMPartner *, NSError *))completion {
    if (!IMPartnerUUIDv4(partnerId)) {
        completion(nil, IMPartnerValidationError(_(@"A valid partner ID is required.")));
        return;
    }
    NSString *path=[NSString stringWithFormat:@"/partners/%@", IMPartnerPathComponent(partnerId)];
    [[IMApiClient shared] PUT:path body:@{ @"inTimeline": @(inTimeline) } completion:^(id json,NSError *error) {
        if (error) { completion(nil, error); return; }
        if (![json isKindOfClass:[NSDictionary class]]) { completion(nil, IMPartnerMalformedResponse()); return; }
        if (!IMPartnerRawUserIsValid(json, YES)) { completion(nil, IMPartnerMalformedResponse()); return; }
        IMPartner *partner = [IMPartner partnerWithDictionary:json];
        completion(partner, IMPartnerResponseIsValid(partner) ? nil : IMPartnerMalformedResponse());
    }];
}
+ (void)removePartnerId:(NSString *)partnerId completion:(void (^)(BOOL, NSError *))completion {
    if (!IMPartnerUUIDv4(partnerId)) {
        completion(NO, IMPartnerValidationError(_(@"A valid partner ID is required.")));
        return;
    }
    NSString *path=[NSString stringWithFormat:@"/partners/%@", IMPartnerPathComponent(partnerId)];
    [[IMApiClient shared] DELETE:path body:nil completion:^(id json,NSError *error){
        if (error) { completion(NO, error); return; }
        completion(json == nil, json == nil ? nil : IMPartnerMalformedResponse());
    }];
}
@end
