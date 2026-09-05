#import "IMQueueLegacyResponse.h"
#include <math.h>
#include <string.h>

static BOOL IMQueueLegacyBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

static BOOL IMQueueLegacyInteger(id value, NSInteger *outValue) {
	if (![value isKindOfClass:[NSNumber class]] || IMQueueLegacyBoolean(value)) return NO;
	double number = [(NSNumber *)value doubleValue];
	if (!isfinite(number) || floor(number) != number || number < -9007199254740991.0 ||
	    number > 9007199254740991.0 || number < (double)NSIntegerMin || number > (double)NSIntegerMax) {
		return NO;
	}
	if (outValue) *outValue = [(NSNumber *)value integerValue];
	return YES;
}

@interface IMQueueLegacyStatus ()
@property (nonatomic, getter=isActive) BOOL active;
@property (nonatomic, getter=isPaused) BOOL paused;
@end

@interface IMQueueLegacyJobCounts ()
@property (nonatomic) NSInteger active;
@property (nonatomic) NSInteger completed;
@property (nonatomic) NSInteger delayed;
@property (nonatomic) NSInteger failed;
@property (nonatomic) NSInteger waiting;
@property (nonatomic) NSInteger paused;
@end

@interface IMQueueLegacyResponse ()
@property (nonatomic, strong) IMQueueLegacyStatus *queueStatus;
@property (nonatomic, strong) IMQueueLegacyJobCounts *jobCounts;
@end

@implementation IMQueueLegacyStatus

+ (nullable instancetype)statusWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]] ||
	    !IMQueueLegacyBoolean(dictionary[@"isActive"]) || !IMQueueLegacyBoolean(dictionary[@"isPaused"])) {
		return nil;
	}
	IMQueueLegacyStatus *status = [[self alloc] init];
	status.active = [dictionary[@"isActive"] boolValue];
	status.paused = [dictionary[@"isPaused"] boolValue];
	return status;
}

@end

@implementation IMQueueLegacyJobCounts

+ (nullable instancetype)countsWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	NSInteger active = 0, completed = 0, delayed = 0, failed = 0, waiting = 0, paused = 0;
	if (!IMQueueLegacyInteger(dictionary[@"active"], &active) ||
	    !IMQueueLegacyInteger(dictionary[@"completed"], &completed) ||
	    !IMQueueLegacyInteger(dictionary[@"delayed"], &delayed) ||
	    !IMQueueLegacyInteger(dictionary[@"failed"], &failed) ||
	    !IMQueueLegacyInteger(dictionary[@"waiting"], &waiting) ||
	    !IMQueueLegacyInteger(dictionary[@"paused"], &paused)) {
		return nil;
	}
	IMQueueLegacyJobCounts *counts = [[self alloc] init];
	counts.active = active;
	counts.completed = completed;
	counts.delayed = delayed;
	counts.failed = failed;
	counts.waiting = waiting;
	counts.paused = paused;
	return counts;
}

@end

@implementation IMQueueLegacyResponse

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	IMQueueLegacyStatus *status = [IMQueueLegacyStatus statusWithResponseDictionary:dictionary[@"queueStatus"]];
	IMQueueLegacyJobCounts *counts = [IMQueueLegacyJobCounts countsWithResponseDictionary:dictionary[@"jobCounts"]];
	if (!status || !counts) return nil;
	IMQueueLegacyResponse *response = [[self alloc] init];
	response.queueStatus = status;
	response.jobCounts = counts;
	return response;
}

@end
