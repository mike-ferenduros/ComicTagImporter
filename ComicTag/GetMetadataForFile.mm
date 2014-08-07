//
//  GetMetadataForFile.m
//  ComicTag
//
//  Created by Michael Ferenduros on 06/08/2014.
//  Copyright (c) 2014 Michael Ferenduros. All rights reserved.
//

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
extern "C" {
#include "unzip.h"
}
#import "rar.hpp"
#import "raros.hpp"
#import "dll.hpp"
#import "XMLDictionary.h"

#define MD_PREFIX @"com_chunkyreader_"
static NSString *kMDComicSeries		= MD_PREFIX @"series";
static NSString *kMDComicTitle		= MD_PREFIX @"title";
static NSString *kMDComicIssue		= MD_PREFIX @"issue";
static NSString *kMDComicVolume		= MD_PREFIX @"vol";
static NSString *kMDComicWriters	= MD_PREFIX @"writers";
static NSString *kMDComicArtists	= MD_PREFIX @"artists";
static NSString *kMDComicInkers		= MD_PREFIX @"inkers";
static NSString *kMDComicLetterers	= MD_PREFIX @"letterers";
static NSString *kMDComicColorists	= MD_PREFIX @"colorists";
static NSString *kMDComicCovers		= MD_PREFIX @"coverartists";
static NSString *kMDComicEditors	= MD_PREFIX @"editors";


extern "C" {
Boolean GetMetadataForFile(void *thisInterface, CFMutableDictionaryRef attributes, CFStringRef contentTypeUTI, CFStringRef pathToFile);
}



BOOL ParseComicRack( NSData *data, NSMutableDictionary *attribs )
{
	NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;

	NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	NSDictionary *meta = [NSDictionary dictionaryWithXMLString:dataStr];
	if( !meta )
		return NO;

	BOOL didStuff = NO;

	NSString *series = [meta stringValueForKeyPath:@"Series"];
	NSString *title = [meta stringValueForKeyPath:@"Title"];
	NSString *issue = [meta stringValueForKeyPath:@"Number"];
	NSString *vol = [meta stringValueForKeyPath:@"Volume"];

	if( series )				{ didStuff = YES; attribs[kMDComicSeries] = series; }
	if( title )					{ didStuff = YES; attribs[kMDComicTitle] = title; }
	if( issue )					{ didStuff = YES; attribs[kMDComicIssue] = issue; }
	if( vol && vol.intValue )	{ didStuff = YES; attribs[kMDComicVolume] = @(vol.intValue); }

	if( series )
	{
		NSString *fullTitle = series;
		if( vol )
			fullTitle = [fullTitle stringByAppendingFormat:@" Vol %@", vol];
		if( issue )
			fullTitle = [fullTitle stringByAppendingFormat:@" #%@", issue];
		if( title )
			fullTitle = [fullTitle stringByAppendingFormat:@": %@", title];

		attribs[(__bridge NSString*)kMDItemTitle] = fullTitle;
		didStuff = YES;
	}
	else if( title )
	{
		attribs[(__bridge NSString*)kMDItemTitle] = title;
		didStuff = YES;
	}

	NSString *publisher = [meta stringValueForKeyPath:@"Publisher"];
	NSString *imprint = [meta stringValueForKeyPath:@"Imprint"];
	if( publisher || imprint )
	{
		NSArray *pubs = (publisher&&imprint) ? @[publisher,imprint] : @[publisher?:imprint];
		attribs[(__bridge NSString*)kMDItemPublishers] = pubs;
		didStuff = YES;
	}

	NSString *pageCount = [meta stringValueForKeyPath:@"PageCount"];
	if( pageCount && pageCount.intValue )
	{
		attribs[(__bridge NSString*)kMDItemNumberOfPages] = @(pageCount.intValue);
		didStuff = YES;
	}

	NSString *summary = [meta stringValueForKeyPath:@"Summary"];
	if( summary )
	{
		attribs[(__bridge NSString*)kMDItemDescription] = summary;
		didStuff = YES;
	}

	NSString *url = [meta stringValueForKeyPath:@"Web"];
	if( url )
	{
		attribs[(__bridge NSString*)kMDItemURL] = url;
		didStuff = YES;
	}

	NSDictionary *roleMap = @{
		@"Writer":		kMDComicWriters,
		@"Penciller":	kMDComicArtists,
		@"Inker":		kMDComicInkers,
		@"Letterer":	kMDComicLetterers,
		@"Colorist":	kMDComicColorists,
		@"CoverArtist":	kMDComicCovers,
		@"Editor":		kMDComicEditors
	};

	for( NSString *role in roleMap )
	{
		NSString *people = [meta stringValueForKeyPath:role];
		for( NSString *person in [people componentsSeparatedByString:@","] )
		{
			NSString *trimmed = [person stringByTrimmingCharactersInSet:whitespace];
			if( trimmed.length == 0 )
				continue;

			NSString *mdKey = roleMap[role];
			if( mdKey )
			{
				NSMutableArray *specialists = attribs[mdKey];
				if( !specialists )
					attribs[mdKey] = specialists = [NSMutableArray array];

				if( ![specialists containsObject:trimmed] )
					[specialists addObject:trimmed];
			}

			NSString *authorKey = (__bridge NSString*)kMDItemAuthors;//(mdKey && [@[@"com_chunkyreader_writers",@"com_chunkyreader_artists"] containsObject:mdKey]) ? (__bridge NSString*)kMDItemAuthors : (__bridge NSString*)kMDItemContributors;
			NSMutableArray *authors = attribs[authorKey];
			if( ![authors isKindOfClass:[NSMutableArray class]] )
				attribs[authorKey] = authors = [NSMutableArray array];

			if( ![authors containsObject:trimmed] )
				[authors addObject:trimmed];

			didStuff = YES;
		}
	}

	NSString *year = [meta stringValueForKeyPath:@"Year"];
	NSString *month = [meta stringValueForKeyPath:@"Month"];
	NSString *day = [meta stringValueForKeyPath:@"Day"];
	if( year && month )
	{
		int y = year.intValue;
		int m = month.intValue;
		int d = (day ?: @"1").intValue;
		if( y && m )
		{
			NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
			cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
			NSDate *pubDate = [cal dateWithEra:1 year:y month:m day:d hour:12 minute:0 second:0 nanosecond:0];
			if( pubDate )
			{
				attribs[(__bridge NSString*)kMDItemContentCreationDate] = pubDate;
				didStuff = YES;
			}
		}
	}

	return didStuff;
}

BOOL ParseCBI( NSData *data, NSMutableDictionary *attribs )
{
	NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;

	NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:0];
	if( !root )
		return NO;

	NSDictionary *meta = [root dictionaryValueForKeyPath:@"ComicBookInfo/1.0"];
	if( !meta )
		return NO;
		
	BOOL didStuff = NO;

	NSString *series = [meta stringValueForKeyPath:@"series"];
	NSString *title = [meta stringValueForKeyPath:@"title"];
	NSString *issue = [meta stringValueForKeyPath:@"issue"];
	NSString *vol = [meta stringValueForKeyPath:@"volume"];

	if( series )				attribs[kMDComicSeries] = series;
	if( title )					attribs[kMDComicTitle] = title;
	if( issue )					attribs[kMDComicIssue] = issue;
	if( vol && vol.intValue )	attribs[kMDComicVolume] = @(vol.intValue);

	if( series )
	{
		NSString *fullTitle = series;
		if( vol )
			fullTitle = [fullTitle stringByAppendingFormat:@" Vol %@", vol];
		if( issue )
			fullTitle = [fullTitle stringByAppendingFormat:@" #%@", issue];
		if( title )
			fullTitle = [fullTitle stringByAppendingFormat:@": %@", title];

		attribs[(__bridge NSString*)kMDItemTitle] = fullTitle;
		didStuff = YES;
	}
	else if( title )
	{
		attribs[(__bridge NSString*)kMDItemTitle] = title;
		didStuff = YES;
	}


	NSString *publisher = [meta stringValueForKeyPath:@"publisher"];
	if( publisher )
	{
		attribs[(__bridge NSString*)kMDItemPublishers] = publisher;
		didStuff = YES;
	}

	NSString *comments = [meta stringValueForKeyPath:@"comments"];
	if( comments )
	{
		attribs[(__bridge NSString*)kMDItemDescription] = comments;
		didStuff = YES;
	}


	NSString *year = [meta stringValueForKeyPath:@"publicationYear"];
	NSString *month = [meta stringValueForKeyPath:@"publicationMonth"];
	if( year && month )
	{
		int y = year.intValue;
		int m = month.intValue;
		if( y && m )
		{
			NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
			cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
			NSDate *pubDate = [cal dateWithEra:1 year:y month:m day:1 hour:12 minute:0 second:0 nanosecond:0];
			if( pubDate )
			{
				attribs[(__bridge NSString*)kMDItemContentCreationDate] = pubDate;
				didStuff = YES;
			}
		}
	}

	NSArray *credits = [meta arrayValueForKeyPath:@"credits"];
	if( credits )
	{
		NSDictionary *roleMap = @{
			@"writer":		kMDComicWriters,
			@"plotter":		kMDComicWriters,
			@"scripter":	kMDComicWriters,
			@"painter":		kMDComicArtists,
			@"artist":		kMDComicArtists,
			@"inker":		kMDComicInkers,
			@"finishes":	kMDComicInkers,
			@"colorist":	kMDComicColorists,
			@"colourist":	kMDComicColorists,
			@"colorer":		kMDComicColorists,
			@"colourer":	kMDComicColorists,
			@"penciler":	kMDComicArtists,
			@"penciller":	kMDComicArtists,
			@"breakdowns":	kMDComicArtists,
			@"cover":		kMDComicCovers,
			@"covers":		kMDComicCovers,
			@"coverartist":	kMDComicCovers,
			@"cover artist":kMDComicCovers,
			@"letterer":	kMDComicLetterers
		};

		for( NSDictionary *credit in credits )
		{
			if( ![credit isKindOfClass:[NSDictionary class]] )
				continue;

			NSString *name = [credit stringValueForKeyPath:@"person"];
			NSString *role = [credit stringValueForKeyPath:@"role"];
			if( !name || !role )
				continue;

			NSString *trimmed = [name stringByTrimmingCharactersInSet:whitespace];
			if( trimmed.length == 0 )
				continue;

			NSString *mdKey = roleMap[role.lowercaseString];
			if( mdKey )
			{
				NSMutableArray *specialists = attribs[mdKey];
				if( !specialists )
					attribs[mdKey] = specialists = [NSMutableArray array];

				if( ![specialists containsObject:trimmed] )
					[specialists addObject:trimmed];
			}

			NSString *authorKey = (__bridge NSString*)kMDItemAuthors;//(mdKey && [@[@"com_chunkyreader_writers",@"com_chunkyreader_artists"] containsObject:mdKey]) ? (__bridge NSString*)kMDItemAuthors : (__bridge NSString*)kMDItemContributors;

			NSMutableArray *authors = attribs[authorKey];
			if( ![authors isKindOfClass:[NSMutableArray class]] )
				attribs[authorKey] = authors = [NSMutableArray array];
			
			if( ![authors containsObject:trimmed] )
				[authors addObject:trimmed];

			didStuff = YES;
		}
	}

	return didStuff;
}



int GetMetadataForZip( NSString *path, NSMutableDictionary *attribs )
{
	unzFile unz = unzOpen( path.UTF8String );
	if( !unz )
		return -1;

	BOOL gotOne = NO;

	//Look for comicinfo.xml first
	if( unzGoToFirstFile(unz) == UNZ_OK )
	{
		NSMutableData *fname = [[NSMutableData alloc] initWithLength:4096];
		do
		{
			unz_file_info64 info;
			if( unzGetCurrentFileInfo64( unz, &info, (char*)fname.mutableBytes, fname.length, 0, 0, 0, 0 ) == UNZ_OK )
			{
				if( strcasecmp((const char*)fname.bytes,"ComicInfo.xml")==0 && info.uncompressed_size<1024*1024 )
				{
					NSMutableData *data = [[NSMutableData alloc] initWithLength:info.uncompressed_size];
					if( unzOpenCurrentFile(unz) == UNZ_OK )
					{
						if( unzReadCurrentFile( unz, data.mutableBytes, (unsigned)data.length ) == info.uncompressed_size )
							gotOne = ParseComicRack( data, attribs );

						unzCloseCurrentFile( unz );
					}
				}
			}
		}
		while( !gotOne && unzGoToNextFile(unz)==UNZ_OK );
	}

	//If no ComicRack, check for CBL
	if( !gotOne )
	{
		unz_global_info64 ginfo;
		if( unzGetGlobalInfo64(unz,&ginfo) == UNZ_OK )
		{
			if( ginfo.size_comment > 0 )
			{
				NSMutableData *comment = [[NSMutableData alloc] initWithLength:ginfo.size_comment];
				if( unzGetGlobalComment(unz,(char*)comment.mutableBytes,comment.length) == comment.length )
				{
					gotOne = ParseCBI( comment, attribs );
				}
			}
		}
	}

	unzClose( unz );
	return gotOne ? 1 : 0;
}



static int CALLBACK rar_data_write(UINT msg, long UserData, long P1, long P2)
{
	if( msg == UCM_PROCESSDATA )
	{
		CFMutableDataRef data = (CFMutableDataRef)UserData;
		CFDataAppendBytes( data, (UInt8 *)P1, P2 );
	}
	return 0;
}

int GetMetadataForRar( NSString *path, NSMutableDictionary *attribs )
{
	RAROpenArchiveDataEx flags;
	bzero( &flags, sizeof(flags) );
	flags.ArcName = (char*)path.UTF8String;
	flags.OpenMode = RAR_OM_EXTRACT;

	NSMutableData *comment = [[NSMutableData alloc] initWithLength:65536];
	flags.CmtBufSize = (unsigned int)comment.length;
	flags.CmtBuf = (char*)comment.mutableBytes;

	NSMutableData *data = nil;

	HANDLE rar = RAROpenArchiveEx( &flags );
	if( !rar )
		return -1;

	if( flags.OpenResult != 0 )
	{
		RARCloseArchive( rar );
		return -1;
	}

	RARHeaderDataEx *header = new RARHeaderDataEx;
	bzero( header, sizeof(*header) );

	size_t length = 0;
	while( RARReadHeaderEx(rar,header) == 0 )
	{
		if( strcasecmp(header->FileName,"comicinfo.xml") == 0 )
		{
			length = header->UnpSize;
			break;
		}
		else
		{
			if( RARProcessFile(rar,RAR_SKIP,0,0) != 0 )
				break;
		}
	}

	delete header;

	BOOL gotOne = NO;

	if( length > 0 && length < 1024*1024 )
	{
		data = [NSMutableData dataWithCapacity:length];

		RARSetCallback( rar, rar_data_write, (long)data );
		RARProcessFile( rar, RAR_TEST, 0, 0 );

		if( data.length == length )
		{
			gotOne = ParseComicRack( data, attribs );
		}
	}

	if( !gotOne && flags.CmtSize>1 )
	{
		//Truncate data blob to actual size read, minus NULL terminator
		comment.length = flags.CmtSize-1;
		gotOne = ParseCBI( comment, attribs );
	}

	RARCloseArchive( rar );
	return gotOne ? 1 : 0;
}





Boolean GetMetadataForFile(void *thisInterface, CFMutableDictionaryRef attributes, CFStringRef contentTypeUTI, CFStringRef pathToFile)
{
    @autoreleasepool
	{
		NSMutableDictionary *attribs = (__bridge NSMutableDictionary*)attributes;
		NSString *path = (__bridge NSString*)pathToFile;

		//Always try both zip + rar regardless of UTI, since files are often misnamed

		if( [@[@"cbr",@"rar"] containsObject:path.pathExtension.lowercaseString] )
		{
			switch( GetMetadataForRar(path,attribs) )
			{
				case 1:		return YES;
				case 0:		return NO;
				default:	return GetMetadataForZip(path,attribs)==1;
			}
		}
		else
		{
			switch( GetMetadataForZip(path,attribs) )
			{
				case 1:		return YES;
				case 0:		return NO;
				default:	return GetMetadataForRar(path,attribs)==1;
			}
		}
    }
}
