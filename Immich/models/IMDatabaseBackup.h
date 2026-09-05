#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMDatabaseBackup : NSObject
@property (nonatomic, copy, readonly) NSString *filename;
@property (nonatomic, readonly) unsigned long long filesize;
@property (nonatomic, copy, readonly) NSString *timezone;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMDatabaseBackup *> *)backupsWithArray:(NSArray *)array;
@end

NS_ASSUME_NONNULL_END
