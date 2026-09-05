#import "IMTestEmailResponse.h"

@interface IMTestEmailResponse ()
@property (nonatomic, copy) NSString *messageId;
@end

@implementation IMTestEmailResponse

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id messageId = dictionary[@"messageId"];
	if (![messageId isKindOfClass:[NSString class]] || [(NSString *)messageId length] == 0) return nil;
	IMTestEmailResponse *result = [[self alloc] init];
	result.messageId = [messageId copy];
	return result;
}

@end
