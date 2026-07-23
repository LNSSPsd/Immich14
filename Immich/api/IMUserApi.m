#import "IMUserApi.h"
#import "IMApiClient.h"

@implementation IMUserApi

static IMUser *sCachedUser;

+ (void)currentUserWithCompletion:(void (^)(IMUser *_Nullable user, NSError *_Nullable error))completion {
	[[IMApiClient shared] GET:@"/users/me"
	                     query:nil
	                completion:^(id _Nullable json, NSError *_Nullable error) {
		    if (error || ![json isKindOfClass:[NSDictionary class]]) {
			    completion(nil, error);
			    return;
		    }
		    IMUser *user = [[IMUser alloc] initWithDictionary:(NSDictionary *)json];
		    sCachedUser = user;
		    completion(user, nil);
	    }];
}

+ (nullable IMUser *)cachedUser {
	return sCachedUser;
}

@end
