#import <Foundation/Foundation.h>
#include <sys/cdefs.h>

#ifdef __OBJC__

NS_ASSUME_NONNULL_BEGIN

#define IM_PREFS_QUEUE "com.lns.immich-ios-14.prefs"

@interface IMPrefs : NSObject

+ (instancetype)shared;

- (nullable id)objectForKey:(NSString *)key;
- (void)setObject:(nullable id)value forKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (nullable NSString *)stringForKey:(NSString *)key;
- (void)setString:(nullable NSString *)value forKey:(NSString *)key;
- (BOOL)synchronize;

@property (nonatomic) BOOL wifiOnlyUpload; 
@property (nonatomic, copy) NSString *thumbnailQuality; 
@property (nonatomic) BOOL allowInsecureTLS; 

@end

NS_ASSUME_NONNULL_END

#endif /* __OBJC__ */

__BEGIN_DECLS

BOOL IMPrefsGetBool(const char *key);
void IMPrefsSetBool(const char *key, BOOL value);
BOOL IMPrefsSynchronize(void);

__END_DECLS
