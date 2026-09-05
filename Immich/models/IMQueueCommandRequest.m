#import "IMQueueCommandRequest.h"
#include <string.h>

static BOOL IMQueueCommandBoolean(id value) {
	if (![value isKindOfClass:[NSNumber class]]) return NO;
	const char *type = [(NSNumber *)value objCType];
	return type && (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(bool)) == 0);
}

NSArray<NSString *> *IMQueueNames(void) {
	static NSArray<NSString *> *names;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		names = @[
			@"thumbnailGeneration", @"metadataExtraction", @"videoConversion", @"faceDetection",
			@"facialRecognition", @"smartSearch", @"duplicateDetection", @"backgroundTask",
			@"storageTemplateMigration", @"migration", @"search", @"sidecar", @"library",
			@"notifications", @"backupDatabase", @"ocr", @"workflow", @"integrityCheck", @"editor",
		];
	});
	return names;
}

BOOL IMQueueNameIsKnown(NSString *name) {
	return [name isKindOfClass:[NSString class]] && [IMQueueNames() containsObject:name];
}

NSArray<NSString *> *IMQueueCommands(void) {
	static NSArray<NSString *> *commands;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		commands = @[ @"start", @"pause", @"resume", @"empty", @"clear-failed" ];
	});
	return commands;
}

BOOL IMQueueCommandIsKnown(NSString *command) {
	return [command isKindOfClass:[NSString class]] && [IMQueueCommands() containsObject:command];
}

@interface IMQueueCommandRequest ()
@property (nonatomic, copy) NSString *command;
@property (nonatomic, strong, nullable) NSNumber *force;
@end

@implementation IMQueueCommandRequest

+ (nullable instancetype)requestWithCommand:(NSString *)command force:(NSNumber *)force {
	if (!IMQueueCommandIsKnown(command)) return nil;
	if (force != nil && !IMQueueCommandBoolean(force)) return nil;
	IMQueueCommandRequest *request = [[self alloc] init];
	request.command = [command copy];
	request.force = [force copy];
	return request;
}

+ (nullable instancetype)requestWithDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	id command = dictionary[@"command"];
	id force = dictionary[@"force"];
	if (force != nil && !IMQueueCommandBoolean(force)) return nil;
	return [self requestWithCommand:command force:force];
}

- (NSDictionary<NSString *, id> *)requestDictionary {
	NSMutableDictionary<NSString *, id> *body = [@{ @"command": self.command } mutableCopy];
	if (self.force != nil) body[@"force"] = self.force;
	return [body copy];
}

@end
