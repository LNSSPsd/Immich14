#import "IMIntegrityReportSummary.h"

NSString *const IMIntegrityReportTypeUntrackedFile = @"untracked_file";
NSString *const IMIntegrityReportTypeMissingFile = @"missing_file";
NSString *const IMIntegrityReportTypeChecksumMismatch = @"checksum_mismatch";

NSArray<NSString *> *IMIntegrityReportTypes(void) {
	static NSArray<NSString *> *types;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		types = @[ IMIntegrityReportTypeUntrackedFile, IMIntegrityReportTypeMissingFile, IMIntegrityReportTypeChecksumMismatch ];
	});
	return types;
}

BOOL IMIntegrityReportTypeIsKnown(NSString *type) {
	return [type isKindOfClass:[NSString class]] && [IMIntegrityReportTypes() containsObject:type];
}

static NSNumber *_Nullable IMIntegrityNonnegativeNumber(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        NSInteger integerValue = [value integerValue];
        return integerValue >= 0 ? @((long long)integerValue) : nil;
    }
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([(NSString *)value rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
            unsigned long long unsignedValue = [(NSString *)value longLongValue];
            if (unsignedValue <= (unsigned long long)NSIntegerMax) {
                return @((long long)unsignedValue);
            }
        }
    }
    return nil;
}

@interface IMIntegrityReportSummary ()
@property (nonatomic) NSInteger untrackedFileCount;
@property (nonatomic) NSInteger missingFileCount;
@property (nonatomic) NSInteger checksumMismatchCount;
@end

@implementation IMIntegrityReportSummary

+ (nullable instancetype)summaryWithResponseDictionary:(NSDictionary *)dictionary {
	if (![dictionary isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSNumber *untracked = IMIntegrityNonnegativeNumber(dictionary[IMIntegrityReportTypeUntrackedFile]);
	NSNumber *missing = IMIntegrityNonnegativeNumber(dictionary[IMIntegrityReportTypeMissingFile]);
	NSNumber *checksum = IMIntegrityNonnegativeNumber(dictionary[IMIntegrityReportTypeChecksumMismatch]);
	if (!untracked || !missing || !checksum) {
		return nil;
	}
	IMIntegrityReportSummary *summary = [[self alloc] init];
	summary.untrackedFileCount = untracked.integerValue;
	summary.missingFileCount = missing.integerValue;
	summary.checksumMismatchCount = checksum.integerValue;
	return summary;
}

@end
