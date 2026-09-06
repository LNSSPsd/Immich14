#import "IMAPIKey.h"
#import "common.h"

static id IMAPIKeyValue(id value) { return [value isKindOfClass:[NSNull class]] ? nil : value; }

@interface IMAPIKey ()
@property (nonatomic, copy) NSString *keyId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *permissions;
@property (nonatomic, copy) NSString *createdAt;
@property (nonatomic, copy) NSString *updatedAt;
@end

@implementation IMAPIKey

+ (nullable instancetype)keyWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
	for (NSString *key in @[ @"createdAt", @"id", @"name", @"permissions", @"updatedAt" ]) {
		if (dictionary[key] == nil) return nil;
	}
	id keyId = dictionary[@"id"];
	if (![keyId isKindOfClass:[NSString class]] || [(NSString *)keyId length] != 36) return nil;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:keyId];
	if (!uuid) return nil;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	if (canonical.length != 36 || [canonical characterAtIndex:14] != '4' ||
	    ([canonical characterAtIndex:19] != '8' && [canonical characterAtIndex:19] != '9' &&
	     [canonical characterAtIndex:19] != 'a' && [canonical characterAtIndex:19] != 'b')) return nil;
	if (![dictionary[@"name"] isKindOfClass:[NSString class]] ||
	    ![dictionary[@"createdAt"] isKindOfClass:[NSString class]] ||
	    ![dictionary[@"updatedAt"] isKindOfClass:[NSString class]] ||
	    !IMDateFromServerTimestamp(dictionary[@"createdAt"]) ||
	    !IMDateFromServerTimestamp(dictionary[@"updatedAt"] ) ||
	    ![dictionary[@"permissions"] isKindOfClass:[NSArray class]]) return nil;
	static NSSet<NSString *> *validPermissions;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		validPermissions = [NSSet setWithArray:@[
			@"all", @"activity.create", @"activity.read", @"activity.update", @"activity.delete", @"activity.statistics",
			@"apiKey.create", @"apiKey.read", @"apiKey.update", @"apiKey.delete", @"asset.read", @"asset.update",
			@"asset.delete", @"asset.statistics", @"asset.share", @"asset.view", @"asset.download", @"asset.upload",
			@"asset.copy", @"asset.derive", @"asset.edit.get", @"asset.edit.create", @"asset.edit.delete",
			@"album.create", @"album.read", @"album.update", @"album.delete", @"album.statistics", @"album.share",
			@"album.download", @"albumAsset.create", @"albumAsset.delete", @"albumUser.create", @"albumUser.update",
			@"albumUser.delete", @"auth.changePassword", @"authDevice.delete", @"archive.read", @"backup.list",
			@"backup.download", @"backup.upload", @"backup.delete", @"duplicate.read", @"duplicate.delete",
			@"face.create", @"face.read", @"face.update", @"face.delete", @"folder.read", @"job.create", @"job.read",
			@"library.create", @"library.read", @"library.update", @"library.delete", @"library.statistics",
			@"timeline.read", @"timeline.download", @"maintenance", @"map.read", @"map.search", @"memory.create",
			@"memory.read", @"memory.update", @"memory.delete", @"memory.statistics", @"memoryAsset.create",
			@"memoryAsset.delete", @"notification.create", @"notification.read", @"notification.update",
			@"notification.delete", @"partner.create", @"partner.read", @"partner.update", @"partner.delete",
			@"person.create", @"person.read", @"person.update", @"person.delete", @"person.statistics", @"person.merge",
			@"person.reassign", @"pinCode.create", @"pinCode.update", @"pinCode.delete", @"plugin.create", @"plugin.read",
			@"plugin.update", @"plugin.delete", @"server.about", @"server.apkLinks", @"server.storage",
			@"server.statistics", @"server.versionCheck", @"serverLicense.read", @"serverLicense.update",
			@"serverLicense.delete", @"session.create", @"session.read", @"session.update", @"session.delete",
			@"session.lock", @"sharedLink.create", @"sharedLink.read", @"sharedLink.update", @"sharedLink.delete",
			@"stack.create", @"stack.read", @"stack.update", @"stack.delete", @"sync.stream", @"syncCheckpoint.read",
			@"syncCheckpoint.update", @"syncCheckpoint.delete", @"systemConfig.read", @"systemConfig.update",
			@"systemMetadata.read", @"systemMetadata.update", @"tag.create", @"tag.read", @"tag.update", @"tag.delete",
			@"tag.asset", @"user.read", @"user.update", @"userLicense.create", @"userLicense.read", @"userLicense.update",
			@"userLicense.delete", @"userOnboarding.read", @"userOnboarding.update", @"userOnboarding.delete",
			@"userPreference.read", @"userPreference.update", @"userProfileImage.create", @"userProfileImage.read",
			@"userProfileImage.update", @"userProfileImage.delete", @"queue.read", @"queue.update", @"queueJob.create",
			@"queueJob.read", @"queueJob.update", @"queueJob.delete", @"workflow.create", @"workflow.read",
			@"workflow.update", @"workflow.delete", @"adminUser.create", @"adminUser.read", @"adminUser.update",
			@"adminUser.delete", @"adminSession.read", @"adminAuth.unlinkAll"
		]];
	});
	for (id permission in (NSArray *)dictionary[@"permissions"]) {
		if (![permission isKindOfClass:[NSString class]] || ![validPermissions containsObject:permission]) return nil;
	}
	IMAPIKey *key = [[self alloc] initWithDictionary:dictionary];
	return key.keyId.length > 0 ? key : nil;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMAPIKeyValue(dictionary[@"id"]); _keyId = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAPIKeyValue(dictionary[@"name"]); _name = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAPIKeyValue(dictionary[@"permissions"]);
		NSMutableArray *permissions = [NSMutableArray array];
		if ([value isKindOfClass:[NSArray class]]) for (id permission in value) if ([permission isKindOfClass:[NSString class]]) [permissions addObject:permission];
		_permissions = [permissions copy];
		value = IMAPIKeyValue(dictionary[@"createdAt"]); _createdAt = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMAPIKeyValue(dictionary[@"updatedAt"]); _updatedAt = [value isKindOfClass:[NSString class]] ? value : @"";
	}
	return self;
}
+ (NSArray<IMAPIKey *> *)keysWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) if ([value isKindOfClass:[NSDictionary class]]) [result addObject:[[self alloc] initWithDictionary:value]];
	return result;
}
@end
