#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IMMaintenanceStorageFolder : NSObject

@property (nonatomic, copy, readonly) NSString *folder;
@property (nonatomic, readonly, getter=isReadable) BOOL readable;
@property (nonatomic, readonly, getter=isWritable) BOOL writable;
@property (nonatomic, readonly) NSInteger files;

+ (nullable instancetype)folderWithResponseDictionary:(NSDictionary *)dictionary;
+ (NSArray<IMMaintenanceStorageFolder *> *)foldersWithResponseArray:(NSArray *)array;

@end

@interface IMMaintenanceDetectInstall : NSObject

@property (nonatomic, copy, readonly) NSArray<IMMaintenanceStorageFolder *> *storage;

+ (nullable instancetype)responseWithDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
