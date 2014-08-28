//
//  NSDictionary+safety.h
//  ComicTag
//
//  Created by Michael Ferenduros on 29/08/2014.
//  Copyright (c) 2014 Michael Ferenduros. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDictionary (safety)

- (NSString*)stringValueForKeyPath:(id)keyPath;
- (NSDictionary*)dictionaryValueForKeyPath:(id)keyPath;
- (NSArray*)arrayValueForKeyPath:(id)keyPath;

@end
