#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const IMIntegrityReportTypeUntrackedFile;
FOUNDATION_EXPORT NSString *const IMIntegrityReportTypeMissingFile;
FOUNDATION_EXPORT NSString *const IMIntegrityReportTypeChecksumMismatch;

FOUNDATION_EXPORT NSArray<NSString *> *IMIntegrityReportTypes(void);
FOUNDATION_EXPORT BOOL IMIntegrityReportTypeIsKnown(NSString *_Nullable type);

@interface IMIntegrityReportSummary : NSObject

@property (nonatomic, readonly) NSInteger untrackedFileCount;
@property (nonatomic, readonly) NSInteger missingFileCount;
@property (nonatomic, readonly) NSInteger checksumMismatchCount;

+ (nullable instancetype)summaryWithResponseDictionary:(NSDictionary *)dictionary;

@end

NS_ASSUME_NONNULL_END
