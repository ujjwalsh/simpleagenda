/* emacs buffer mode hint -*- objc -*- */

#import <Foundation/Foundation.h>
#import "AgendaStore.h"
#import "StoreManager.h"
#import "UserDefaults.h"
#import "defines.h"

@implementation StoreManager

#define PERSONAL_AGENDA @"Personal Agenda"

UserDefaults *defaults;

- (NSDictionary *)defaults
{
  NSDictionary *local = [NSDictionary
			  dictionaryWithObjects:[NSArray arrayWithObjects:@"LocalStore", @"Personal", nil]
			  forKeys:[NSArray arrayWithObjects:ST_CLASS, ST_FILE, nil]];
  NSDictionary *dict = [NSDictionary 
			 dictionaryWithObjects:[NSArray arrayWithObjects: [NSArray arrayWithObject:PERSONAL_AGENDA], local, PERSONAL_AGENDA, nil]
			 forKeys:[NSArray arrayWithObjects: STORES, PERSONAL_AGENDA, ST_DEFAULT, nil]];
  return dict;
}

- (id)init
{
  Class <AgendaStore> storeClass;
  id <AgendaStore> store;
  NSString *stname;
  NSDictionary *dict;
  NSEnumerator *enumerator;

  self = [super init];
  if (self) {
    defaults = [UserDefaults sharedInstance];
    [defaults setHardDefaults:[self defaults]];
    [defaults registerClient:self forKey:ST_DEFAULT];
    NSArray *storeArray = [defaults objectForKey:STORES];
    NSString *defaultStore = [defaults objectForKey:ST_DEFAULT];

    _stores = [[NSMutableDictionary alloc] initWithCapacity:1];
    enumerator = [storeArray objectEnumerator];
    while ((stname = [enumerator nextObject])) {
      dict = [defaults objectForKey:stname];
      if (dict) {
	storeClass = NSClassFromString([dict objectForKey:ST_CLASS]);
	store = [storeClass storeNamed:stname forManager:self];
	if (store) {
	  [_stores setObject:store forKey:stname];
	  NSLog(@"Added %@ to StoreManager", stname);
	} else
	  NSLog(@"Unable to initialize store %@", stname);
      }
    }
    [self setDefaultStore:defaultStore];
  }
  return self;
}

- (void)dealloc
{
  [defaults unregisterClient:self];
  RELEASE(_defaultStore);
  RELEASE(_delegate);
  [_stores release];
  [super dealloc];
}

- (void)defaultDidChanged:(NSString *)name
{
  [self setDefaultStore:[[UserDefaults sharedInstance] objectForKey:ST_DEFAULT]];
}

- (id <AgendaStore>)storeForName:(NSString *)name
{
  return [_stores objectForKey:name];
}

- (void)setDefaultStore:(NSString *)name
{
  id st = [self storeForName:name];
  if (st != nil)
    ASSIGN(_defaultStore, st);
}

- (id <AgendaStore>)defaultStore
{
  return _defaultStore;
}

- (NSEnumerator *)objectEnumerator
{
  return [_stores objectEnumerator];
}

- (void)setDelegate:(id)delegate;
{
  ASSIGN(_delegate, delegate);
}

- (void)synchronise
{
  NSEnumerator *enumerator;
  id <AgendaStore> store;

  enumerator = [_stores objectEnumerator];
  while ((store = [enumerator nextObject]))
    [store write];
}

@end

@implementation StoreManager(AgendaStoreDelegate)

- (void)dataChanged:(id <AgendaStore>)store
{
  NSLog(@"Data changed in %@", [store description]);
  if ([_delegate respondsToSelector:@selector(dataChanged)])
    [_delegate dataChanged];
}

@end

