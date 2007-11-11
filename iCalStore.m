#import <Foundation/Foundation.h>
#import <GNUstepBase/GSXML.h>
#import "Event.h"
#import "Task.h"
#import "iCalStore.h"
#import "defines.h"

@implementation iCalStoreDialog
- (id)initWithName:(NSString *)storeName
{
  self = [super init];
  if (self) {
    if (![NSBundle loadNibNamed:@"iCalendar" owner:self])
      return nil;
    [warning setHidden:YES];
    [name setStringValue:storeName];
    [url setStringValue:@"http://"];
  }
  return self;
}

- (void)dealloc
{
  [panel close];
}

- (BOOL)show
{
  [ok setEnabled:NO];
  return [NSApp runModalForWindow:panel];
}

- (void)okClicked:(id)sender
{
  [NSApp stopModalWithCode:1];
}

- (void)cancelClicked:(id)sender
{
  [NSApp stopModalWithCode:0];
}

- (void)setError:(NSString *)errorText
{
  [error setStringValue:errorText];
  [warning setHidden:NO];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
  NSURL *storeUrl = [NSURL URLWithString:[url stringValue]];
  [ok setEnabled:(storeUrl != nil)];
}

- (NSString *)url
{
  return [url stringValue];
}
@end


@implementation iCalStore

- (GSXMLNode *)getLastModifiedElement:(GSXMLNode *)node
{
  GSXMLNode *inter;

  while (node) {
    if ([node type] == [GSXMLNode typeFromDescription:@"XML_ELEMENT_NODE"] && 
	[@"getlastmodified" isEqualToString:[node name]])
      return node;
    if ([node firstChild]) {
      inter = [self getLastModifiedElement:[node firstChild]];
      if (inter)
	return inter;
    }
    node = [node next];
  }
  return nil;
}

- (NSDate *)getLastModified
{
  GSXMLParser *parser;
  GSXMLNode *node;
  NSDate *date;
  NSData *data;

  [_url setProperty:@"PROPFIND" forKey:GSHTTPPropertyMethodKey];
  data = [_url resourceDataUsingCache:NO];
  [_url setProperty:@"GET" forKey:GSHTTPPropertyMethodKey];
  if (data) {
    parser = [GSXMLParser parserWithData:data];
    if ([parser parse]) {
      node = [self getLastModifiedElement:[[parser document] root]];
      date = [NSDate dateWithNaturalLanguageString:[node content]];
      return date;
    }
  }
  return nil;
}

- (BOOL)needsRefresh
{
  NSDate *lm = [self getLastModified];

  if (!_lastModified) {
    if (lm)
      _lastModified = [lm copy];
    return YES;
  }
  if (!lm)
    return YES;
  if ([_lastModified compare:lm] == NSOrderedAscending) {
    [_lastModified release];
    _lastModified = [lm copy];
    return YES;
  }
  return NO;
}

- (NSDictionary *)defaults
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
			 [NSArchiver archivedDataWithRootObject:[NSColor blueColor]], ST_COLOR,
			 [NSArchiver archivedDataWithRootObject:[NSColor darkGrayColor]], ST_TEXT_COLOR,
		       [NSNumber numberWithBool:NO], ST_RW,
		       [NSNumber numberWithBool:YES], ST_DISPLAY,
		       nil, nil];
}

+ (NSURL *)getRealURL:(NSURL *)url
{
  NSString *location;

  location = [url propertyForKey:@"Location"];
  if (location) {
    NSLog(@"Redirected to %@", location);
    return [iCalStore getRealURL:[NSURL URLWithString:location]];
  }
  return url;
}

+ (BOOL)canReadFromURL:(NSURL *)url
{
  if ([url resourceDataUsingCache:NO] == nil)
      return NO;
  return YES;
}

/* This is destructive : it writes an empty file */
+ (BOOL)canWriteToURL:(NSURL *)url
{
  BOOL ret;

  [url setProperty:@"PUT" forKey:GSHTTPPropertyMethodKey];
  ret = [url setResourceData:[NSData data]];
  [url setProperty:@"GET" forKey:GSHTTPPropertyMethodKey];
  if (ret)
    return YES;
  return NO;
}

- (void)fetchData
{
  _retrievedData = [[NSMutableData alloc] initWithCapacity:16384];
  [_url loadResourceDataNotifyingClient:self usingCache:NO]; 
}

- (id)initWithName:(NSString *)name
{
  self = [super init];
  if (self) {
    _tree = [iCalTree new];
    _config = [[ConfigManager alloc] initForKey:name withParent:nil];
    [_config registerDefaults:[self defaults]];
    _url = [iCalStore getRealURL:[NSURL URLWithString:[_config objectForKey:ST_URL]]];
    if (_url == nil) {
      NSLog(@"%@ isn't a valid url", [_config objectForKey:ST_URL]);
      [self release];
      return nil;
    }
    [_url retain];
    _name = [name copy];
    _modified = NO;
    _retrievedData = nil;
    _lastModified = nil;
    _writable = [[_config objectForKey:ST_RW] boolValue];
    _displayed = [[_config objectForKey:ST_DISPLAY] boolValue];
    _data = [[NSMutableDictionary alloc] initWithCapacity:32];
    _tasks = [[NSMutableDictionary alloc] initWithCapacity:32];
    [self fetchData]; 

    if ([_config objectForKey:ST_REFRESH])
      _minutesBeforeRefresh = [_config integerForKey:ST_REFRESH];
    else
      _minutesBeforeRefresh = 60;
    _refreshTimer = [[NSTimer alloc] initWithFireDate:nil
				     interval:_minutesBeforeRefresh * 60
				     target:self selector:@selector(refreshData:) 
				     userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_refreshTimer forMode:NSDefaultRunLoopMode];
  }
  return self;
}

+ (id)storeNamed:(NSString *)name
{
  return AUTORELEASE([[self allocWithZone: NSDefaultMallocZone()] initWithName:name]);
}

+ (BOOL)registerWithName:(NSString *)name
{
  ConfigManager *cm;
  iCalStoreDialog *dialog;
  NSURL *storeURL;
  BOOL writable = NO;

  dialog = [[iCalStoreDialog alloc] initWithName:name];
 error:
  if ([dialog show] == YES) {
    storeURL = [iCalStore getRealURL:[NSURL URLWithString:[dialog url]]];
    /* If there's no file there */
    if ([iCalStore canReadFromURL:storeURL] == NO) {
      /* Try to write one */
      if ([iCalStore canWriteToURL:storeURL] == NO) {
	[dialog setError:@"Unable to read or write at this url"];
	goto error;
      }
      writable = YES;
    }
    [dialog release];
    cm = [[ConfigManager alloc] initForKey:[name copy] withParent:nil];
    [cm setObject:[storeURL description] forKey:ST_URL];
    [cm setObject:[[self class] description] forKey:ST_CLASS];
    [cm setObject:[NSNumber numberWithBool:writable] forKey:ST_RW];
    return YES;
  }
  [dialog release];
  return NO;
}

+ (NSString *)storeTypeName
{
  return @"iCalendar store";
}

- (void)dealloc
{
  [_refreshTimer invalidate];
  [self write];
  [_data release];
  [_tasks release];
  [_url release];
  [_config release];
  [_name release];
  [_lastModified release];
  [_tree release];
  [super dealloc];
}

- (void)refreshData:(NSTimer *)timer
{
  [self read];
}

- (NSEnumerator *)enumerator
{
  return [_data objectEnumerator];
}

- (NSArray *)events
{
  return [_data allValues];
}
- (NSArray *)tasks
{
  return [_tasks allValues];
}

- (void)addEvent:(Event *)evt
{
  if ([_tree add:evt]) {
    [evt setStore:self];
    [_data setValue:evt forKey:[evt UID]];
    _modified = YES;
    if (![_url isFileURL])
      [self write];
    [[NSNotificationCenter defaultCenter] postNotificationName:SADataChangedInStore object:self];
  }
}
- (void)addTask:(Task *)task
{
  if ([_tree add:task]) {
    [task setStore:self];
    [_tasks setValue:task forKey:[task UID]];
    _modified = YES;
    if (![_url isFileURL])
      [self write];
    [[NSNotificationCenter defaultCenter] postNotificationName:SADataChangedInStore object:self];
  }
}

/*
 * FIXME : we should probably write asynchronously on
 * every change or every x minutes.
 * Do we need to read before writing ?
 */
- (void)remove:(Element *)elt
{
  if ([_tree remove:[_data objectForKey:[elt UID]]]) {
    [_data removeObjectForKey:[elt UID]];
    _modified = YES;
    if (![_url isFileURL])
      [self write];
    [[NSNotificationCenter defaultCenter] postNotificationName:SADataChangedInStore object:self];
  }
}

- (void)update:(Element *)elt
{
  if ([_tree update:(Event *)elt]) {
    [elt setStore:self];
    if ([elt isKindOfClass:[Event class]]) {
      [_data removeObjectForKey:[elt UID]];
      [_data setValue:elt forKey:[elt UID]];
    } else {
      [_tasks removeObjectForKey:[elt UID]];
      [_tasks setValue:elt forKey:[elt UID]];
    }
    _modified = YES;
    if (![_url isFileURL])
      [self write];
    [[NSNotificationCenter defaultCenter] postNotificationName:SADataChangedInStore object:self];
  }
}

- (BOOL)contains:(Element *)elt
{
  if ([elt isKindOfClass:[Event class]])
    return [_data objectForKey:[elt UID]] != nil;
  return [_tasks objectForKey:[elt UID]] != nil;
}

- (BOOL)isWritable
{
  return _writable;
}

- (void)setIsWritable:(BOOL)writable
{
  _writable = writable;
  [_config setObject:[NSNumber numberWithBool:_writable] forKey:ST_RW];
}

- (BOOL)modified
{
  return _modified;
}

- (BOOL)read
{
  if ([self needsRefresh]) {
    [self fetchData];
    return YES;
  }
  return NO;
}

- (BOOL)write
{
  NSData *data;

  if ([self isWritable] && data) {
    [_url setProperty:@"PUT" forKey:GSHTTPPropertyMethodKey];
    data = [[_tree iCalTreeAsString] dataUsingEncoding:NSUTF8StringEncoding];  
    if ([_url setResourceData:data]) {
      [_url setProperty:@"GET" forKey:GSHTTPPropertyMethodKey];
      NSLog(@"iCalStore written to %@", [_url absoluteString]);
      _modified = NO;
      return YES;
    }
    [_url setProperty:@"GET" forKey:GSHTTPPropertyMethodKey];
    NSLog(@"Unable to write to %@, make this store read only", [_url absoluteString]);
    [self setIsWritable:NO];
    return NO;
  }
  return YES;
}

- (NSString *)description
{
  return _name;
}

- (NSColor *)eventColor
{
  NSData *theData =[_config objectForKey:ST_COLOR];
  return [NSUnarchiver unarchiveObjectWithData:theData];
}

- (void)setEventColor:(NSColor *)color
{
  NSData *data = [NSArchiver archivedDataWithRootObject:color];
  [_config setObject:data forKey:ST_COLOR];
}

- (NSColor *)textColor
{
  NSData *theData =[_config objectForKey:ST_TEXT_COLOR];
  return [NSUnarchiver unarchiveObjectWithData:theData];
}

- (void)setTextColor:(NSColor *)color
{
  NSData *data = [NSArchiver archivedDataWithRootObject:color];
  [_config setObject:data forKey:ST_TEXT_COLOR];
}

- (BOOL)displayed
{
  return _displayed;
}

- (void)setDisplayed:(BOOL)state
{
  _displayed = state;
  [_config setObject:[NSNumber numberWithBool:_displayed] forKey:ST_DISPLAY];
}
@end


@implementation iCalStore(NSURLClient)
- (void)URL:(NSURL *)sender resourceDataDidBecomeAvailable:(NSData *)newBytes
{
  [_retrievedData appendData:newBytes];
}
- (void)URL:(NSURL *)sender resourceDidFailLoadingWithReason:(NSString *)reason
{
  NSLog(@"resourceDidFailLoadingWithReason %@", reason);
  [_retrievedData release];
}
- (void)URLResourceDidCancelLoading:(NSURL *)sender
{
  NSLog(@"URLResourceDidCancelLoading");
  [_retrievedData release];
}

- (void)URLResourceDidFinishLoading:(NSURL *)sender
{
  NSSet *items;
  NSString *text;
  NSEnumerator *enumerator;
  Element *elt;

  text = [[NSString alloc] initWithData:_retrievedData encoding:NSUTF8StringEncoding];
  if (text && [_tree parseString:text]) {
    items = [_tree components];
    [items makeObjectsPerform:@selector(setStore:) withObject:self];
    enumerator = [items objectEnumerator];
    while ((elt = [enumerator nextObject])) {
      if ([elt isKindOfClass:[Event class]])
	[_data setValue:elt forKey:[elt UID]];
      else
	[_tasks setValue:elt forKey:[elt UID]];
    }
    NSLog(@"iCalStore from %@ : loaded %d appointment(s)", [_url absoluteString], [_data count]);
    NSLog(@"iCalStore from %@ : loaded %d tasks(s)", [_url absoluteString], [_tasks count]);
    [text release];
    [[NSNotificationCenter defaultCenter] postNotificationName:SADataChangedInStore object:self];
  } else
    NSLog(@"Couldn't parse data from %@", [_url absoluteString]);
  [_retrievedData release];
}
@end
