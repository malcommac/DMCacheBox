//
//  DMCacheBox.h
//  Fast advanced caching system for Objective-C (Cocoa/iOS compatible)
//
//  Created by Daniele Margutti (daniele.margutti@gmail.com) on 7/9/12.
//  Web: http://www.danielemargutti.com
//
//  Licensed under MIT License
//

#import <Foundation/Foundation.h>

typedef void (^DMCacheBoxOperationHandler)(NSError *error);
typedef void (^DMCacheBoxMultipleOperationHandler)(NSUInteger removedIdentifiers, NSUInteger remainingIdentifiers);
typedef void (^DMCacheBoxStoreData)(NSString *destinationPath,BOOL existingCacheReplaced, NSError *error);
typedef void (^DMCacheBoxStoreMultipleData)(NSArray *writtenCacheIdentifiers);
typedef void (^DMCacheBoxStoreProgress)(NSUInteger itemsDone);

@interface DMCacheBox : NSObject { }

@property (nonatomic,readonly)  NSString*       cacheDirectory;
@property (nonatomic,assign)    NSTimeInterval  defaultCacheExpireInterval;

+ (DMCacheBox *) defaultCache;
- (void) save;

#pragma mark - REMOVE CACHED DATA

    //
- (void) flushCache:(BOOL) onlyExpiredIdentifiers withCompletition:(DMCacheBoxMultipleOperationHandler) completition;
- (void) removeCachedIdentifier:(NSString *) cacheIdentifier withCompletition:(DMCacheBoxOperationHandler) completition;
- (void) removeCachedIdentifiers:(NSArray *) cacheIdentifiers withCompletition:(DMCacheBoxMultipleOperationHandler) completition;

#pragma mark - QUERY CACHE

- (NSArray *) expiredCachedIdentifiers;
- (BOOL) hasCachedIdentifier:(NSString *) cacheIdentifier;
- (BOOL) isCachedIdentifierValid:(NSString *) cacheIdentifier;

- (NSDictionary *) cacheDictionaryForIdentifier:(NSString *) cacheIdentifier;
- (NSData *) dataForIdentifier:(NSString *) cacheIdentifier;

#pragma mark - SIMPLE SET DATA

- (void) setData:(NSData *) data forIdentifier:(NSString *) cacheIdentifier;
- (void) setData:(NSData *) data forIdentifier:(NSString *) cacheIdentifier expireIn:(NSTimeInterval) expireInterval;

- (BOOL) setFileAtPath:(NSString *) filePathToCache forIdentifier:(NSString *) cacheIdentifier;
- (BOOL) setFileAtPath:(NSString *) filePathToCache forIdentifier:(NSString *) cacheIdentifier expireIn:(NSTimeInterval) expireInterval;

#pragma mark - IMAGE UTILS

#if TARGET_OS_IPHONE
    - (void)setImage:(UIImage*)anImage forIdentifier:(NSString*)cacheIdentifier expireInterval:(NSTimeInterval)timeoutInterval;
    - (UIImage*)imageForIdentifier:(NSString*)cacheIdentifier;
#else
    - (NSImage*)imageForIdentifier:(NSString*)cacheIdentifier;
    - (void)setImage:(NSImage*)anImage forIdentifier:(NSString*)cacheIdentifier expireInterval:(NSTimeInterval)timeoutInterval;
#endif

#pragma mark - PLIST UTILS

- (NSData*)plistForIdentifier:(NSString*)cacheIdentifier;
- (void)setPlist:(id)plistObject forIdentifier:(NSString*)cacheIdentifier expireInterval:(NSTimeInterval)timeoutInterval;

#pragma mark - SAVE TO CACHE (ADVANCED CONTROL)

    // Add a new entry value to cache
- (void) setData:(NSData *) data withParameters:(NSDictionary *) params forIdentifier:(NSString *) cacheIdentifier
  expireInterval:(NSTimeInterval) expireInterval withCompletition:(DMCacheBoxStoreData) completition;
    // Set data with an existing file at path

    // Allows you to save a set of <key,value> (<identifier_to_set,NSData_to_save>) to save
- (void) setData:(NSDictionary *) IDsDataPairValue expireInterval:(NSTimeInterval) expireInterval
        progress:(DMCacheBoxStoreProgress) progress withCompletition:(DMCacheBoxStoreMultipleData) completition;

- (BOOL) setFileAtPath:(NSString *) filePath withParameters:(NSDictionary *) params forIdentifier:(NSString *) cacheIdentifier
        expireInterval:(NSTimeInterval) expireInterval withCompletition:(DMCacheBoxStoreData) completition;

- (void) setFilePaths:(NSDictionary *) pathsAndIdentifierPairs expireInterval:(NSTimeInterval) expireInterval
             progress:(DMCacheBoxStoreProgress) progress withCompletition:(DMCacheBoxStoreMultipleData) completition;

@end
