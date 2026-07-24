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

extern NSNotificationName const IMSessionDidChangeNotification; 

extern NSDate *_Nullable IMDateFromServerTimestamp(NSString *_Nullable raw);

#endif /* __OBJC__ */

#endif /* IMMICH_COMMON_H */
