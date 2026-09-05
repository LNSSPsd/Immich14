#import "IMPartner.h"

static id IMPartnerValue(id v) { return [v isKindOfClass:[NSNull class]] ? nil : v; }

@interface IMPartner ()
@property (nonatomic, copy) NSString *partnerId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *email;
@property (nonatomic, copy) NSString *profileImagePath;
@property (nonatomic, copy) NSString *avatarColor;
@property (nonatomic) BOOL inTimeline;
@end

@implementation IMPartner
+ (nullable instancetype)partnerWithDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    id pid=IMPartnerValue(d[@"id"]), name=IMPartnerValue(d[@"name"]), email=IMPartnerValue(d[@"email"]);
    if (![pid isKindOfClass:[NSString class]]) return nil;
    IMPartner *p=[IMPartner new]; p.partnerId=pid;
    p.name=[name isKindOfClass:[NSString class]] ? name : @"";
    p.email=[email isKindOfClass:[NSString class]] ? email : @"";
    id path=IMPartnerValue(d[@"profileImagePath"]); p.profileImagePath=[path isKindOfClass:[NSString class]] ? path : @"";
    id color=IMPartnerValue(d[@"avatarColor"]); p.avatarColor=[color isKindOfClass:[NSString class]] ? color : @"";
    id timeline=IMPartnerValue(d[@"inTimeline"]); p.inTimeline=[timeline isKindOfClass:[NSNumber class]] && [timeline boolValue];
    return p;
}
+ (NSArray<IMPartner *> *)partnersWithArray:(NSArray *)array {
    NSMutableArray *result=[NSMutableArray array];
    for (id d in array) { IMPartner *p=[self partnerWithDictionary:d]; if (p) [result addObject:p]; }
    return result;
}
@end
