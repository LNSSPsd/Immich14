#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const IMApiErrorDomain;

typedef void (^IMJSONHandler)(id _Nullable json, NSError *_Nullable error);
typedef void (^IMDataHandler)(NSData *_Nullable data, NSError *_Nullable error);

@interface IMApiClient : NSObject

+ (instancetype)shared;

- (instancetype)initWithBaseURL:(NSURL *)baseURL;

- (NSURLSessionTask *)GET:(NSString *)path
                    query:(nullable NSDictionary<NSString *, NSString *> *)query
               completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)POST:(NSString *)path
                      body:(nullable id)body
                completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)PUT:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion;
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
