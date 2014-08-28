//
//  NSDictionary+safety.m
//  ComicTag
//
//  Created by Michael Ferenduros on 29/08/2014.
//  Copyright (c) 2014 Michael Ferenduros. All rights reserved.
//

#import "NSDictionary+safety.h"

@implementation NSDictionary (safety)

- (NSString*)stringValueForKeyPath:(id)keyPath
{
	id val = [self valueForKeyPath:keyPath];
	if( [val isKindOfClass:[NSString class]] )
		return val;
	else if( [val isKindOfClass:[NSNumber class]] )
		return ((NSNumber*)val).stringValue;
	else
		return nil;
}
- (NSDictionary*)dictionaryValueForKeyPath:(id)keyPath
{
	id val = [self valueForKeyPath:keyPath];
	return [val isKindOfClass:[NSDictionary class]] ? val : nil;
}
- (NSArray*)arrayValueForKeyPath:(id)keyPath
{
	id val = [self valueForKeyPath:keyPath];
	return [val isKindOfClass:[NSArray class]] ? val : nil;
}

@end
