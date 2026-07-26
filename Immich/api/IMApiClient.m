#import "IMApiClient.h"
#import "IMSession.h"
#import "IMPrefs.h"
#import "common.h"

NSErrorDomain const IMApiErrorDomain = @"IMApiErrorDomain";
NSString *const IMApiErrorStatusCodeKey = @"statusCode";

typedef NS_ENUM(NSInteger, IMApiErrorCode) {
	IMApiErrorInvalidURL = 1,
	IMApiErrorDecoding = 2,
	IMApiErrorServer = 3,
};

@interface IMApiClient () <NSURLSessionDelegate>
@property (atomic, strong, nullable) NSURLSession *urlSession;
@property (nonatomic, copy, nullable) NSURL *fixedBaseURL; 
@property (nonatomic) BOOL usesSessionBaseURL;
@end

@implementation IMApiClient

+ (instancetype)shared {
	static IMApiClient *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMApiClient alloc] initInternal];
		shared.usesSessionBaseURL = YES;
	});
	return shared;
}

+ (NSInteger)HTTPStatusForError:(nullable NSError *)error {
	if (![error.domain isEqualToString:IMApiErrorDomain]) {
		return 0;
	}
	id status = error.userInfo[IMApiErrorStatusCodeKey];
	return [status respondsToSelector:@selector(integerValue)] ? [status integerValue] : 0;
}

- (NSURLSession *)makeURLSession {
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
	config.timeoutIntervalForRequest = 30;
	return [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
}

- (instancetype)initInternal {
	self = [super init];
	if (self) {
		_urlSession = [self makeURLSession];
	}
	return self;
}

- (void)invalidate {
	NSURLSession *session = self.urlSession;
	self.urlSession = nil; 
	[session finishTasksAndInvalidate];
}

- (void)resetConnections {
	NSURLSession *old = self.urlSession;
	self.urlSession = [self makeURLSession];
	[old finishTasksAndInvalidate];
}

- (instancetype)initWithBaseURL:(NSURL *)baseURL {
	self = [self initInternal];
	if (self) {
		_fixedBaseURL = baseURL;
		_usesSessionBaseURL = NO;
	}
	return self;
}

- (nullable NSURL *)effectiveBaseURL {
	return self.usesSessionBaseURL ? [IMSession shared].baseURL : self.fixedBaseURL;
}

#pragma mark - Request building

- (nullable NSURL *)URLForPath:(NSString *)path
                          query:(nullable NSDictionary<NSString *, NSString *> *)query {
	NSURL *base = [self effectiveBaseURL];
	if (!base) {
		return nil;
	}
	NSString *baseString = base.absoluteString;
	if ([baseString hasSuffix:@"/"]) {
		baseString = [baseString substringToIndex:baseString.length - 1];
	}
	if (![path hasPrefix:@"/"]) {
		path = [@"/" stringByAppendingString:path];
	}
	NSURL *full = [NSURL URLWithString:[baseString stringByAppendingString:path]];
	if (!full) {
		return nil;
	}
	if (!query.count) {
		return full;
	}
	NSURLComponents *components = [NSURLComponents componentsWithURL:full resolvingAgainstBaseURL:YES];
	NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
	[query enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		[items addObject:[NSURLQueryItem queryItemWithName:key value:value]];
	}];
	components.queryItems = items;
	return components.URL;
}

- (NSMutableURLRequest *)requestWithURL:(NSURL *)url method:(NSString *)method body:(nullable id)body {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = method;
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	NSString *apiKey = self.overrideAPIKey ?: [IMSession shared].apiKeyHeaderValue;
	if (apiKey) {
		[request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
	} else {
		NSString *auth = [IMSession shared].authorizationHeader;
		if (auth) {
			[request setValue:auth forHTTPHeaderField:@"Authorization"];
		}
	}
	if (body) {
		request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
		[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	}
	return request;
}

- (NSError *)invalidURLError {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:IMApiErrorInvalidURL
	                        userInfo:@{ NSLocalizedDescriptionKey: _(@"No server URL configured.") }];
}

- (void)failJSON:(IMJSONHandler)completion withError:(NSError *)error {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(nil, error);
	});
}

#pragma mark - JSON requests

- (NSURLSessionTask *)dataTaskWithRequest:(NSURLRequest *)request completion:(IMJSONHandler)completion {
	NSURLSessionDataTask *task =
	    [self.urlSession dataTaskWithRequest:request
	                        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
		    [self handleData:data response:response error:error completion:completion];
	    }];
	[task resume];
	return task;
}

- (void)handleData:(nullable NSData *)data
          response:(nullable NSURLResponse *)response
             error:(nullable NSError *)error
        completion:(IMJSONHandler)completion {
	if (error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(nil, error);
		});
		return;
	}

	NSInteger status = [(NSHTTPURLResponse *)response statusCode];
	id json = nil;
	if (data.length > 0) {
		json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	}

	if (status < 200 || status >= 300) {
		NSString *message = [self errorMessageFromJSON:json] ?: [NSHTTPURLResponse localizedStringForStatusCode:status];
		NSError *serverError = [NSError errorWithDomain:IMApiErrorDomain
		                                            code:IMApiErrorServer
		                                        userInfo:@{
			                                        NSLocalizedDescriptionKey: message,
			                                        IMApiErrorStatusCodeKey: @(status),
		                                        }];
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(nil, serverError);
		});
		return;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		completion(json, nil);
	});
}

- (nullable NSString *)errorMessageFromJSON:(nullable id)json {
	if (![json isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	id message = json[@"message"];
	if ([message isKindOfClass:[NSString class]]) {
		return message;
	}
	if ([message isKindOfClass:[NSArray class]] && [message firstObject]) {
		return [(NSArray *)message componentsJoinedByString:@", "];
	}
	return nil;
}

- (NSURLSessionTask *)GET:(NSString *)path
                    query:(nullable NSDictionary<NSString *, NSString *> *)query
               completion:(IMJSONHandler)completion {
	NSURL *url = [self URLForPath:path query:query];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"GET" body:nil] completion:completion];
}

- (NSURLSessionTask *)POST:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion {
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"POST" body:body] completion:completion];
}

- (NSURLSessionTask *)PUT:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion {
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"PUT" body:body] completion:completion];
}

- (NSURLSessionTask *)PATCH:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion {
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"PATCH" body:body] completion:completion];
}

- (NSURLSessionTask *)DELETE:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion {
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"DELETE" body:body] completion:completion];
}

#pragma mark - Raw data

- (NSURLSessionTask *)getData:(NSString *)path
                        query:(nullable NSDictionary<NSString *, NSString *> *)query
                   completion:(IMDataHandler)completion {
	NSURL *url = [self URLForPath:path query:query];
	if (!url) {
		NSError *urlError = [self invalidURLError];
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(nil, urlError);
		});
		return nil;
	}
	NSURLRequest *request = [self requestWithURL:url method:@"GET" body:nil];
	NSURLSessionDataTask *task =
	    [self.urlSession dataTaskWithRequest:request
	                        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
		    if (error) {
			    dispatch_async(dispatch_get_main_queue(), ^{
				    completion(nil, error);
			    });
			    return;
		    }
		    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
		    if (status < 200 || status >= 300) {
			    NSError *serverError = [NSError errorWithDomain:IMApiErrorDomain
			                                                code:IMApiErrorServer
			                                            userInfo:@{
				                                            NSLocalizedDescriptionKey: [NSHTTPURLResponse localizedStringForStatusCode:status],
				                                            IMApiErrorStatusCodeKey: @(status),
			                                            }];
			    dispatch_async(dispatch_get_main_queue(), ^{
				    completion(nil, serverError);
			    });
			    return;
		    }
		    dispatch_async(dispatch_get_main_queue(), ^{
			    completion(data, nil);
		    });
	    }];
	[task resume];
	return task;
}

#pragma mark - Multipart

static NSString *IMMultipartQuote(NSString *value) {
	NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
	escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
	escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
	escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
	return escaped;
}

- (NSURLSessionTask *)multipartPOST:(NSString *)path
                             fields:(NSDictionary<NSString *, NSString *> *)fields
                          fileField:(NSString *)fileField
                           filename:(NSString *)filename
                           fileData:(NSData *)fileData
                         completion:(IMJSONHandler)completion {
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}

	NSString *boundary = [NSString stringWithFormat:@"IMBoundary-%@", [NSUUID UUID].UUIDString];
	NSMutableURLRequest *request = [self requestWithURL:url method:@"POST" body:nil];
	[request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
	    forHTTPHeaderField:@"Content-Type"];

	NSMutableData *body = [NSMutableData data];
	NSData *dashBoundary = [[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding];

	[fields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		[body appendData:dashBoundary];
		[body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", IMMultipartQuote(key)]
		              dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	}];

	[body appendData:dashBoundary];
	[body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n",
	                                              IMMultipartQuote(fileField), IMMultipartQuote(filename)] dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:fileData];
	[body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

	NSURLSessionUploadTask *task = [self.urlSession uploadTaskWithRequest:request
	                                                                fromData:body
	                                                        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
		    [self handleData:data response:response error:error completion:completion];
	    }];
	[task resume];
	return task;
}

#pragma mark - TLS

- (void)URLSession:(NSURLSession *)session
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *_Nullable credential))completionHandler {
	if (![challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust] ||
	    !IMPrefs.shared.allowInsecureTLS) {
		completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
		return;
	}
	NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
	completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

@end
