#import <Foundation/Foundation.h>
#import "IMDatabaseBackup.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMDatabaseBackupApi : NSObject
+ (NSURLSessionTask *)allBackupsWithCompletion:(void (^)(NSArray<IMDatabaseBackup *> *_Nullable backups, NSError *_Nullable error))completion;
+ (NSURLSessionTask *)deleteBackups:(NSArray<NSString *> *)filenames
                         completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (NSURLSessionTask *)downloadBackup:(NSString *)filename
                           completion:(void (^)(NSData *_Nullable data, NSError *_Nullable error))completion;
+ (NSURLSessionTask *)uploadBackupData:(NSData *)data
                              filename:(NSString *)filename
                            completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (NSURLSessionTask *)startRestoreFlowWithCompletion:(void (^)(BOOL success, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
