#import "IMAlbumMember.h"

@implementation IMAlbumMember
+ (instancetype)memberWithUser:(NSDictionary *)user role:(NSString *)role {
	if (![user isKindOfClass:NSDictionary.class] || ![user[@"id"] isKindOfClass:NSString.class] || ![user[@"id"] length]) return nil;
	IMAlbumMember *member = [[self alloc] init];
	member->_userId = [user[@"id"] copy];
	member->_name = [user[@"name"] isKindOfClass:NSString.class] ? [user[@"name"] copy] : @"";
	member->_email = [user[@"email"] isKindOfClass:NSString.class] ? [user[@"email"] copy] : @"";
	member->_role = [role isKindOfClass:NSString.class] ? [role copy] : @"";
	return member;
}
@end
