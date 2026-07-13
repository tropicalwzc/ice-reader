//
//  MKiCloudSync.m
//  iCloud1
//
//  Created by Mugunth Kumar (@mugunthkumar) on 20/11/11.
//  Copyright (C) 2011-2020 by Steinlogic

//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

//  As a side note, you might also consider
//	1) tweeting about this mentioning @mugunthkumar
//	2) A paypal donation to mugunth.kumar@gmail.com


#import "MKiCloudSync.h"

static NSString *prefix;
@implementation MKiCloudSync

+(long long) progressValue:(id) value {
  if([value respondsToSelector:@selector(longLongValue)]) {
    return [value longLongValue];
  }

  return 0;
}

+(NSString*) overrideKeyForProgressKey:(NSString*) key {
  return [NSString stringWithFormat:@"%@Override_%@", prefix, key];
}

+(BOOL) isProgressKey:(NSString*) key {
  NSString *overridePrefix = [NSString stringWithFormat:@"%@Override_", prefix];
  return [key hasPrefix:prefix] && ![key hasPrefix:overridePrefix];
}

+(void) setObject:(id) value
            forKey:(NSString*) key
        ifDifferentInDefaults:(NSUserDefaults*) defaults {
  if(value != nil && ![[defaults objectForKey:key] isEqual:value]) {
    [defaults setObject:value forKey:key];
  }
}

+(void) setObject:(id) value
            forKey:(NSString*) key
        ifDifferentInCloud:(NSUbiquitousKeyValueStore*) cloudStore {
  if(value != nil && ![[cloudStore objectForKey:key] isEqual:value]) {
    [cloudStore setObject:value forKey:key];
  }
}

+(void) mergeLocalAndCloudProgress {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSUbiquitousKeyValueStore *cloudStore = [NSUbiquitousKeyValueStore defaultStore];
  NSMutableSet<NSString*> *progressKeys = [NSMutableSet set];

  for(NSString *key in [defaults dictionaryRepresentation]) {
    if([self isProgressKey:key]) {
      [progressKeys addObject:key];
    }
  }

  for(NSString *key in [cloudStore dictionaryRepresentation]) {
    if([self isProgressKey:key]) {
      [progressKeys addObject:key];
    }
  }

  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSUserDefaultsDidChangeNotification
                                                object:nil];

  for(NSString *key in progressKeys) {
    id localValue = [defaults objectForKey:key];
    id cloudValue = [cloudStore objectForKey:key];
    NSString *overrideKey = [self overrideKeyForProgressKey:key];
    id localOverride = [defaults objectForKey:overrideKey];
    id cloudOverride = [cloudStore objectForKey:overrideKey];
    long long localRevision = [self progressValue:localOverride];
    long long cloudRevision = [self progressValue:cloudOverride];
    id winningValue = nil;

    if(localRevision > cloudRevision) {
      winningValue = localValue;
    } else if(cloudRevision > localRevision) {
      winningValue = cloudValue;
    } else if(localValue == nil) {
      winningValue = cloudValue;
    } else if(cloudValue == nil ||
              [self progressValue:localValue] >= [self progressValue:cloudValue]) {
      winningValue = localValue;
    } else {
      winningValue = cloudValue;
    }

    id winningRevision = localRevision >= cloudRevision ? localOverride : cloudOverride;
    [self setObject:winningValue forKey:key ifDifferentInDefaults:defaults];
    [self setObject:winningValue forKey:key ifDifferentInCloud:cloudStore];
    [self setObject:winningRevision forKey:overrideKey ifDifferentInDefaults:defaults];
    [self setObject:winningRevision forKey:overrideKey ifDifferentInCloud:cloudStore];
  }

  [defaults synchronize];
  [cloudStore synchronize];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(updateToiCloud:)
                                               name:NSUserDefaultsDidChangeNotification
                                             object:nil];
}

+(void) updateToiCloud:(NSNotification*) notificationObject {

  @synchronized(self) {
    [self mergeLocalAndCloudProgress];
  }
}

+(void) forceUpdateProgress:(long long)progress forKey:(NSString*)key {
  if(![self isProgressKey:key]) {
    return;
  }

  @synchronized(self) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUbiquitousKeyValueStore *cloudStore = [NSUbiquitousKeyValueStore defaultStore];
    NSString *overrideKey = [self overrideKeyForProgressKey:key];
    long long timestamp = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    long long latestRevision = MAX([self progressValue:[defaults objectForKey:overrideKey]],
                                   [self progressValue:[cloudStore objectForKey:overrideKey]]);
    long long revision = MAX(timestamp, latestRevision + 1);
    NSString *progressValue = [NSString stringWithFormat:@"%lld", progress];
    NSNumber *revisionValue = @(revision);

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSUserDefaultsDidChangeNotification
                                                  object:nil];
    [defaults setObject:progressValue forKey:key];
    [defaults setObject:revisionValue forKey:overrideKey];
    [cloudStore setObject:progressValue forKey:key];
    [cloudStore setObject:revisionValue forKey:overrideKey];
    [defaults synchronize];
    [cloudStore synchronize];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateToiCloud:)
                                                 name:NSUserDefaultsDidChangeNotification
                                               object:nil];
  }
}

+(long long) overrideRevisionForKey:(NSString*)key {
  if(![self isProgressKey:key]) {
    return 0;
  }

  NSString *overrideKey = [self overrideKeyForProgressKey:key];
  return [self progressValue:[[NSUserDefaults standardUserDefaults] objectForKey:overrideKey]];
}

+(void) updateFromiCloud:(NSNotification*) notificationObject {

  @synchronized(self) {
    [self mergeLocalAndCloudProgress];
  }

  [[NSNotificationCenter defaultCenter] postNotificationName:kMKiCloudSyncNotification object:nil];
}

+(void) startWithPrefix:(NSString*) prefixToSync {

  prefix = prefixToSync;
  NSUbiquitousKeyValueStore *iCloudStore = [NSUbiquitousKeyValueStore defaultStore];
  if(iCloudStore) {  // is iCloud enabled

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateFromiCloud:)
                                                 name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateToiCloud:)
                                                 name:NSUserDefaultsDidChangeNotification                                                    object:nil];

    // Request the latest server values after observers are ready. The
    // resulting external-change notification performs the max-value merge.
    [iCloudStore synchronize];
    [self updateToiCloud:nil];
  } else {
    DLog(@"iCloud not enabled");
  }
}

+ (void) dealloc {

  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification
                                                object:nil];

  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSUserDefaultsDidChangeNotification
                                                object:nil];
}
@end
