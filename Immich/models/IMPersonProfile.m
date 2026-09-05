#import "IMPersonProfile.h"

static id IMPersonProfileValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMPersonProfile ()
@property (nonatomic, copy) NSString *personId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *birthDate;
@property (nonatomic, copy) NSString *thumbnailPath;
@property (nonatomic, getter=isHidden) BOOL hidden;
@property (nonatomic, getter=isFavorite) BOOL favorite;
@property (nonatomic, copy, nullable) NSString *color;
@property (nonatomic, copy, nullable) NSString *updatedAt;
@end

@implementation IMPersonProfile

+ (nullable instancetype)personWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id identifier = IMPersonProfileValueOrNil(dictionary[@"id"]);
	if (![identifier isKindOfClass:[NSString class]] || [(NSString *)identifier length] == 0) {
		return nil;
	}
	IMPersonProfile *person = [[self alloc] init];
	person.personId = [identifier copy];
	id value = IMPersonProfileValueOrNil(dictionary[@"name"]);
	person.name = [value isKindOfClass:[NSString class]] ? [value copy] : @"";
	value = IMPersonProfileValueOrNil(dictionary[@"birthDate"]);
	person.birthDate = [value isKindOfClass:[NSString class]] ? [value copy] : nil;
	value = IMPersonProfileValueOrNil(dictionary[@"thumbnailPath"]);
	person.thumbnailPath = [value isKindOfClass:[NSString class]] ? [value copy] : @"";
	value = IMPersonProfileValueOrNil(dictionary[@"isHidden"]);
	person.hidden = [value isKindOfClass:[NSNumber class]] && [value boolValue];
	value = IMPersonProfileValueOrNil(dictionary[@"isFavorite"]);
	person.favorite = [value isKindOfClass:[NSNumber class]] && [value boolValue];
	value = IMPersonProfileValueOrNil(dictionary[@"color"]);
	person.color = [value isKindOfClass:[NSString class]] ? [value copy] : nil;
	value = IMPersonProfileValueOrNil(dictionary[@"updatedAt"]);
	person.updatedAt = [value isKindOfClass:[NSString class]] ? [value copy] : nil;
	return person;
}

+ (NSArray<IMPersonProfile *> *)peopleWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMPersonProfile *> *people = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMPersonProfile *person = [value isKindOfClass:[NSDictionary class]] ? [self personWithResponseDictionary:value] : nil;
		if (person) [people addObject:person];
	}
	return [people copy];
}

@end
