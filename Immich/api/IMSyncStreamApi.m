#import "IMSyncStreamApi.h"
#import "IMApiClient.h"
#import "IMSession.h"
#import "IMPrefs.h"
#import "common.h"

@interface IMSyncStreamApi () <NSURLSessionDataDelegate>
@property (nonatomic, strong, nullable) NSURLSession *urlSession;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *streamTask;
@property (nonatomic) BOOL polling;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSUInteger streamGeneration;
@property (nonatomic, copy, nullable) NSString *sessionFingerprint;

@property (nonatomic, strong) NSMutableData *lineBuffer;
@property (nonatomic, strong) NSMutableSet<NSString *> *changedBuckets;
@property (nonatomic) BOOL sawDeletes;
@property (nonatomic) BOOL needsReset;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *acksByType;
@property (nonatomic) BOOL bootstrapping;
@property (nonatomic, copy, nullable) void (^completion)(NSSet<NSString *> *_Nullable, BOOL, NSError *_Nullable);
@end

@implementation IMSyncStreamApi

static NSString *IMSyncSessionFingerprint(void) {
	IMSession *session = IMSession.shared;
	if (!session.isLoggedIn || session.baseURL.absoluteString.length == 0 || session.accessToken.length == 0) {
		return nil;
	}
	return [@[ session.baseURL.absoluteString,
	           session.userId ?: @"",
	           @(session.authKind),
	           session.accessToken ] componentsJoinedByString:@"\n"];
}

static BOOL IMSyncUUIDv4String(id value) {
	if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] != 36) return NO;
	NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
	if (!uuid) return NO;
	NSString *canonical = uuid.UUIDString.lowercaseString;
	NSString *raw = [(NSString *)value lowercaseString];
	return [raw isEqualToString:canonical] && [canonical characterAtIndex:14] == '4' &&
	       ([canonical characterAtIndex:19] == '8' || [canonical characterAtIndex:19] == '9' ||
	        [canonical characterAtIndex:19] == 'a' || [canonical characterAtIndex:19] == 'b');
}

- (instancetype)init {
	self = [super init];
	if (self) {
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                          selector:@selector(sessionDidChange:)
		                                              name:IMSessionDidChangeNotification
		                                            object:nil];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)shared {
	static IMSyncStreamApi *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMSyncStreamApi alloc] init];
	});
	return shared;
}

- (NSURLSession *)streamSession {
	if (!self.urlSession) {
		NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
		config.timeoutIntervalForRequest = 60;    
		config.timeoutIntervalForResource = 3600; 
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		queue.maxConcurrentOperationCount = 1;
		self.urlSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
	}
	return self.urlSession;
}

- (void)pollAssetChangesWithCompletion:(void (^)(NSSet<NSString *> *_Nullable changedBuckets,
                                                  BOOL sawDeletes,
                                                  NSError *_Nullable error))completion {
	if (self.polling || !IMSession.shared.isLoggedIn) {
		return;
	}
	NSString *fingerprint = IMSyncSessionFingerprint();
	if (fingerprint.length == 0) {
		return;
	}
	NSUInteger generation = ++self.generation;
	self.polling = YES;

	__weak typeof(self) weakSelf = self;
	[[IMApiClient shared] GET:@"/sync/ack" query:nil completion:^(id _Nullable json, NSError *_Nullable error) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) {
			return;
		}
		if (generation != strongSelf.generation ||
		    ![fingerprint isEqualToString:IMSyncSessionFingerprint()]) {
			if (generation == strongSelf.generation) strongSelf.polling = NO;
			return;
		}
		if (error || ![json isKindOfClass:[NSArray class]]) {
			strongSelf.polling = NO;
			completion(nil, NO, error ?: [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:nil]);
			return;
		}
		[strongSelf openStreamBootstrapping:(((NSArray *)json).count == 0)
		                  sessionFingerprint:fingerprint
		                         generation:generation
		                         completion:completion];
	}];
}

- (void)openStreamBootstrapping:(BOOL)bootstrapping
               sessionFingerprint:(NSString *)fingerprint
                      generation:(NSUInteger)generation
                     completion:(void (^)(NSSet<NSString *> *_Nullable, BOOL, NSError *_Nullable))completion {
	if (generation != self.generation || ![fingerprint isEqualToString:IMSyncSessionFingerprint()]) {
		self.polling = NO;
		return;
	}
	NSURL *url = [IMSession.shared.baseURL URLByAppendingPathComponent:@"sync/stream"];
	if (!url) {
		self.polling = NO;
		completion(nil, NO, [NSError errorWithDomain:IMApiErrorDomain code:0 userInfo:nil]);
		return;
	}

	self.lineBuffer = [NSMutableData data];
	self.changedBuckets = [NSMutableSet set];
	self.sawDeletes = NO;
	self.needsReset = NO;
	self.acksByType = [NSMutableDictionary dictionary];
	self.bootstrapping = bootstrapping;
	self.streamGeneration = generation;
	self.sessionFingerprint = [fingerprint copy];
	self.completion = completion;

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"POST";
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	NSString *apiKey = [IMSession.shared apiKeyHeaderValue];
	NSString *bearer = [IMSession.shared authorizationHeader];
	if (apiKey) {
		[request setValue:apiKey forHTTPHeaderField:@"x-api-key"];
	} else if (bearer) {
		[request setValue:bearer forHTTPHeaderField:@"Authorization"];
	}
	request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"types": @[ @"AssetsV2" ] }
	                                                    options:0
	                                                      error:NULL];

	self.streamTask = [[self streamSession] dataTaskWithRequest:request];
	[self.streamTask resume];
}

#pragma mark - Line reduction (delegate queue)

- (void)consumeLine:(NSData *)lineData {
	if (lineData.length == 0) {
		return;
	}
	NSDictionary *event = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:NULL];
	if (![event isKindOfClass:[NSDictionary class]]) {
		self.needsReset = YES;
		return;
	}
	NSString *ack = event[@"ack"];
	if ([ack isKindOfClass:[NSString class]] && ack.length > 0) {
		NSString *ackType = [[ack componentsSeparatedByString:@"|"] firstObject];
		if (ackType.length > 0) self.acksByType[ackType] = ack;
	}
	NSString *type = event[@"type"];
	if (![type isKindOfClass:[NSString class]]) {
		self.needsReset = YES;
		return;
	}

	if ([type isEqualToString:@"SyncResetV1"]) {
		self.needsReset = YES;
		return;
	}
	if ([type isEqualToString:@"SyncAckV1"] || [type isEqualToString:@"SyncCompleteV1"]) {
		return; 
	}
	if ([type isEqualToString:@"AssetDeleteV1"] || [type rangeOfString:@"Delete"].location != NSNotFound) {
		self.sawDeletes = YES;
		return;
	}
	if (![type isEqualToString:@"AssetV2"]) {
		if ([type hasPrefix:@"Asset"]) self.needsReset = YES;
		return;
	}

	NSDictionary *data = event[@"data"];
	if (![data isKindOfClass:[NSDictionary class]]) {
		self.needsReset = YES;
		return;
	}
	if (!IMSyncUUIDv4String(data[@"id"])) {
		self.needsReset = YES;
		return;
	}
	id fileCreatedAt = data[@"fileCreatedAt"];
	if (fileCreatedAt && fileCreatedAt != [NSNull null] && ![fileCreatedAt isKindOfClass:[NSString class]]) {
		self.needsReset = YES;
		return;
	}
	if ([fileCreatedAt isKindOfClass:[NSString class]] && !IMDateFromServerTimestamp(fileCreatedAt)) {
		self.needsReset = YES;
		return;
	}
	NSString *bucket = [fileCreatedAt isKindOfClass:[NSString class]]
	    ? IMTimeBucketKeyForDate(IMDateFromServerTimestamp(fileCreatedAt))
	    : nil;
	if (bucket) {
		[self.changedBuckets addObject:bucket];
	} else {
		self.sawDeletes = YES; 
	}
}

- (void)drainBuffer:(BOOL)final {
	while (YES) {
		const char *bytes = self.lineBuffer.bytes;
		NSUInteger length = self.lineBuffer.length;
		NSUInteger newline = NSNotFound;
		for (NSUInteger i = 0; i < length; i++) {
			if (bytes[i] == '\n') {
				newline = i;
				break;
			}
		}
		if (newline == NSNotFound) {
			break;
		}
		[self consumeLine:[self.lineBuffer subdataWithRange:NSMakeRange(0, newline)]];
		[self.lineBuffer replaceBytesInRange:NSMakeRange(0, newline + 1) withBytes:NULL length:0];
	}
	if (final && self.lineBuffer.length > 0) {
		[self consumeLine:self.lineBuffer];
		self.lineBuffer = [NSMutableData data];
	}
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
	if (dataTask != self.streamTask || self.streamGeneration != self.generation) return;
	[self.lineBuffer appendData:data];
	[self drainBuffer:NO];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
	if (task != self.streamTask || self.streamGeneration != self.generation) return;
	[self drainBuffer:YES];

	NSInteger status = 0;
	if ([task.response isKindOfClass:[NSHTTPURLResponse class]]) {
		status = ((NSHTTPURLResponse *)task.response).statusCode;
	}
	if (!error && (status < 200 || status >= 300)) {
		error = [NSError errorWithDomain:IMApiErrorDomain
		                             code:1
		                         userInfo:@{ IMApiErrorStatusCodeKey: @(status) }];
	}

	NSSet<NSString *> *changed = error ? nil
	    : (self.bootstrapping ? [NSSet set] : [self.changedBuckets copy]);
	BOOL deletes = error ? NO : (!self.bootstrapping && (self.sawDeletes || self.needsReset));
	NSArray<NSString *> *acks = error ? @[] : [self.acksByType.allValues sortedArrayUsingSelector:@selector(compare:)];
	BOOL reset = self.needsReset;
	NSUInteger generation = self.streamGeneration;
	NSString *fingerprint = [self.sessionFingerprint copy];
	void (^completion)(NSSet<NSString *> *_Nullable, BOOL, NSError *_Nullable) = self.completion;
	self.completion = nil;
	self.streamTask = nil;
	self.lineBuffer = [NSMutableData data];
	self.acksByType = nil;

	dispatch_async(dispatch_get_main_queue(), ^{
		if (generation != self.generation || ![fingerprint isEqualToString:IMSyncSessionFingerprint()]) {
			self.polling = NO;
			return;
		}
		if (!error) {
			if (reset) {
				[[IMApiClient shared] DELETE:@"/sync/ack" body:@{} completion:^(id _Nullable json, NSError *_Nullable ackError) {}];
			} else if (acks.count > 0) {
				[[IMApiClient shared] POST:@"/sync/ack" body:@{ @"acks": acks } completion:^(id _Nullable json, NSError *_Nullable ackError) {
					if (ackError) {
						NSLog(@"IMSyncStreamApi: ack failed: %@", ackError);
					}
				}];
			}
		}
		self.polling = NO;
		if (completion) {
			completion(changed, deletes, error);
		}
	});
}

- (void)sessionDidChange:(NSNotification *)notification {
	(void)notification;
	self.generation += 1;
	self.polling = NO;
	self.completion = nil;
	self.sessionFingerprint = nil;
	self.streamTask = nil;
	self.lineBuffer = [NSMutableData data];
	self.acksByType = nil;
	NSURLSession *session = self.urlSession;
	self.urlSession = nil;
	[session invalidateAndCancel];
}

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
