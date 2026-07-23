#import "IMServerApi.h"
#import "IMApiClient.h"

@implementation IMServerApi

static NSString *sCachedServerVersion;
static IMServerStorage *sCachedServerStorage;

+ (void)serverVersionWithCompletion:(void (^)(NSString *_Nullable versionString, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/server/version"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    NSDictionary *dict = (NSDictionary *)json;
		    id major = dict[@"major"], minor = dict[@"minor"], patch = dict[@"patch"];
		    if (![major isKindOfClass:[NSNumber class]] || ![minor isKindOfClass:[NSNumber class]] ||
		        ![patch isKindOfClass:[NSNumber class]]) {
			    completion(nil, error);
			    return;
		    }
		    NSString *version = [NSString stringWithFormat:@"v%ld.%ld.%ld", (long)[major integerValue], (long)[minor integerValue],
		                                                    (long)[patch integerValue]];
		    sCachedServerVersion = version;
		    completion(version, nil);
	    }];
}

+ (nullable NSString *)cachedServerVersion {
	return sCachedServerVersion;
}

+ (void)serverStorageWithCompletion:(void (^)(IMServerStorage *_Nullable storage, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/server/storage"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    IMServerStorage *storage = [IMServerStorage storageWithDictionary:(NSDictionary *)json];
		    sCachedServerStorage = storage;
		    completion(storage, nil);
	    }];
}

+ (nullable IMServerStorage *)cachedServerStorage {
	return sCachedServerStorage;
}

@end
