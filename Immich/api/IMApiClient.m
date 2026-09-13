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

- (nullable NSURL *)URLForPath:(NSString *)path
	                  queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems {
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
	if (queryItems.count == 0) {
		return full;
	}
	NSURLComponents *components = [NSURLComponents componentsWithURL:full resolvingAgainstBaseURL:YES];
	components.queryItems = queryItems;
	return components.URL;
}

- (NSMutableURLRequest *)requestWithURL:(NSURL *)url method:(NSString *)method body:(nullable id)body {
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = method;
	[request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

	if (!self.anonymous) {
		NSString *apiKey = self.overrideAPIKey ?: [IMSession shared].apiKeyHeaderValue;
		if (apiKey) {
			[request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
		} else {
			NSString *auth = [IMSession shared].authorizationHeader;
			if (auth) {
				[request setValue:auth forHTTPHeaderField:@"Authorization"];
			}
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

- (NSError *)invalidJSONBodyError {
	return [NSError errorWithDomain:IMApiErrorDomain
	                            code:IMApiErrorDecoding
	                        userInfo:@{ NSLocalizedDescriptionKey: _(@"The request body contains unsupported values.") }];
}

- (void)failJSON:(IMJSONHandler)completion withError:(NSError *)error {
	dispatch_async(dispatch_get_main_queue(), ^{
		completion(nil, error);
	});
}

#pragma mark - JSON requests

- (NSURLSessionTask *)dataTaskWithRequest:(NSURLRequest *)request completion:(IMJSONHandler)completion {
	NSURLSession *session = self.urlSession;
	if (!session) {
		[self failJSON:completion withError:[NSError errorWithDomain:IMApiErrorDomain
		                                                   code:IMApiErrorInvalidURL
		                                               userInfo:@{NSLocalizedDescriptionKey: _(@"The network client is no longer available.")}]];
		return nil;
	}
	NSURLSessionDataTask *task =
	    [session dataTaskWithRequest:request
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
	NSError *decodingError = nil;
	if (data.length > 0) {
		json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&decodingError];
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
	if (decodingError != nil) {
		NSError *apiError = [NSError errorWithDomain:IMApiErrorDomain
	                                             code:IMApiErrorDecoding
	                                         userInfo:@{
			                                     NSLocalizedDescriptionKey: _(@"The server returned invalid JSON."),
			                                     NSUnderlyingErrorKey: decodingError,
	                                         }];
		dispatch_async(dispatch_get_main_queue(), ^{
			completion(nil, apiError);
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

- (NSURLSessionTask *)GET:(NSString *)path
	               queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems
	               completion:(IMJSONHandler)completion {
	NSURL *url = [self URLForPath:path queryItems:queryItems];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"GET" body:nil] completion:completion];
}

- (NSURLSessionTask *)POST:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion {
	if (body && ![NSJSONSerialization isValidJSONObject:body]) {
		[self failJSON:completion withError:[self invalidJSONBodyError]];
		return nil;
	}
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"POST" body:body] completion:completion];
}

- (NSURLSessionTask *)POST:(NSString *)path
	                queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems
	                      body:(nullable id)body
	                completion:(IMJSONHandler)completion {
	if (body && ![NSJSONSerialization isValidJSONObject:body]) {
		[self failJSON:completion withError:[self invalidJSONBodyError]];
		return nil;
	}
	NSURL *url = [self URLForPath:path queryItems:queryItems];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"POST" body:body] completion:completion];
}

- (NSURLSessionTask *)POSTForm:(NSString *)path
                         fields:(NSDictionary<NSString *, NSString *> *)fields
                     completion:(IMJSONHandler)completion {
	if (![fields isKindOfClass:[NSDictionary class]]) {
		[self failJSON:completion withError:[NSError errorWithDomain:IMApiErrorDomain
		                                                   code:IMApiErrorDecoding
		                                               userInfo:@{NSLocalizedDescriptionKey: _(@"Form fields are invalid.")}]];
		return nil;
	}
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithCapacity:fields.count];
	for (id rawKey in fields) {
		if (![rawKey isKindOfClass:[NSString class]] || [(NSString *)rawKey length] == 0 ||
		    [(NSString *)rawKey rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) {
			[self failJSON:completion withError:[NSError errorWithDomain:IMApiErrorDomain
			                                                   code:IMApiErrorDecoding
			                                               userInfo:@{NSLocalizedDescriptionKey: _(@"Form fields are invalid.")}]];
			return nil;
		}
		id rawValue = fields[rawKey];
		if (![rawValue isKindOfClass:[NSString class]] ||
		    [(NSString *)rawValue rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) {
			[self failJSON:completion withError:[NSError errorWithDomain:IMApiErrorDomain
			                                                   code:IMApiErrorDecoding
			                                               userInfo:@{NSLocalizedDescriptionKey: _(@"Form fields are invalid.")}]];
			return nil;
		}
		[items addObject:[NSURLQueryItem queryItemWithName:rawKey value:rawValue]];
	}
	NSMutableString *encoded = [NSMutableString string];
	for (NSURLQueryItem *item in items) {
		if (encoded.length > 0) [encoded appendString:@"&"];
		NSString *name = item.name ?: @"";
		NSString *value = item.value ?: @"";
		NSURLComponents *one = [[NSURLComponents alloc] init];
		one.queryItems = @[ [NSURLQueryItem queryItemWithName:name value:value] ];
		NSString *query = one.percentEncodedQuery ?: @"";
		[encoded appendString:query];
	}
	NSMutableURLRequest *request = [self requestWithURL:url method:@"POST" body:nil];
	request.HTTPBody = [encoded dataUsingEncoding:NSUTF8StringEncoding];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
	return [self dataTaskWithRequest:request completion:completion];
}

- (NSURLSessionTask *)PUT:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion {
	if (body && ![NSJSONSerialization isValidJSONObject:body]) {
		[self failJSON:completion withError:[self invalidJSONBodyError]];
		return nil;
	}
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"PUT" body:body] completion:completion];
}

- (NSURLSessionTask *)PATCH:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion {
	if (body && ![NSJSONSerialization isValidJSONObject:body]) {
		[self failJSON:completion withError:[self invalidJSONBodyError]];
		return nil;
	}
	NSURL *url = [self URLForPath:path query:nil];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}
	return [self dataTaskWithRequest:[self requestWithURL:url method:@"PATCH" body:body] completion:completion];
}

- (NSURLSessionTask *)DELETE:(NSString *)path body:(nullable id)body completion:(IMJSONHandler)completion {
	if (body && ![NSJSONSerialization isValidJSONObject:body]) {
		[self failJSON:completion withError:[self invalidJSONBodyError]];
		return nil;
	}
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
	NSURLSession *session = self.urlSession;
	if (!session) {
		NSError *clientError = [NSError errorWithDomain:IMApiErrorDomain
		                                            code:IMApiErrorInvalidURL
		                                        userInfo:@{NSLocalizedDescriptionKey: _(@"The network client is no longer available.")}];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, clientError); });
		return nil;
	}
	NSURLSessionDataTask *task =
	    [session dataTaskWithRequest:request
	                        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
		    if (error) {
			    dispatch_async(dispatch_get_main_queue(), ^{
				    completion(nil, error);
			    });
			    return;
		    }
		    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
		    if (status < 200 || status >= 300) {
			    id json = nil;
			    if (data.length > 0 && data.length <= 64 * 1024) {
				    json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
			    }
			    NSString *message = [self errorMessageFromJSON:json] ?: [NSHTTPURLResponse localizedStringForStatusCode:status];
			    NSError *serverError = [NSError errorWithDomain:IMApiErrorDomain
			                                                code:IMApiErrorServer
			                                            userInfo:@{
				                                            NSLocalizedDescriptionKey: message ?: _(@"The server rejected the media request."),
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

- (NSURLSessionTask *)downloadFile:(NSString *)path
	                          query:(nullable NSDictionary<NSString *, NSString *> *)query
	                 destinationURL:(NSURL *)destinationURL
	                      completion:(IMFileHandler)completion {
	return [self downloadFile:path
	                    method:@"GET"
	                     query:query
	                      body:nil
	            destinationURL:destinationURL
	                 completion:completion];
}

- (NSURLSessionTask *)downloadFile:(NSString *)path
	                         method:(NSString *)method
	                          query:(nullable NSDictionary<NSString *, NSString *> *)query
	                           body:(nullable id)body
	                 destinationURL:(NSURL *)destinationURL
	                      completion:(IMFileHandler)completion {
	if (![destinationURL isKindOfClass:[NSURL class]] || !destinationURL.isFileURL || destinationURL.path.length == 0) {
		NSError *error = [NSError errorWithDomain:IMApiErrorDomain
	                                      code:IMApiErrorInvalidURL
	                                  userInfo:@{NSLocalizedDescriptionKey: _(@"A local destination file is required.")}];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	if (![method isKindOfClass:[NSString class]] || method.length == 0 ||
	    [method rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n"]].location != NSNotFound) {
		NSError *error = [NSError errorWithDomain:IMApiErrorDomain
	                                      code:IMApiErrorInvalidURL
	                                  userInfo:@{NSLocalizedDescriptionKey: _(@"A valid download method is required.")}];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	if (body && ![NSJSONSerialization isValidJSONObject:body]) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [self invalidJSONBodyError]); });
		return nil;
	}
	NSURL *url = [self URLForPath:path query:query];
	if (!url) {
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, [self invalidURLError]); });
		return nil;
	}
	NSURLSession *session = self.urlSession;
	if (!session) {
		NSError *error = [NSError errorWithDomain:IMApiErrorDomain
		                                      code:IMApiErrorInvalidURL
		                                  userInfo:@{NSLocalizedDescriptionKey: _(@"The network client is no longer available.")}];
		dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
		return nil;
	}
	NSMutableURLRequest *request = [self requestWithURL:url method:method body:body];
	[request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
	NSURL *destination = [destinationURL copy];
	NSURLSessionDownloadTask *task = [session downloadTaskWithRequest:request
	                                                completionHandler:^(NSURL *_Nullable location,
	                                                                      NSURLResponse *_Nullable response,
	                                                                      NSError *_Nullable error) {
			NSError *resultError = error;
			NSInteger status = [(NSHTTPURLResponse *)response statusCode];
			if (!resultError && (status < 200 || status >= 300)) {
				NSData *errorBody = nil;
				if (location) {
					NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:location.path error:NULL];
					NSNumber *lengthNumber = attrs[NSFileSize];
					if ([lengthNumber isKindOfClass:[NSNumber class]] && lengthNumber.unsignedLongLongValue <= 64 * 1024) {
						errorBody = [NSData dataWithContentsOfURL:location options:0 error:NULL];
					}
				}
				id json = errorBody.length ? [NSJSONSerialization JSONObjectWithData:errorBody options:0 error:NULL] : nil;
				NSString *message = [self errorMessageFromJSON:json] ?: [NSHTTPURLResponse localizedStringForStatusCode:status];
				resultError = [NSError errorWithDomain:IMApiErrorDomain
				                                  code:IMApiErrorServer
				                              userInfo:@{NSLocalizedDescriptionKey: message ?: _(@"The server rejected the download."),
				                                         IMApiErrorStatusCodeKey: @(status)}];
			}
			if (!resultError && !location) {
				resultError = [NSError errorWithDomain:IMApiErrorDomain
				                                  code:IMApiErrorDecoding
				                              userInfo:@{NSLocalizedDescriptionKey: _(@"The server returned no file.")}];
			}
			if (!resultError) {
				NSFileManager *manager = [NSFileManager defaultManager];
				NSString *parent = destination.URLByDeletingLastPathComponent.path;
				BOOL prepared = parent.length == 0 || [manager createDirectoryAtPath:parent
				                                          withIntermediateDirectories:YES
				                                                           attributes:nil
				                                                                error:NULL];
				if (!prepared) {
					resultError = [NSError errorWithDomain:IMApiErrorDomain
				                                  code:IMApiErrorDecoding
				                              userInfo:@{NSLocalizedDescriptionKey: _(@"The downloaded file could not be prepared.")}];
				} else {
					NSString *stagingName = [NSString stringWithFormat:@".%@.%@.part",
					                         destination.lastPathComponent ?: @"download",
					                         [NSUUID UUID].UUIDString];
					NSURL *staging = [NSURL fileURLWithPath:[parent stringByAppendingPathComponent:stagingName]];
					[manager removeItemAtURL:staging error:NULL];
					BOOL staged = [manager moveItemAtURL:location toURL:staging error:&resultError];
					if (!staged) {
						resultError = nil;
						staged = [manager copyItemAtURL:location toURL:staging error:&resultError];
						if (staged) [manager removeItemAtURL:location error:NULL];
					}
					if (staged) {
						BOOL destinationExists = [manager fileExistsAtPath:destination.path];
						if (destinationExists) {
								staged = [manager replaceItemAtURL:destination
							                       withItemAtURL:staging
							                      backupItemName:nil
							                             options:NSFileManagerItemReplacementUsingNewMetadataOnly
							                               resultingItemURL:NULL
							                               error:&resultError];
						} else {
							staged = [manager moveItemAtURL:staging toURL:destination error:&resultError];
						}
						if (!staged) [manager removeItemAtURL:staging error:NULL];
					}
				}
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(resultError ? nil : destination, resultError);
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

static NSData *IMMultipartHead(NSString *boundary, NSDictionary<NSString *, NSString *> *fields,
                               NSString *fileField, NSString *filename) {
	NSMutableData *head = [NSMutableData data];
	NSData *dashBoundary = [[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding];
	[fields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		[head appendData:dashBoundary];
		[head appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", IMMultipartQuote(key)]
		              dataUsingEncoding:NSUTF8StringEncoding]];
		[head appendData:[value dataUsingEncoding:NSUTF8StringEncoding]];
		[head appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	}];
	[head appendData:dashBoundary];
	[head appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n",
	                                              IMMultipartQuote(fileField), IMMultipartQuote(filename)] dataUsingEncoding:NSUTF8StringEncoding]];
	[head appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	return head;
}

static NSData *IMMultipartTail(NSString *boundary) {
	return [[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSURLSessionTask *)multipartPOST:(NSString *)path
                             fields:(NSDictionary<NSString *, NSString *> *)fields
                          fileField:(NSString *)fileField
                           filename:(NSString *)filename
                           fileData:(NSData *)fileData
                         completion:(IMJSONHandler)completion {
	return [self multipartPOST:path
	                queryItems:nil
	                    fields:fields
	                 fileField:fileField
	                  filename:filename
	                  fileData:fileData
	                completion:completion];
}

- (NSURLSessionTask *)multipartPOST:(NSString *)path
                         queryItems:(nullable NSArray<NSURLQueryItem *> *)queryItems
                             fields:(NSDictionary<NSString *, NSString *> *)fields
                          fileField:(NSString *)fileField
                           filename:(NSString *)filename
                           fileData:(NSData *)fileData
                         completion:(IMJSONHandler)completion {
	NSURL *url = [self URLForPath:path queryItems:queryItems];
	if (!url) {
		[self failJSON:completion withError:[self invalidURLError]];
		return nil;
	}

	NSString *boundary = [NSString stringWithFormat:@"IMBoundary-%@", [NSUUID UUID].UUIDString];
	NSMutableURLRequest *request = [self requestWithURL:url method:@"POST" body:nil];
	NSURLSession *session = self.urlSession;
	if (!session) {
		[self failJSON:completion withError:[NSError errorWithDomain:IMApiErrorDomain
		                                                   code:IMApiErrorInvalidURL
		                                               userInfo:@{NSLocalizedDescriptionKey: _(@"The network client is no longer available.")}]];
		return nil;
	}
	[request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
	    forHTTPHeaderField:@"Content-Type"];

	NSMutableData *body = [IMMultipartHead(boundary, fields, fileField, filename) mutableCopy];
	[body appendData:fileData];
	[body appendData:IMMultipartTail(boundary)];

	NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request
	                                                                fromData:body
	                                                        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
		    [self handleData:data response:response error:error completion:completion];
	    }];
	[task resume];
	return task;
}

- (nullable NSURLSessionTask *)uploadMultipartBody:(IMMultipartBodyFile *)body
                                              path:(NSString *)path
                                        completion:(IMJSONHandler)completion {
	NSURL *fileURL = body.fileURL;
	NSURL *url = [self URLForPath:path queryItems:nil];
	NSURLSession *session = self.urlSession;
	if (!body.finished || !url || !session) {
		[body discard];
		[self failJSON:completion withError:!url ? [self invalidURLError] : [NSError errorWithDomain:IMApiErrorDomain
		                                                                                       code:IMApiErrorInvalidURL
		                                                                                   userInfo:@{NSLocalizedDescriptionKey: _(@"The upload could not be prepared.")}]];
		return nil;
	}
	NSMutableURLRequest *request = [self requestWithURL:url method:@"POST" body:nil];
	[request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", body.boundary]
	    forHTTPHeaderField:@"Content-Type"];
	NSURLSessionUploadTask *task = [session uploadTaskWithRequest:request
	                                                     fromFile:fileURL
	                                            completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
		    [[NSFileManager defaultManager] removeItemAtURL:fileURL error:NULL];
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

#pragma mark - IMMultipartBodyFile

static NSString *IMMultipartBodyDirectory(void) {
	return [NSTemporaryDirectory() stringByAppendingPathComponent:@"IMUpload"];
}

@interface IMMultipartBodyFile ()
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, copy) NSString *boundary;
@property (nonatomic, strong, nullable) NSFileHandle *handle;
@property (nonatomic, strong, nullable) NSError *writeError;
@property (nonatomic) BOOL finished;
@end

@implementation IMMultipartBodyFile

+ (nullable instancetype)bodyWithFields:(NSDictionary<NSString *, NSString *> *)fields
                              fileField:(NSString *)fileField
                               filename:(NSString *)filename
                                  error:(NSError **)error {
	NSFileManager *manager = [NSFileManager defaultManager];
	if (![manager createDirectoryAtPath:IMMultipartBodyDirectory() withIntermediateDirectories:YES attributes:nil error:error]) {
		return nil;
	}
	IMMultipartBodyFile *body = [[self alloc] init];
	body.boundary = [NSString stringWithFormat:@"IMBoundary-%@", [NSUUID UUID].UUIDString];
	NSString *name = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"multipart"];
	body.fileURL = [NSURL fileURLWithPath:[IMMultipartBodyDirectory() stringByAppendingPathComponent:name]];
	if (![manager createFileAtPath:body.fileURL.path contents:IMMultipartHead(body.boundary, fields, fileField, filename) attributes:nil]) {
		if (error) {
			*error = [NSError errorWithDomain:IMApiErrorDomain
			                             code:IMApiErrorInvalidURL
			                         userInfo:@{NSLocalizedDescriptionKey: _(@"The upload file could not be created.")}];
		}
		return nil;
	}
	body.handle = [NSFileHandle fileHandleForWritingToURL:body.fileURL error:error];
	if (!body.handle || ![body.handle seekToEndReturningOffset:NULL error:error]) {
		[body discard];
		return nil;
	}
	return body;
}

+ (void)removeStaleFiles {
	NSFileManager *manager = [NSFileManager defaultManager];
	NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-6 * 60 * 60];
	for (NSString *name in [manager contentsOfDirectoryAtPath:IMMultipartBodyDirectory() error:NULL]) {
		NSString *path = [IMMultipartBodyDirectory() stringByAppendingPathComponent:name];
		NSDate *modified = [manager attributesOfItemAtPath:path error:NULL][NSFileModificationDate];
		if (modified && [modified compare:cutoff] == NSOrderedAscending) {
			[manager removeItemAtPath:path error:NULL];
		}
	}
}

- (void)appendFileData:(NSData *)data {
	if (self.writeError || !self.handle || data.length == 0) {
		return;
	}
	NSError *error = nil;
	if (![self.handle writeData:data error:&error]) {
		self.writeError = error ?: [NSError errorWithDomain:IMApiErrorDomain
		                                               code:IMApiErrorInvalidURL
		                                           userInfo:@{NSLocalizedDescriptionKey: _(@"The upload file could not be written.")}];
	}
}

- (BOOL)finishWithError:(NSError **)error {
	if (!self.writeError && self.handle) {
		[self appendFileData:IMMultipartTail(self.boundary)];
	}
	NSError *closeError = nil;
	BOOL closed = !self.handle || [self.handle closeAndReturnError:&closeError];
	self.handle = nil;
	if (self.writeError || !closed) {
		if (error) *error = self.writeError ?: closeError;
		return NO;
	}
	self.finished = YES;
	return YES;
}

- (void)discard {
	[self.handle closeAndReturnError:NULL];
	self.handle = nil;
	[[NSFileManager defaultManager] removeItemAtURL:self.fileURL error:NULL];
}

@end
