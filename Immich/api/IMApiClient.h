#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const IMApiErrorDomain;

extern NSString *const IMApiErrorStatusCodeKey;

typedef void (^IMJSONHandler)(id _Nullable json, NSError *_Nullable error);
typedef void (^IMDataHandler)(NSData *_Nullable data, NSError *_Nullable error);
typedef void (^IMFileHandler)(NSURL *_Nullable fileURL, NSError *_Nullable error);

@interface IMMultipartBodyFile : NSObject
+ (nullable instancetype)bodyWithFields:(NSDictionary<NSString *, NSString *> *)fields
                              fileField:(NSString *)fileField
                               filename:(NSString *)filename
                                  error:(NSError **)error;
+ (void)removeStaleFiles;
@property (nonatomic, copy, readonly) NSURL *fileURL;
@property (nonatomic, copy, readonly) NSString *boundary;
@property (nonatomic, readonly) BOOL finished;
- (void)appendFileData:(NSData *)data;
- (BOOL)finishWithError:(NSError **)error;
- (void)discard;
@end

@interface IMApiClient : NSObject

+ (instancetype)shared;

+ (NSInteger)HTTPStatusForError:(nullable NSError *)error;

- (instancetype)initWithBaseURL:(NSURL *)baseURL;

@property (nonatomic, copy, nullable) NSString *overrideAPIKey;

@property (nonatomic) BOOL anonymous;

- (void)invalidate;

- (void)resetConnections;

- (NSURLSessionTask *)GET:(NSString *)path
                    query:(nullable NSDictionary<NSString *, NSString *> *)query
               completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)GET:(NSString *)path
               queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems
               completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)POST:(NSString *)path
                      body:(nullable id)body
                completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)POST:(NSString *)path
                queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems
                      body:(nullable id)body
                completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)POSTForm:(NSString *)path
                         fields:(NSDictionary<NSString *, NSString *> *)fields
                     completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)PUT:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion;
- (NSURLSessionTask *)PATCH:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion;
- (NSURLSessionTask *)DELETE:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)getData:(NSString *)path
                        query:(nullable NSDictionary<NSString *, NSString *> *)query
                   completion:(IMDataHandler)completion;

- (NSURLSessionTask *)downloadFile:(NSString *)path
                              query:(nullable NSDictionary<NSString *, NSString *> *)query
                     destinationURL:(NSURL *)destinationURL
                          completion:(IMFileHandler)completion;

- (NSURLSessionTask *)downloadFile:(NSString *)path
                             method:(NSString *)method
                              query:(nullable NSDictionary<NSString *, NSString *> *)query
                               body:(nullable id)body
                     destinationURL:(NSURL *)destinationURL
                          completion:(IMFileHandler)completion;

- (NSURLSessionTask *)multipartPOST:(NSString *)path
                             fields:(NSDictionary<NSString *, NSString *> *)fields
                          fileField:(NSString *)fileField
                           filename:(NSString *)filename
                           fileData:(NSData *)fileData
                         completion:(IMJSONHandler)completion;

- (NSURLSessionTask *)multipartPOST:(NSString *)path
                         queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems
                             fields:(NSDictionary<NSString *, NSString *> *)fields
                          fileField:(NSString *)fileField
                           filename:(NSString *)filename
                           fileData:(NSData *)fileData
                         completion:(IMJSONHandler)completion;

- (nullable NSURLSessionTask *)uploadMultipartBody:(IMMultipartBodyFile *)body
                                              path:(NSString *)path
                                        completion:(IMJSONHandler)completion;

@end

NS_ASSUME_NONNULL_END
