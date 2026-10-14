#ifndef IMMICH_COMMON_H
#define IMMICH_COMMON_H

#include <TargetConditionals.h>

#ifndef _
#define _(s) (s)
#endif

#ifndef IM_TROLLSTORE
#define IM_TROLLSTORE 0
#endif

#ifndef APP_VERSION_STRING
#define APP_VERSION_STRING "0.0.0"
#endif
#ifndef APP_COMMIT_HASH
#define APP_COMMIT_HASH ""
#endif

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static inline BOOL IMJSONIsBoolean(id value) {
	return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

extern NSNotificationName const IMSessionDidChangeNotification; 

extern NSNotificationName const IMServerAssetsDidChangeNotification;
extern NSString *const IMChangedTimeBucketsUserInfoKey;

extern NSDate *_Nullable IMDateFromServerTimestamp(NSString *_Nullable raw);

extern NSInteger IMDurationMsFromJSONValue(id _Nullable value);

extern NSString *_Nullable IMTimeBucketKeyForDate(NSDate *_Nullable date);

#endif 

#endif 
