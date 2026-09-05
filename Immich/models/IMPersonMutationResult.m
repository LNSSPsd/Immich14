#import "IMPersonMutationResult.h"

static id IMPersonMutationValueOrNil(id value) {
	return [value isKindOfClass:[NSNull class]] ? nil : value;
}

@interface IMPersonMutationResult ()
@property (nonatomic, copy) NSString *resultId;
@property (nonatomic) BOOL success;
@property (nonatomic, copy, nullable) NSString *error;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@end

@implementation IMPersonMutationResult

+ (nullable instancetype)resultWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id identifier = IMPersonMutationValueOrNil(dictionary[@"id"]);
	if (![identifier isKindOfClass:[NSString class]] || [(NSString *)identifier length] == 0) return nil;
	id successValue = IMPersonMutationValueOrNil(dictionary[@"success"]);
	if (![successValue isKindOfClass:[NSNumber class]]) return nil;
	id error = IMPersonMutationValueOrNil(dictionary[@"error"]);
	if (error != nil && ![error isKindOfClass:[NSString class]]) return nil;
	id errorMessage = IMPersonMutationValueOrNil(dictionary[@"errorMessage"]);
	if (errorMessage != nil && ![errorMessage isKindOfClass:[NSString class]]) return nil;
	IMPersonMutationResult *result = [[self alloc] init];
	result.resultId = [identifier copy];
	result.success = [successValue boolValue];
	result.error = [error isKindOfClass:[NSString class]] ? [error copy] : nil;
	result.errorMessage = [errorMessage isKindOfClass:[NSString class]] ? [errorMessage copy] : nil;
	return result;
}

+ (NSArray<IMPersonMutationResult *> *)resultsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray<IMPersonMutationResult *> *results = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMPersonMutationResult *result = [value isKindOfClass:[NSDictionary class]] ? [self resultWithResponseDictionary:value] : nil;
		if (result) [results addObject:result];
	}
	return [results copy];
}

+ (nullable NSArray<IMPersonMutationResult *> *)strictResultsWithResponseArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray<IMPersonMutationResult *> *results = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) {
		IMPersonMutationResult *result = [value isKindOfClass:[NSDictionary class]]
		    ? [self resultWithResponseDictionary:value]
		    : nil;
		if (!result) return nil;
		[results addObject:result];
	}
	return [results copy];
}

@end
