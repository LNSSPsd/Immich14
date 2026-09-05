#import "IMQueue.h"

static id IMQueueValue(id value) { return [value isKindOfClass:[NSNull class]] ? nil : value; }

@interface IMQueue ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL paused;
@property (nonatomic) NSInteger active;
@property (nonatomic) NSInteger completed;
@property (nonatomic) NSInteger delayed;
@property (nonatomic) NSInteger failed;
@property (nonatomic) NSInteger waiting;
@property (nonatomic) NSInteger pausedCount;
@end

@implementation IMQueue

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
	self = [super init];
	if (self) {
		id value = IMQueueValue(dictionary[@"name"]);
		_name = [value isKindOfClass:[NSString class]] ? value : @"";
		value = IMQueueValue(dictionary[@"isPaused"]);
		_paused = [value isKindOfClass:[NSNumber class]] && [value boolValue];
		NSDictionary *statistics = [dictionary[@"statistics"] isKindOfClass:[NSDictionary class]] ? dictionary[@"statistics"] : @{};
		_active = [IMQueueValue(statistics[@"active"]) integerValue];
		_completed = [IMQueueValue(statistics[@"completed"]) integerValue];
		_delayed = [IMQueueValue(statistics[@"delayed"]) integerValue];
		_failed = [IMQueueValue(statistics[@"failed"]) integerValue];
		_waiting = [IMQueueValue(statistics[@"waiting"]) integerValue];
		_pausedCount = [IMQueueValue(statistics[@"paused"]) integerValue];
	}
	return self;
}

+ (NSArray<IMQueue *> *)queuesWithArray:(NSArray *)array {
	if (![array isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray<IMQueue *> *queues = [NSMutableArray arrayWithCapacity:array.count];
	for (id value in array) if ([value isKindOfClass:[NSDictionary class]]) [queues addObject:[[self alloc] initWithDictionary:value]];
	return queues;
}

@end
