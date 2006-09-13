//
//  GetMetadataForFile.m
//  DjVu
//
//  Created by Jeff Sickel on 9/6/06.
//  Copyright (c) 2006 Corpus Callosum Corporation. All rights reserved.
//

#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h> 

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#include "libdjvu/miniexp.h"
// #define miniexp_t mminiexp_t
#include "libdjvu/ddjvuapi.h"

ddjvu_context_t *ctx;
ddjvu_document_t *doc;

void
handle(int wait)
{
    const ddjvu_message_t *msg;
    if (!ctx)
        return;
    if (wait)
        msg = ddjvu_message_wait(ctx);
    while ((msg = ddjvu_message_peek(ctx)))
    {
        switch(msg->m_any.tag)
        {
            case DDJVU_ERROR:
                NSLog(@"%s", msg->m_error.message);
                if (msg->m_error.filename)
                    NSLog(@"'%s:%d'",
                            msg->m_error.filename, msg->m_error.lineno);
                    // pop();
                break; // never gets here
            default:
                break;
        }
        ddjvu_message_pop(ctx);
    }
}

/*
void
die(fmt, ...)
{
    handle(FALSE);
    va_list args;
    va_start(args, fmt);
    NSLogv(fmt, args);
    va_end(args);
    goto pop; // exit (10)
}
*/

#pragma mark -
void
mdprint(NSMutableString *str, miniexp_t r)
{
    if (miniexp_consp(r)) {
        while (miniexp_consp(r)) {
            mdprint(str, miniexp_car(r));  
            r = miniexp_cdr(r);
        }
    } else if (miniexp_stringp(r)) {
        [str appendFormat:@" %s", miniexp_to_str(r)];
    }
}

void
mdfprint(FILE *str, miniexp_t r)
{
    if (miniexp_consp(r)) {
        while (miniexp_consp(r)) {
            mdfprint(str, miniexp_car(r));  
            r = miniexp_cdr(r);
        }
    } else if (miniexp_stringp(r)) {
        fprintf(str, " %s", miniexp_to_str(r));
    }
}


#pragma mark -
/* -----------------------------------------------------------------------------
    Get metadata attributes from file
   
   This function's job is to extract useful information your file format supports
   and return it as a dictionary
   ----------------------------------------------------------------------------- */

Boolean GetMetadataForFile(void* thisInterface, 
			   CFMutableDictionaryRef attributes, 
			   CFStringRef contentTypeUTI,
			   CFStringRef pathToFile)
{
    Boolean result = NO;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSProcessInfo *pinfo = [NSProcessInfo processInfo];
    NSString *path = (NSString *)pathToFile;
    NSMutableDictionary *dictionary = (NSMutableDictionary *)attributes;
    int npages;
    miniexp_t expr;
    
    if (! (ctx = ddjvu_context_create([[pinfo processName] cStringUsingEncoding:NSASCIIStringEncoding]))) {
        NSLog(@"Cannot create djvu conext for '%@'.", path);
        goto pop;
    }
    if (! (doc = ddjvu_document_create_by_filename(ctx, [path cStringUsingEncoding:NSASCIIStringEncoding], TRUE))) {
        NSLog(@"Cannot open djvu document '%@'.", path);
        goto pop;
    }

    while (! ddjvu_document_decoding_done(doc))
        handle(TRUE);
            
    /* Pull any available metadata from the file at the specified path */
    /* Return the attribute keys and attribute values in the dict */
    /* Return TRUE if successful, FALSE if there was no data provided */
    
    npages = ddjvu_document_get_pagenum(doc);
    if (npages) {
        int i;
        ddjvu_status_t r;
        ddjvu_pageinfo_t info;
        double f = 1.0;
        NSMutableString *buf = [NSMutableString string];
        
        for (i=0; i<npages; i++) {
            while ((expr=ddjvu_document_get_pagetext(doc,i,"page")) == miniexp_dummy)
                handle(TRUE);
            if (expr)
                mdprint(buf, expr);
        }
        
        if ([buf length])
            [dictionary setObject:buf forKey:(NSString *)kMDItemTextContent];            
        
        // this could be public.djvu or org.djvulibre.djvu
        // but we still need to pick up the files from com.lizardtech.djvu
        [dictionary setObject:@"com.lizardtech.djvu" forKey:(NSString *)kMDItemContentType];

        while ((r = ddjvu_document_get_pageinfo(doc, 0, &info)) < DDJVU_JOB_OK)
            handle(TRUE);
        if (r >= DDJVU_JOB_FAILED)
            goto pop;
        
        f = 72.0 / (double)info.dpi;
        
#define DjAddIntKey(n,k) \
        [dictionary setObject:[NSNumber numberWithInt:n] forKey:(NSString *)k]
            
        DjAddIntKey(npages, kMDItemNumberOfPages);
        DjAddIntKey(info.height, kMDItemPixelHeight);
        DjAddIntKey(info.width, kMDItemPixelWidth);
        DjAddIntKey((int)(f * info.height), kMDItemPageHeight);
        DjAddIntKey((int)(f * info.width), kMDItemPageWidth);
        
        [dictionary setObject:[NSString stringWithFormat:@"%d", info.version] 
                       forKey:(NSString *)kMDItemVersion];
        
        /** Image orientation:
            0: no rotation      1: 90 degrees counter-clockwise
            2: 180 degrees      3: 270 degrees counter-clockwise
            trying to map to kMDItemOrientation:
            Values are 0 is "Landscape" or 1 is "Portrait"
        */
        DjAddIntKey(!(info.rotation), kMDItemOrientation);
        
        // implement in next release ---
        // kMDItemDescription
        // kMDItemCodecs ??
        
        result = YES;
    }
    
pop:
    if (doc)
        ddjvu_document_release(doc);
    if (ctx)
        ddjvu_context_release(ctx);
        
    [pool release];
    
    return result;
}