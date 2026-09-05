#import <UIKit/UIKit.h>
#import "IMUser.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^IMOAuthLoginCompletion)(BOOL success, NSError *_Nullable error);
typedef void (^IMOAuthLinkCompletion)(IMUser *_Nullable user, NSError *_Nullable error);

/**
 * Owns one OAuth browser transaction at a time.  The coordinator keeps the
 * PKCE verifier and state in memory, validates the callback scheme/path/state,
 * and then delegates token exchange to IMOAuthApi.
 */
@interface IMOAuthCoordinator : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly, getter=isActive) BOOL active;

- (BOOL)startLoginFromViewController:(UIViewController *)presentingViewController
                             baseURL:(NSURL *)baseURL
                          completion:(IMOAuthLoginCompletion)completion;

- (BOOL)startLinkFromViewController:(UIViewController *)presentingViewController
                          completion:(IMOAuthLinkCompletion)completion;

- (BOOL)handleCallbackURL:(NSURL *)url;

- (void)cancel;

@end

NS_ASSUME_NONNULL_END
