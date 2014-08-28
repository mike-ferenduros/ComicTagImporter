//
//  GetMetadataForFile.m
//  ComicTag
//
//  Created by Michael Ferenduros on 06/08/2014.
//  Copyright (c) 2014 Michael Ferenduros. All rights reserved.
//

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import "NSDictionary+safety.h"
#import "JSONKit.h"

extern "C" {
#include "unzip.h"
}
#import "rar.hpp"
#import "raros.hpp"
#import "dll.hpp"

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



@interface CrackParser : NSObject <NSXMLParserDelegate>
{
	int depth;
	NSMutableDictionary *contents;
	NSString *elem;
}
- (NSDictionary*)contents;
@end

@implementation CrackParser
- (NSDictionary*)contents { return contents; }
- (void)dealloc
{
	[contents release];
	[elem release];
	[super dealloc];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	depth++;

	if( depth == 1 )
	{
		if( ![elementName.lowercaseString isEqualToString:@"comicinfo"] )
			[parser abortParsing];

		contents = contents ?: [[NSMutableDictionary alloc] init];
	}
	else if( depth == 2 )
	{
		elem = [elementName retain];
	}
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	if( depth == 2 )
	{
		[elem release];
		elem = nil;
	}
	depth--;
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	if( depth==2 && elem )
	{
		NSString *existing = [contents valueForKey:elem];
		if( existing )
			string = [@[existing,string] componentsJoinedByString:@" "];
		[contents setValue:string forKey:elem];
	}
}
@end




BOOL ParseComicRack( NSData *data, NSMutableDictionary *attribs )
{
	NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;

	NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
	CrackParser *cparser = [[CrackParser alloc] init];
	parser.delegate = cparser;
	BOOL ok = [parser parse];

	NSDictionary *meta = ok ? [cparser.contents retain] : nil;

	[cparser release];
	[parser release];

	if( !meta )
		return NO;

	BOOL didStuff = NO;

	NSString *series = [meta stringValueForKeyPath:@"Series"];
	NSString *title = [meta stringValueForKeyPath:@"Title"];
	NSString *issue = [meta stringValueForKeyPath:@"Number"];
	NSString *vol = [meta stringValueForKeyPath:@"Volume"];

	if( series )				{ didStuff = YES; [attribs setValue:series forKey:kMDComicSeries]; }
	if( title )					{ didStuff = YES; [attribs setValue:title forKey:kMDComicTitle]; }
	if( issue )					{ didStuff = YES; [attribs setValue:issue forKey:kMDComicIssue]; }
	if( vol && vol.intValue )	{ didStuff = YES; [attribs setValue:[NSNumber numberWithInt:vol.intValue] forKey:kMDComicVolume]; }

	if( series )
	{
		NSString *fullTitle = series;
		if( vol )
			fullTitle = [fullTitle stringByAppendingFormat:@" Vol %@", vol];
		if( issue )
			fullTitle = [fullTitle stringByAppendingFormat:@" #%@", issue];
		if( title )
			fullTitle = [fullTitle stringByAppendingFormat:@": %@", title];

		[attribs setValue:fullTitle forKey:(__bridge NSString*)kMDItemTitle];
		didStuff = YES;
	}
	else if( title )
	{
		[attribs setValue:title forKey:(__bridge NSString*)kMDItemTitle];
		didStuff = YES;
	}

	NSString *publisher = [meta stringValueForKeyPath:@"Publisher"];
	NSString *imprint = [meta stringValueForKeyPath:@"Imprint"];
	if( publisher || imprint )
	{
		NSArray *pubs = (publisher&&imprint) ? [NSArray arrayWithObjects:publisher,imprint,nil] : [NSArray arrayWithObject:publisher?:imprint];
		[attribs setValue:pubs forKey:(__bridge NSString*)kMDItemPublishers];
		didStuff = YES;
	}

	NSString *pageCount = [meta stringValueForKeyPath:@"PageCount"];
	if( pageCount && pageCount.intValue )
	{
		NSNumber *pc = [NSNumber numberWithInt:pageCount.intValue];
		[attribs setValue:pc forKey:(__bridge NSString*)kMDItemNumberOfPages];
		didStuff = YES;
	}

	NSString *summary = [meta stringValueForKeyPath:@"Summary"];
	if( summary )
	{
		[attribs setValue:summary forKey:(__bridge NSString*)kMDItemDescription];
		didStuff = YES;
	}

	NSString *url = [meta stringValueForKeyPath:@"Web"];
	if( url )
	{
		[attribs setValue:url forKey:(__bridge NSString*)kMDItemURL];
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

			NSString *mdKey = [roleMap valueForKey:role];
			if( mdKey )
			{
				NSMutableArray *specialists = [attribs valueForKey:mdKey];
				if( !specialists )
				{
					specialists = [NSMutableArray array];
					[attribs setValue:specialists forKey:mdKey];
				}

				if( ![specialists containsObject:trimmed] )
					[specialists addObject:trimmed];
			}

			NSString *authorKey = (__bridge NSString*)kMDItemAuthors;//(mdKey && [@[@"com_chunkyreader_writers",@"com_chunkyreader_artists"] containsObject:mdKey]) ? (__bridge NSString*)kMDItemAuthors : (__bridge NSString*)kMDItemContributors;
			NSMutableArray *authors = [attribs valueForKey:authorKey];
			if( ![authors isKindOfClass:[NSMutableArray class]] )
			{
				authors = [NSMutableArray array];
				[attribs setValue:authors forKey:authorKey];
			}

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
			NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
			cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
			NSDateComponents *balls = [[NSDateComponents alloc] init];
			balls.era = 1;
			balls.year = y;
			balls.month = m;
			balls.day = d;
			balls.hour = 12;
			NSDate *pubDate = [cal dateFromComponents:balls];
			if( pubDate )
			{
				[attribs setValue:pubDate forKey:(__bridge NSString*)kMDItemContentCreationDate];
				didStuff = YES;
			}
			[cal release];
		}
	}

	[meta release];
	return didStuff;
}

BOOL ParseCBI( NSData *data, NSMutableDictionary *attribs )
{
	NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;

	NSDictionary *root = [data objectFromJSONData];
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

	if( series )				[attribs setValue:series forKey:kMDComicSeries];
	if( title )					[attribs setValue:title forKey:kMDComicTitle];
	if( issue )					[attribs setValue:issue forKey:kMDComicIssue];
	if( vol && vol.intValue )	[attribs setValue:@(vol.intValue) forKey:kMDComicVolume];

	if( series )
	{
		NSString *fullTitle = series;
		if( vol )
			fullTitle = [fullTitle stringByAppendingFormat:@" Vol %@", vol];
		if( issue )
			fullTitle = [fullTitle stringByAppendingFormat:@" #%@", issue];
		if( title )
			fullTitle = [fullTitle stringByAppendingFormat:@": %@", title];

		[attribs setValue:fullTitle forKey:(__bridge NSString*)kMDItemTitle];
		didStuff = YES;
	}
	else if( title )
	{
		[attribs setValue:title forKey:(__bridge NSString*)kMDItemTitle];
		didStuff = YES;
	}


	NSString *publisher = [meta stringValueForKeyPath:@"publisher"];
	if( publisher )
	{
		[attribs setValue:publisher forKey:(__bridge NSString*)kMDItemPublishers];
		didStuff = YES;
	}

	NSString *comments = [meta stringValueForKeyPath:@"comments"];
	if( comments )
	{
		[attribs setValue:comments forKey:(__bridge NSString*)kMDItemDescription];
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
			NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
			cal.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
			NSDateComponents *balls = [[NSDateComponents alloc] init];
			balls.era = 1;
			balls.year = y;
			balls.month = m;
			balls.day = 1;
			balls.hour = 12;
			NSDate *pubDate = [cal dateFromComponents:balls];
			if( pubDate )
			{
				[attribs setValue:pubDate forKey:(__bridge NSString*)kMDItemContentCreationDate];
				didStuff = YES;
			}
			[cal release];
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

			NSString *mdKey = [roleMap valueForKey:role.lowercaseString];
			if( mdKey )
			{
				NSMutableArray *specialists = [attribs valueForKey:mdKey];
				{
					specialists = [NSMutableArray array];
					[attribs setValue:specialists forKey:mdKey];
				}

				if( ![specialists containsObject:trimmed] )
					[specialists addObject:trimmed];
			}

			NSString *authorKey = (__bridge NSString*)kMDItemAuthors;//(mdKey && [@[@"com_chunkyreader_writers",@"com_chunkyreader_artists"] containsObject:mdKey]) ? (__bridge NSString*)kMDItemAuthors : (__bridge NSString*)kMDItemContributors;

			NSMutableArray *authors = [attribs valueForKey:authorKey];
			if( ![authors isKindOfClass:[NSMutableArray class]] )
			{
				authors = [NSMutableArray array];
				[attribs setValue:authors forKey:authorKey];
			}

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
					NSMutableData *data = [[NSMutableData alloc] initWithLength:(NSUInteger)info.uncompressed_size];
					if( unzOpenCurrentFile(unz) == UNZ_OK )
					{
						if( unzReadCurrentFile( unz, data.mutableBytes, (unsigned)data.length ) == info.uncompressed_size )
							gotOne = ParseComicRack( data, attribs );

						unzCloseCurrentFile( unz );
					}
					[data release];
				}
			}
		}
		while( !gotOne && unzGoToNextFile(unz)==UNZ_OK );
		[fname release];
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
				[comment release];
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

	NSMutableData *comment = [NSMutableData dataWithLength:65536];
	flags.CmtBufSize = (unsigned int)comment.length;
	flags.CmtBuf = (char*)comment.mutableBytes;

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
		NSMutableData *data = [[NSMutableData alloc] initWithCapacity:length];

		RARSetCallback( rar, rar_data_write, (long)data );
		RARProcessFile( rar, RAR_TEST, 0, 0 );

		if( data.length == length )
		{
			gotOne = ParseComicRack( data, attribs );
		}
		[data release];
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
