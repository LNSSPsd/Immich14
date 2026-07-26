#import "IMDatabase.h"
#import <sqlite3.h>

NSNotificationName const IMSyncStateDidChangeNotification = @"IMSyncStateDidChangeNotification";

@interface IMDatabase ()
@property (nonatomic) sqlite3 *db;
@end

@implementation IMDatabase

+ (instancetype)shared {
	static IMDatabase *shared;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[IMDatabase alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		[self openDatabase];
	}
	return self;
}

- (void)openDatabase {
	NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	[[NSFileManager defaultManager] createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *path = [support stringByAppendingPathComponent:@"immich.sqlite"];

	if (sqlite3_open(path.UTF8String, &_db) != SQLITE_OK) {
		NSLog(@"IMDatabase: failed to open %@: %s", path, sqlite3_errmsg(_db));
		return;
	}

	[self exec:@"CREATE TABLE IF NOT EXISTS buckets ("
	            "  timeBucket TEXT PRIMARY KEY,"
	            "  count INTEGER NOT NULL,"
	            "  position INTEGER NOT NULL"
	            ")"];
	[self exec:@"CREATE TABLE IF NOT EXISTS assets ("
	            "  id TEXT PRIMARY KEY,"
	            "  timeBucket TEXT NOT NULL,"
	            "  position INTEGER NOT NULL,"
	            "  fileCreatedAt TEXT,"
	            "  isFavorite INTEGER,"
	            "  isImage INTEGER,"
	            "  durationMs INTEGER,"
	            "  ratio REAL"
	            ")"];
	[self exec:@"CREATE INDEX IF NOT EXISTS idx_assets_bucket ON assets(timeBucket, position)"];
	[self exec:@"ALTER TABLE assets ADD COLUMN city TEXT"];
	[self exec:@"ALTER TABLE assets ADD COLUMN country TEXT"];
	[self exec:@"ALTER TABLE assets ADD COLUMN livePhotoVideoId TEXT"];
	[self exec:@"CREATE TABLE IF NOT EXISTS sync_state ("
	            "  deviceAssetId TEXT PRIMARY KEY,"
	            "  assetId TEXT,"
	            "  state INTEGER NOT NULL"
	            ")"];
}

- (void)exec:(NSString *)sql {
	char *errMsg = NULL;
	if (sqlite3_exec(self.db, sql.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
		NSLog(@"IMDatabase: exec failed: %s (%@)", errMsg, sql);
		sqlite3_free(errMsg);
	}
}

#pragma mark - Buckets

- (void)replaceBucketDates:(NSArray<NSString *> *)dates counts:(NSArray<NSNumber *> *)counts {
	[self exec:@"BEGIN TRANSACTION"];
	[self exec:@"DELETE FROM buckets"];

	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db, "INSERT INTO buckets (timeBucket, count, position) VALUES (?, ?, ?)", -1, &stmt, NULL);
	for (NSUInteger i = 0; i < dates.count; i++) {
		sqlite3_bind_text(stmt, 1, [dates[i] UTF8String], -1, SQLITE_TRANSIENT);
		sqlite3_bind_int(stmt, 2, [counts[i] intValue]);
		sqlite3_bind_int64(stmt, 3, (sqlite3_int64)i);
		if (sqlite3_step(stmt) != SQLITE_DONE) {
			NSLog(@"IMDatabase: insert bucket failed: %s", sqlite3_errmsg(self.db));
		}
		sqlite3_reset(stmt);
	}
	sqlite3_finalize(stmt);
	[self exec:@"COMMIT"];
}

- (void)cachedBucketDates:(NSArray<NSString *> *_Nonnull *_Nonnull)outDates
                    counts:(NSArray<NSNumber *> *_Nonnull *_Nonnull)outCounts {
	NSMutableArray<NSString *> *dates = [NSMutableArray array];
	NSMutableArray<NSNumber *> *counts = [NSMutableArray array];

	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db, "SELECT timeBucket, count FROM buckets ORDER BY position ASC", -1, &stmt, NULL);
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		[dates addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)]];
		[counts addObject:@(sqlite3_column_int(stmt, 1))];
	}
	sqlite3_finalize(stmt);

	*outDates = dates;
	*outCounts = counts;
}

#pragma mark - Assets

- (void)replaceAssets:(NSArray<IMAsset *> *)assets forTimeBucket:(NSString *)timeBucket {
	[self exec:@"BEGIN TRANSACTION"];

	sqlite3_stmt *deleteStmt = NULL;
	sqlite3_prepare_v2(self.db, "DELETE FROM assets WHERE timeBucket = ?", -1, &deleteStmt, NULL);
	sqlite3_bind_text(deleteStmt, 1, [timeBucket UTF8String], -1, SQLITE_TRANSIENT);
	sqlite3_step(deleteStmt);
	sqlite3_finalize(deleteStmt);

	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db,
	                    "INSERT INTO assets (id, timeBucket, position, fileCreatedAt, isFavorite, isImage, durationMs, ratio, city, country, livePhotoVideoId) "
	                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
	                    -1, &stmt, NULL);
	for (NSUInteger i = 0; i < assets.count; i++) {
		IMAsset *asset = assets[i];
		sqlite3_bind_text(stmt, 1, [asset.assetId UTF8String], -1, SQLITE_TRANSIENT);
		sqlite3_bind_text(stmt, 2, [timeBucket UTF8String], -1, SQLITE_TRANSIENT);
		sqlite3_bind_int64(stmt, 3, (sqlite3_int64)i);
		sqlite3_bind_text(stmt, 4, [asset.fileCreatedAt UTF8String], -1, SQLITE_TRANSIENT);
		sqlite3_bind_int(stmt, 5, asset.isFavorite ? 1 : 0);
		sqlite3_bind_int(stmt, 6, asset.isImage ? 1 : 0);
		sqlite3_bind_int64(stmt, 7, (sqlite3_int64)asset.durationMs);
		sqlite3_bind_double(stmt, 8, asset.ratio);
		if (asset.city) {
			sqlite3_bind_text(stmt, 9, [asset.city UTF8String], -1, SQLITE_TRANSIENT);
		} else {
			sqlite3_bind_null(stmt, 9);
		}
		if (asset.country) {
			sqlite3_bind_text(stmt, 10, [asset.country UTF8String], -1, SQLITE_TRANSIENT);
		} else {
			sqlite3_bind_null(stmt, 10);
		}
		if (asset.livePhotoVideoId) {
			sqlite3_bind_text(stmt, 11, [asset.livePhotoVideoId UTF8String], -1, SQLITE_TRANSIENT);
		} else {
			sqlite3_bind_null(stmt, 11);
		}
		if (sqlite3_step(stmt) != SQLITE_DONE) {
			NSLog(@"IMDatabase: insert asset failed: %s", sqlite3_errmsg(self.db));
		}
		sqlite3_reset(stmt);
	}
	sqlite3_finalize(stmt);
	[self exec:@"COMMIT"];
}

- (NSArray<IMAsset *> *)cachedAssetsForTimeBucket:(NSString *)timeBucket {
	NSMutableArray<IMAsset *> *assets = [NSMutableArray array];

	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db,
	                    "SELECT id, fileCreatedAt, isFavorite, isImage, durationMs, ratio, city, country, livePhotoVideoId "
	                    "FROM assets WHERE timeBucket = ? ORDER BY position ASC",
	                    -1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, [timeBucket UTF8String], -1, SQLITE_TRANSIENT);
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		NSString *assetId = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
		const char *fileCreatedAtC = (const char *)sqlite3_column_text(stmt, 1);
		NSString *fileCreatedAt = fileCreatedAtC ? [NSString stringWithUTF8String:fileCreatedAtC] : @"";
		BOOL isFavorite = sqlite3_column_int(stmt, 2) != 0;
		BOOL isImage = sqlite3_column_int(stmt, 3) != 0;
		NSInteger durationMs = (NSInteger)sqlite3_column_int64(stmt, 4);
		double ratio = sqlite3_column_double(stmt, 5);
		const char *cityC = (const char *)sqlite3_column_text(stmt, 6);
		NSString *city = cityC ? [NSString stringWithUTF8String:cityC] : nil;
		const char *countryC = (const char *)sqlite3_column_text(stmt, 7);
		NSString *country = countryC ? [NSString stringWithUTF8String:countryC] : nil;
		const char *liveC = (const char *)sqlite3_column_text(stmt, 8);
		NSString *livePhotoVideoId = liveC ? [NSString stringWithUTF8String:liveC] : nil;
		[assets addObject:[IMAsset assetWithId:assetId
		                          fileCreatedAt:fileCreatedAt
		                               favorite:isFavorite
		                                  image:isImage
		                             durationMs:durationMs
		                                  ratio:ratio
		                                   city:city
		                                country:country
		                       livePhotoVideoId:livePhotoVideoId]];
	}
	sqlite3_finalize(stmt);

	return assets;
}

- (void)clearAllData {
	[self exec:@"DELETE FROM buckets"];
	[self exec:@"DELETE FROM assets"];
	[self exec:@"DELETE FROM sync_state"];
}

#pragma mark - Sync state (Phase 7)

- (void)setSyncState:(IMSyncState)state
              assetId:(nullable NSString *)assetId
    forDeviceAssetId:(NSString *)deviceAssetId {
	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db,
	                    "INSERT INTO sync_state (deviceAssetId, assetId, state) VALUES (?, ?, ?) "
	                    "ON CONFLICT(deviceAssetId) DO UPDATE SET assetId = excluded.assetId, state = excluded.state",
	                    -1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, [deviceAssetId UTF8String], -1, SQLITE_TRANSIENT);
	if (assetId) {
		sqlite3_bind_text(stmt, 2, [assetId UTF8String], -1, SQLITE_TRANSIENT);
	} else {
		sqlite3_bind_null(stmt, 2);
	}
	sqlite3_bind_int(stmt, 3, (int)state);
	BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;
	if (!ok) {
		NSLog(@"IMDatabase: set sync state failed: %s", sqlite3_errmsg(self.db));
	}
	sqlite3_finalize(stmt);
	if (ok) {
		[[NSNotificationCenter defaultCenter] postNotificationName:IMSyncStateDidChangeNotification object:self];
	}
}

- (void)resetUploadingStates {
	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db, "UPDATE sync_state SET state = ? WHERE state = ?", -1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, (int)IMSyncStateLocalOnly);
	sqlite3_bind_int(stmt, 2, (int)IMSyncStateUploading);
	BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;
	sqlite3_finalize(stmt);
	if (ok && sqlite3_changes(self.db) > 0) {
		[[NSNotificationCenter defaultCenter] postNotificationName:IMSyncStateDidChangeNotification object:self];
	}
}

- (IMSyncState)syncStateForDeviceAssetId:(NSString *)deviceAssetId {
	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db, "SELECT state FROM sync_state WHERE deviceAssetId = ?", -1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, [deviceAssetId UTF8String], -1, SQLITE_TRANSIENT);
	IMSyncState state = IMSyncStateUnknown;
	if (sqlite3_step(stmt) == SQLITE_ROW) {
		state = (IMSyncState)sqlite3_column_int(stmt, 0);
	}
	sqlite3_finalize(stmt);
	return state;
}

- (void)syncStateCountsLocalOnly:(NSInteger *)outLocalOnly synced:(NSInteger *)outSynced {
	NSInteger localOnly = 0, synced = 0;
	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db, "SELECT state, COUNT(*) FROM sync_state GROUP BY state", -1, &stmt, NULL);
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		IMSyncState state = (IMSyncState)sqlite3_column_int(stmt, 0);
		int count = sqlite3_column_int(stmt, 1);
		if (state == IMSyncStateLocalOnly) {
			localOnly = count;
		} else if (state == IMSyncStateSynced) {
			synced = count;
		}
	}
	sqlite3_finalize(stmt);
	if (outLocalOnly) {
		*outLocalOnly = localOnly;
	}
	if (outSynced) {
		*outSynced = synced;
	}
}

- (NSArray<NSString *> *)deviceAssetIdsWithState:(IMSyncState)state {
	NSMutableArray<NSString *> *ids = [NSMutableArray array];
	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db, "SELECT deviceAssetId FROM sync_state WHERE state = ?", -1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, (int)state);
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		[ids addObject:[NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)]];
	}
	sqlite3_finalize(stmt);
	return ids;
}

- (NSDictionary<NSString *, NSNumber *> *)allDeviceAssetSyncStates {
	NSMutableDictionary<NSString *, NSNumber *> *states = [NSMutableDictionary dictionary];
	sqlite3_stmt *stmt = NULL;
	sqlite3_prepare_v2(self.db, "SELECT deviceAssetId, state FROM sync_state", -1, &stmt, NULL);
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		NSString *deviceAssetId = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
		states[deviceAssetId] = @(sqlite3_column_int(stmt, 1));
	}
	sqlite3_finalize(stmt);
	return states;
}

@end
