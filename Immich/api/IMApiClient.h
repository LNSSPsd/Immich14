#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const IMApiErrorDomain;

extern NSString *const IMApiErrorStatusCodeKey;

typedef void (^IMJSONHandler)(id _Nullable json, NSError *_Nullable error);
typedef void (^IMDataHandler)(NSData *_Nullable data, NSError *_Nullable error);

@interface IMApiClient : NSObject

+ (instancetype)shared;

+ (NSInteger)HTTPStatusForError:(nullable NSError *)error;

- (instancetype)initWithBaseURL:(NSURL *)baseURL;

@property (nonatomic, copy, nullable) NSString *overrideAPIKey;

- (void)invalidate;

- (void)resetConnections;

- (NSURLSessionTask *)GET:(NSString *)path
                    query:(nullable NSDictionary<NSString *, NSString *> *)query
               completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)POST:(NSString *)path
                      body:(nullable id)body
                completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)PUT:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion;
- (NSURLSessionTask *)PATCH:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion;
- (NSURLSessionTask *)DELETE:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)getData:(NSString *)path
                        query:(nullable NSDictionary<NSString *, NSString *> *)query
                   completion:(IMDataHandler)completion;

- (NSURLSessionTask *)multipartPOST:(NSString *)path
                             fields:(NSDictionary<NSString *, NSString *> *)fields
                          fileField:(NSString *)fileField
                           filename:(NSString *)filename
                           fileData:(NSData *)fileData
                         completion:(IMJSONHandler)completion;

@end

NS_ASSUME_NONNULL_END
