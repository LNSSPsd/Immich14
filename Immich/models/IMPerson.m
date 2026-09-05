#import "IMPerson.h"

@interface IMPerson ()
@property (nonatomic, copy) NSString *personId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL isHidden;
@end

@implementation IMPerson

+ (nullable instancetype)personWithDictionary:(NSDictionary *)dict {
	if (![dict isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSString *personId = dict[@"id"];
	if (![personId isKindOfClass:[NSString class]] || personId.length == 0) {
		return nil;
	}
	NSString *name = dict[@"name"];
	IMPerson *person = [[IMPerson alloc] init];
	person.personId = personId;
	person.name = [name isKindOfClass:[NSString class]] ? name : @"";
	person.isHidden = [dict[@"isHidden"] isKindOfClass:[NSNumber class]] ? [dict[@"isHidden"] boolValue] : NO;
	return person;
}

+ (NSArray<IMPerson *> *)peopleWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) {
		return @[];
	}
	NSMutableArray<IMPerson *> *people = [NSMutableArray arrayWithCapacity:array.count];
	for (NSDictionary *dict in array) {
		IMPerson *person = [IMPerson personWithDictionary:dict];
		if (person) {
			[people addObject:person];
		}
	}
	return people;
}

@end
