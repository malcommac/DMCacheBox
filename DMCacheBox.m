//
//  DMCacheBox.h
//  Fast advanced caching system for Objective-C (Cocoa/iOS compatible)
//
//  Created by Daniele Margutti (daniele.margutti@gmail.com) on 7/9/12.
//  Web: http://www.danielemargutti.com
//
//  Licensed under MIT License
//

#import "DMCacheBox.h"

#define kDMCacheBoxDefaultCacheExpireInterval       (60*60*24)          // Default expire time interval (24h)
#define kDMFlushExpiredIdentifiersAtStartup         YES

    // Internals
#define kDMCacheBoxCacheDirectoryName               @"DMCacheBox"
#define kDMCacheBoxCacheDatabaseFilename            @"DMCacheDB.plist"
#define kDMCacheEntry_ExpireDate                    @"expire_date"

@interface DMCacheBox() {
    NSMutableDictionary*        cacheContent;       // Cache content dictionary
    NSOperationQueue*           diskIOQueue;        // Main disk I/O operation queue
}

- (NSString *) cacheDirectoryForIdentifier:(NSString *) cacheID;
- (NSString *) cacheDatabasePath;
- (NSDictionary *) entryWithExtraParams:(NSDictionary *) params expireIn:(NSTimeInterval) expireInterval;

- (void) setDataWithKeys:(NSDictionary *) valuesAndIdentifiers
      valuesAreFilePaths:(BOOL) valuesAreFilePaths
          expireInterval:(NSTimeInterval) expireInterval
                progress:(DMCacheBoxStoreProgress) progress
        withCompletition:(DMCacheBoxStoreMultipleData) completition;

@end


@implementation DMCacheBox

@synthesize cacheDirectory,defaultCacheExpireInterval;

+ (DMCacheBox *) defaultCache {
    static dispatch_once_t pred;
    static DMCacheBox *shared = nil;
    
    dispatch_once(&pred, ^{
        shared = [[DMCacheBox alloc] initWithCacheFolder:nil];
    });
    return shared;
}

- (void)dealloc {
    [self save]; // save changes
}

- (id)initWithCacheFolder:(NSString *) cacheBaseFolder {
    self = [super init];
    if (self) {
        self.defaultCacheExpireInterval = kDMCacheBoxDefaultCacheExpireInterval;
        
        if (cacheBaseFolder != nil) // if we have specified a custom cache folder path we force it
            kDMCacheBoxCacheDirectory = cacheBaseFolder;
        // otherwise we'll use default location (see -cacheDirectory)
        
            // Create our cache base folder (if needed)
        [[NSFileManager defaultManager] createDirectoryAtPath:[self cacheDirectory]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        
            // Load saved database or create a new one
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self cacheDatabasePath]]) {
            cacheContent = [NSKeyedUnarchiver unarchiveObjectWithFile:[self cacheDatabasePath]];
            if (kDMFlushExpiredIdentifiersAtStartup == YES) {
                [self flushCache:YES
                withCompletition:^(NSUInteger removedIdentifiers, NSUInteger remainingIdentifiers) {
                
                }]; // flush expired cache identifiers
            }
        } else
            cacheContent = [[NSMutableDictionary alloc] init];
        
        diskIOQueue = [[NSOperationQueue alloc] init];
        
    }
    return self;
}

- (void) save {
	@synchronized(self) {
		[cacheContent writeToFile:[self cacheDatabasePath]
                       atomically:YES];
	}
}

static NSString* kDMCacheBoxCacheDirectory;

#pragma mark - DIRECTORIES

    // Return the base cache directory. If you have not specified a default one we will use our default path
- (NSString *) cacheDirectory {
    if (kDMCacheBoxCacheDirectory == nil) {
        NSString* systemCacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
		kDMCacheBoxCacheDirectory = [[[systemCacheDir stringByAppendingPathComponent:[[NSProcessInfo processInfo] processName]] stringByAppendingPathComponent:kDMCacheBoxCacheDirectoryName] copy];
    }
    return kDMCacheBoxCacheDirectory;
}

    // Return cache database full path
- (NSString *) cacheDatabasePath {
    return [self cacheDirectoryForIdentifier:kDMCacheBoxCacheDatabaseFilename];
}

    // Return a directory for given identifier key
- (NSString *) cacheDirectoryForIdentifier:(NSString *) cacheID {
    return [self.cacheDirectory stringByAppendingPathComponent:cacheID];
}

#pragma mark - FLUSH CACHE

    // Flush cache database (if onlyExpiredIdentifiers is YES we will remove only expired items, otherwise we will reset our cache)
- (void) flushCache:(BOOL) onlyExpiredIdentifiers
   withCompletition:(DMCacheBoxMultipleOperationHandler) completition {
    
    [self removeCachedIdentifiers:(onlyExpiredIdentifiers ? [self expiredCachedIdentifiers] : [cacheContent allKeys])
                 withCompletition:^(NSUInteger removedIdentifiers, NSUInteger remainingIdentifiers) {
                     completition(removedIdentifiers,remainingIdentifiers);
                 }];
}

#pragma mark - GET EXPIRED CACHE IDENTIFIERS

    // Return only expired cached identifiers
- (NSArray *) expiredCachedIdentifiers {
    
    NSMutableArray *keysToRemove = [[NSMutableArray alloc] init];

    NSDate *currentDate = [NSDate date];
    [cacheContent.allKeys enumerateObjectsUsingBlock:^(NSString* cacheIdentifier, NSUInteger idx, BOOL *stop) {
        NSDictionary *cacheEntry = [cacheContent objectForKey:cacheIdentifier];
        NSDate *expireDate = ((NSDate*)[cacheEntry objectForKey:kDMCacheEntry_ExpireDate]);
        if ([[currentDate earlierDate: expireDate] isEqualToDate:currentDate])
            [keysToRemove addObject:cacheIdentifier];
    }];
    return keysToRemove;
}

#pragma mark - REMOVE CACHED IDENTIFIERS

    // Remove cache identifier set
- (void) removeCachedIdentifiers:(NSArray *) cacheIdentifiers
                withCompletition:(DMCacheBoxMultipleOperationHandler) completition {
    
    NSOperationQueue* deleteOperations = [[NSOperationQueue alloc] init];
    [deleteOperations setSuspended:YES];
    
    __block NSUInteger removedItemsCounter = 0;
    NSMutableArray *removedCachedIdentifiers = [[NSMutableArray alloc] init];
    [cacheIdentifiers enumerateObjectsUsingBlock:^(NSString* identifierToRemove, NSUInteger idx, BOOL *stop) {
        NSString *identifierContentPath = [self cacheDirectoryForIdentifier:identifierToRemove];
        [deleteOperations addOperationWithBlock:^{
                // remove cached content
            if([[NSFileManager defaultManager] removeItemAtPath:identifierContentPath error:nil]) {
                [removedCachedIdentifiers addObject:identifierToRemove];
                removedItemsCounter++;
            }
        }];
    }];
    
    [deleteOperations setSuspended:NO];
    [deleteOperations waitUntilAllOperationsAreFinished];
    // delete entry for successfully removed cached identifiers
    [cacheContent removeObjectsForKeys:removedCachedIdentifiers];
    
    [self save]; // save changes
    
    completition(removedItemsCounter,[cacheContent count]);
}

    // Remove cached identifier
- (void) removeCachedIdentifier:(NSString *) cacheIdentifier
               withCompletition:(DMCacheBoxOperationHandler) completition {
    NSString *identifierContentPath = [self cacheDirectoryForIdentifier:cacheIdentifier];
    if (identifierContentPath == nil) {
        completition([NSError errorWithDomain:@"Key identifier does not exist in local cache" code:0 userInfo:nil]);
    } else {
        [diskIOQueue addOperationWithBlock:^{
            NSError* error = nil;
            [[NSFileManager defaultManager] removeItemAtPath:identifierContentPath error:&error];
            completition(error);
            [self save]; // save changes
        }];
    }
}

#pragma mark - QUERY FOR CACHED IDENTIFIERS

- (BOOL) hasCachedIdentifier:(NSString *) cacheIdentifier {
    return ([cacheContent objectForKey:cacheIdentifier] != nil);
}

- (BOOL) isCachedIdentifierValid:(NSString *) cacheIdentifier {
    NSDictionary *cacheDict = [cacheContent objectForKey:cacheIdentifier];
    if (cacheDict == nil) return NO;
    NSDate *cache_date = [cacheDict objectForKey:kDMCacheEntry_ExpireDate];
    if ([[[NSDate date] earlierDate:cache_date] isEqualToDate:cache_date])
        return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:[self cacheDirectoryForIdentifier:cacheIdentifier]];
}

#pragma mark - SAVE DATA IN CACHE

- (void) setData:(NSData *) data forIdentifier:(NSString *) cacheIdentifier {
    [self setData:data forIdentifier:cacheIdentifier expireIn:self.defaultCacheExpireInterval];
}

- (void) setData:(NSData *) data forIdentifier:(NSString *) cacheIdentifier expireIn:(NSTimeInterval) expireInterval {
    [self setData:data
   withParameters:nil
    forIdentifier:cacheIdentifier
   expireInterval:self.defaultCacheExpireInterval
 withCompletition:^(NSString *destinationPath, BOOL existingCacheReplaced, NSError *error) {
     
 }];
}

- (void) setData:(NSData *) data
  withParameters:(NSDictionary *) params
   forIdentifier:(NSString *) cacheIdentifier
  expireInterval:(NSTimeInterval) expireInterval
withCompletition:(DMCacheBoxStoreData) completition {
    
    BOOL replaceExistingKey = [self hasCachedIdentifier:cacheIdentifier];
    [diskIOQueue addOperationWithBlock:^{
            // Store cache entry
        NSString *destination_path = [self cacheDirectoryForIdentifier:cacheIdentifier];
        [cacheContent setObject:[self entryWithExtraParams:params expireIn:expireInterval] forKey:cacheIdentifier];

            // Save cached content data
        NSError *error = nil;
        [data writeToFile:destination_path
                  options:NSDataWritingAtomic
                    error:&error];
        completition(destination_path,replaceExistingKey,error);
        [self save]; // save changes
    }];
}

- (BOOL) setFileAtPath:(NSString *) filePathToCache
         forIdentifier:(NSString *) cacheIdentifier {
    return [self setFileAtPath:filePathToCache forIdentifier:cacheIdentifier expireIn:self.defaultCacheExpireInterval];
}

- (BOOL) setFileAtPath:(NSString *) filePathToCache forIdentifier:(NSString *) cacheIdentifier expireIn:(NSTimeInterval) expireInterval {
    return [self setFileAtPath:filePathToCache
                withParameters:nil
                 forIdentifier:cacheIdentifier
                expireInterval:self.defaultCacheExpireInterval
              withCompletition:^(NSString *destinationPath, BOOL existingCacheReplaced, NSError *error) {
                  
              }];
}

- (BOOL) setFileAtPath:(NSString *) filePath
        withParameters:(NSDictionary *) params
         forIdentifier:(NSString *) cacheIdentifier
        expireInterval:(NSTimeInterval) expireInterval
      withCompletition:(DMCacheBoxStoreData) completition {
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath] == NO)
        return NO;
    
    BOOL replaceExistingKey = [self hasCachedIdentifier:cacheIdentifier];
    [diskIOQueue addOperationWithBlock:^{
            // Store cache entry
        NSString *destination_path = [self cacheDirectoryForIdentifier:cacheIdentifier];
        [cacheContent setObject:[self entryWithExtraParams:params expireIn:expireInterval] forKey:cacheIdentifier];

            // Copy real file to cache
        NSError*error = nil;
        [[NSFileManager defaultManager] copyItemAtPath:filePath
                                                toPath:destination_path
                                                 error:&error];
        completition(destination_path,replaceExistingKey,error);
        [self save]; // save changes
    }];
        
    return YES;
}

- (NSDictionary *) entryWithExtraParams:(NSDictionary *) params expireIn:(NSTimeInterval) expireInterval {
    NSDate *expire_date = [NSDate dateWithTimeIntervalSinceNow:expireInterval];
    NSMutableDictionary *paramDict = [[NSMutableDictionary alloc] initWithObjectsAndKeys:expire_date,kDMCacheEntry_ExpireDate, nil];
    if (params)
        [paramDict addEntriesFromDictionary:params];
    return paramDict;
}

- (void) setData:(NSDictionary *) IDsDataPairValue
  expireInterval:(NSTimeInterval) expireInterval
        progress:(DMCacheBoxStoreProgress) progress
withCompletition:(DMCacheBoxStoreMultipleData) completition {
    
    [self setDataWithKeys:IDsDataPairValue
       valuesAreFilePaths:NO
           expireInterval:expireInterval
                 progress:^(NSUInteger itemsDone) {
                     progress(itemsDone);
                 } withCompletition:^(NSArray *writtenCacheIdentifiers) {
                     completition(writtenCacheIdentifiers);
                 }];
}

- (void) setFilePaths:(NSDictionary *) pathsAndIdentifierPairs
       expireInterval:(NSTimeInterval) expireInterval
             progress:(DMCacheBoxStoreProgress) progress
     withCompletition:(DMCacheBoxStoreMultipleData) completition {
    
    [self setDataWithKeys:pathsAndIdentifierPairs
       valuesAreFilePaths:YES
           expireInterval:expireInterval
                 progress:^(NSUInteger itemsDone) {
                     progress(itemsDone);
                 } withCompletition:^(NSArray *writtenCacheIdentifiers) {
                     completition(writtenCacheIdentifiers);
                 }];
}

- (void) setDataWithKeys:(NSDictionary *) valuesAndIdentifiers
      valuesAreFilePaths:(BOOL) valuesAreFilePaths
          expireInterval:(NSTimeInterval) expireInterval
                progress:(DMCacheBoxStoreProgress) progress
        withCompletition:(DMCacheBoxStoreMultipleData) completition {
    
    NSOperationQueue* deleteOperations = [[NSOperationQueue alloc] init];
    [deleteOperations setSuspended:YES];
    
    __block NSUInteger itemsDone = 0;
    NSMutableArray *writtenCacheIdentifiers = [[NSMutableArray alloc] init];
    [valuesAndIdentifiers.allKeys enumerateObjectsUsingBlock:^(NSString* cacheIdentifier, NSUInteger idx, BOOL *stop) {
        NSString *destination_path = [self cacheDirectoryForIdentifier:cacheIdentifier];
        
        [cacheContent setObject:[self entryWithExtraParams:nil expireIn:expireInterval] forKey:cacheIdentifier];
        NSError *error = nil;
        
        id value = [valuesAndIdentifiers objectForKey:cacheIdentifier];
        
        if (!valuesAreFilePaths) {
            [((NSData*)value) writeToFile:destination_path
                                  options:NSDataWritingAtomic
                                    error:&error];
        } else {
            [[NSFileManager defaultManager] copyItemAtPath:((NSString *)value)
                                                    toPath:destination_path
                                                    error:&error];
        }
        if (error == nil) {
            [writtenCacheIdentifiers addObject:cacheIdentifier];
            itemsDone++;
        }
        progress(itemsDone);
    }];
    
    [deleteOperations setSuspended:NO];
    [deleteOperations waitUntilAllOperationsAreFinished];
        // delete entry for successfully removed cached identifiers
    [self save]; // save changes
    completition(writtenCacheIdentifiers);
}

#pragma mark - QUERY CACHED CONTENT

- (NSData *) dataForIdentifier:(NSString *) cacheIdentifier {
    NSDictionary *cacheDict = [cacheContent objectForKey:cacheIdentifier];
    if (cacheDict == nil && [[NSFileManager defaultManager] fileExistsAtPath:[self cacheDirectoryForIdentifier:cacheIdentifier]]) return nil;
    return [NSData dataWithContentsOfFile:[self cacheDirectoryForIdentifier:cacheIdentifier]];
}

- (NSDictionary *) cacheDictionaryForIdentifier:(NSString *) cacheIdentifier {
    return [cacheContent objectForKey:cacheIdentifier];
}

#pragma mark -
#pragma mark Image methds

#if TARGET_OS_IPHONE

- (UIImage*)imageForIdentifier:(NSString*)cacheIdentifier {
	return [UIImage imageWithContentsOfFile:[self cacheDirectoryForIdentifier:cacheIdentifier]];
}

- (void)setImage:(UIImage*)anImage
   forIdentifier:(NSString*)cacheIdentifier
  expireInterval:(NSTimeInterval)timeoutInterval {
    
    [self setData:UIImagePNGRepresentation(anImage)
   withParameters:nil
    forIdentifier:cacheIdentifier
   expireInterval:timeoutInterval
 withCompletition:^(NSString *destinationPath, BOOL existingCacheReplaced, NSError *error) {
     
 }];
}

#else

- (NSImage*)imageForIdentifier:(NSString*)cacheIdentifier {
	return [[NSImage alloc] initWithData:[self dataForIdentifier:cacheIdentifier]];
}

- (void)setImage:(NSImage*)anImage
   forIdentifier:(NSString*)cacheIdentifier
  expireInterval:(NSTimeInterval)timeoutInterval {
    
    [self setData:[[[anImage representations] objectAtIndex:0] representationUsingType:NSPNGFileType properties:nil]
   withParameters:nil
    forIdentifier:cacheIdentifier
   expireInterval:timeoutInterval
 withCompletition:^(NSString *destinationPath, BOOL existingCacheReplaced, NSError *error) {
     
 }];
}

#endif

#pragma mark - PLIST

- (NSData*)plistForIdentifier:(NSString*)cacheIdentifier {
	NSData* plistData = [self dataForIdentifier:cacheIdentifier];
	return [NSPropertyListSerialization propertyListFromData:plistData
											mutabilityOption:NSPropertyListImmutable
													  format:nil
											errorDescription:nil];
}


- (void)setPlist:(id)plistObject forIdentifier:(NSString*)cacheIdentifier expireInterval:(NSTimeInterval)timeoutInterval {
        // Binary plists are used over XML for better performance
	NSData* plistData = [NSPropertyListSerialization dataFromPropertyList:plistObject
																   format:NSPropertyListBinaryFormat_v1_0
														 errorDescription:NULL];
	
    [self setData:plistData
   withParameters:nil
    forIdentifier:cacheIdentifier
   expireInterval:timeoutInterval
 withCompletition:^(NSString *destinationPath, BOOL existingCacheReplaced, NSError *error) {
     
 }];
}

@end
