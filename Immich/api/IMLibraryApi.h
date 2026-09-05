#import <Foundation/Foundation.h>
#import "IMLibrary.h"

NS_ASSUME_NONNULL_BEGIN

@interface IMLibraryApi : NSObject
+ (void)allLibrariesWithCompletion:(void (^)(NSArray<IMLibrary *> *_Nullable libraries, NSError *_Nullable error))completion;
+ (void)createLibraryWithName:(NSString *)name
	                   ownerId:(NSString *)ownerId
	              importPaths:(NSArray<NSString *> *)importPaths
	       exclusionPatterns:(NSArray<NSString *> *)exclusionPatterns
	                completion:(void (^)(IMLibrary *_Nullable library, NSError *_Nullable error))completion;
+ (void)updateLibraryId:(NSString *)libraryId
	                 name:(nullable NSString *)name
	           importPaths:(nullable NSArray<NSString *> *)importPaths
	    exclusionPatterns:(nullable NSArray<NSString *> *)exclusionPatterns
	             completion:(void (^)(IMLibrary *_Nullable library, NSError *_Nullable error))completion;
+ (void)deleteLibraryId:(NSString *)libraryId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)scanLibraryId:(NSString *)libraryId completion:(void (^)(BOOL success, NSError *_Nullable error))completion;
+ (void)statisticsForLibraryId:(NSString *)libraryId completion:(void (^)(IMLibraryStats *_Nullable stats, NSError *_Nullable error))completion;
+ (void)validateLibraryId:(NSString *)libraryId
	             importPaths:(NSArray<NSString *> *)importPaths
	              completion:(void (^)(NSArray<IMLibraryValidation *> *_Nullable results, NSError *_Nullable error))completion;
@end

NS_ASSUME_NONNULL_END
