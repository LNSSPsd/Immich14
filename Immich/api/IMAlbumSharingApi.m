#import "IMAlbumSharingApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMAlbumSharingResponseError(void) {
	return [NSError errorWithDomain:@"IMAlbumSharing" code:1 userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned an invalid album response.")}];
}

@implementation IMAlbumSharingApi
+ (void)membersForAlbumId:(NSString *)albumId completion:(void (^)(NSArray<IMAlbumMember *> *, NSError *))completion {
	[[IMApiClient shared] GET:[NSString stringWithFormat:@"/albums/%@", albumId] query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:NSDictionary.class] || ![json[@"albumUsers"] isKindOfClass:NSArray.class]) { completion(nil, error ?: IMAlbumSharingResponseError()); return; }
		NSMutableArray *members = [NSMutableArray array];
		for (id entry in json[@"albumUsers"]) {
			if (![entry isKindOfClass:NSDictionary.class]) { completion(nil, IMAlbumSharingResponseError()); return; }
			IMAlbumMember *member = [IMAlbumMember memberWithUser:entry[@"user"] role:entry[@"role"]];
			if (!member) { completion(nil, IMAlbumSharingResponseError()); return; }
			[members addObject:member];
		}
		completion(members, nil);
	}];
}
+ (void)availableUsersWithCompletion:(void (^)(NSArray<IMAlbumMember *> *, NSError *))completion {
	[[IMApiClient shared] GET:@"/users" query:nil completion:^(id json, NSError *error) {
		if (error || ![json isKindOfClass:NSArray.class]) { completion(nil, error ?: IMAlbumSharingResponseError()); return; }
		NSMutableArray *users = [NSMutableArray array];
		for (id entry in json) {
			IMAlbumMember *member = [IMAlbumMember memberWithUser:entry role:nil];
			if (!member) { completion(nil, IMAlbumSharingResponseError()); return; }
			[users addObject:member];
		}
		completion(users, nil);
	}];
}
+ (void)addUserId:(NSString *)userId role:(NSString *)role albumId:(NSString *)albumId completion:(void (^)(NSError *))completion {
	[[IMApiClient shared] PUT:[NSString stringWithFormat:@"/albums/%@/users", albumId] body:@{@"albumUsers": @[@{@"userId": userId, @"role": role}]} completion:^(id json, NSError *error) { completion(error); }];
}
+ (void)updateUserId:(NSString *)userId role:(NSString *)role albumId:(NSString *)albumId completion:(void (^)(NSError *))completion {
	[[IMApiClient shared] PUT:[NSString stringWithFormat:@"/albums/%@/user/%@", albumId, userId] body:@{@"role": role} completion:^(id json, NSError *error) { completion(error); }];
}
+ (void)removeUserId:(NSString *)userId albumId:(NSString *)albumId completion:(void (^)(NSError *))completion {
	[[IMApiClient shared] DELETE:[NSString stringWithFormat:@"/albums/%@/user/%@", albumId, userId] body:nil completion:^(id json, NSError *error) { completion(error); }];
}
@end
