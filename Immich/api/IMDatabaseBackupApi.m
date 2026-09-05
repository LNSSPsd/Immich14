#import "IMDatabaseBackupApi.h"
#import "IMApiClient.h"
#import "common.h"

static NSError *IMDatabaseBackupError(NSString *message) {
	return [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL IMValidDatabaseBackupFilename(NSString *filename) {
	if (filename.length == 0 || filename.length > 255) return NO;
	if (![filename hasSuffix:@".sql"] && ![filename hasSuffix:@".sql.gz"]) return NO;
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-. "];
	if ([filename rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound) return NO;
	if ([filename rangeOfString:@" "].location != NSNotFound) return NO;
	return YES;
}

@implementation IMDatabaseBackupApi

+ (NSURLSessionTask *)allBackupsWithCompletion:(void (^)(NSArray<IMDatabaseBackup *> *, NSError *))completion {
	return [[IMApiClient shared] GET:@"/admin/database-backups" query:nil completion:^(id json, NSError *error) {
		if (error) { completion(nil, error); return; }
		if (![json isKindOfClass:[NSDictionary class]]) {
			completion(nil, IMDatabaseBackupError(_(@"The server returned an invalid backup response.")));
			return;
		}
		id raw = ((NSDictionary *)json)[@"backups"];
		if (![raw isKindOfClass:[NSArray class]]) {
			completion(nil, IMDatabaseBackupError(_(@"The server returned an invalid backup list.")));
			return;
		}
		completion([IMDatabaseBackup backupsWithArray:raw], nil);
	}];
}

+ (NSURLSessionTask *)deleteBackups:(NSArray<NSString *> *)filenames
                         completion:(void (^)(BOOL, NSError *))completion {
	NSMutableArray<NSString *> *valid = [NSMutableArray array];
	for (id value in filenames) {
		if (![value isKindOfClass:[NSString class]] || !IMValidDatabaseBackupFilename(value)) {
			completion(NO, IMDatabaseBackupError(_(@"One or more backup filenames are invalid.")));
			return nil;
		}
		[valid addObject:value];
	}
	if (valid.count == 0) { completion(YES, nil); return nil; }
	return [[IMApiClient shared] DELETE:@"/admin/database-backups" body:@{ @"backups": valid } completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (NSURLSessionTask *)downloadBackup:(NSString *)filename
                           completion:(void (^)(NSData *, NSError *))completion {
	if (!IMValidDatabaseBackupFilename(filename)) {
		completion(nil, IMDatabaseBackupError(_(@"The backup filename is invalid.")));
		return nil;
	}
	NSString *escaped = [filename stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
	if (escaped.length == 0) {
		completion(nil, IMDatabaseBackupError(_(@"The backup filename is invalid.")));
		return nil;
	}
	return [[IMApiClient shared] getData:[NSString stringWithFormat:@"/admin/database-backups/%@", escaped]
	                               query:nil
	                          completion:completion];
}

+ (NSURLSessionTask *)uploadBackupData:(NSData *)data
                              filename:(NSString *)filename
                            completion:(void (^)(BOOL, NSError *))completion {
	if (data.length == 0 || !IMValidDatabaseBackupFilename(filename)) {
		completion(NO, IMDatabaseBackupError(_(@"Choose a valid, non-empty SQL backup file.")));
		return nil;
	}
	return [[IMApiClient shared] multipartPOST:@"/admin/database-backups/upload"
	                                    fields:@{}
	                                 fileField:@"file"
	                                  filename:filename
	                                  fileData:data
	                                completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

+ (NSURLSessionTask *)startRestoreFlowWithCompletion:(void (^)(BOOL, NSError *))completion {
	return [[IMApiClient shared] POST:@"/admin/database-backups/start-restore" body:nil completion:^(id json, NSError *error) {
		completion(error == nil, error);
	}];
}

@end
