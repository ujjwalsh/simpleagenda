/* emacs buffer mode hint -*- objc -*- */

#import <Foundation/Foundation.h>
#import "AgendaStore.h"
#import "StoreManager.h"
#import "ConfigManager.h"
#import "defines.h"

@implementation StoreManager

#define PERSONAL_AGENDA @"Personal Agenda"

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
  NSArray *storeArray;
  NSString *defaultStore;
  NSEnumerator *enumerator;
  NSString *stname;

  self = [super init];
  if (self) {
    [[ConfigManager globalConfig] registerDefaults:[self defaults]];
    [[ConfigManager globalConfig] registerClient:self forKey:ST_DEFAULT];
    storeArray = [[ConfigManager globalConfig] objectForKey:STORES];
    defaultStore = [[ConfigManager globalConfig] objectForKey:ST_DEFAULT];
    _stores = [[NSMutableDictionary alloc] initWithCapacity:1];
    enumerator = [storeArray objectEnumerator];
    while ((stname = [enumerator nextObject]))
      [self addStoreNamed:stname];
    [self setDefaultStore:defaultStore];
  }
  return self;
}

- (void)dealloc
{
  [[ConfigManager globalConfig] unregisterClient:self];
  RELEASE(_defaultStore);
  [_stores release];
  [super dealloc];
}

- (void)config:(ConfigManager*)config dataDidChangedForKey:(NSString *)key
{
  [self setDefaultStore:[[ConfigManager globalConfig] objectForKey:ST_DEFAULT]];
}

- (void)addStoreNamed:(NSString *)name
{
  Class <AgendaStore> storeClass;
  id <AgendaStore> store;
  NSDictionary *dict;

  dict = [[ConfigManager globalConfig] objectForKey:name];
  if (dict) {
    storeClass = NSClassFromString([dict objectForKey:ST_CLASS]);
    store = [storeClass storeNamed:name];
    if (store) {
      [_stores setObject:store forKey:name];
      NSLog(@"Added %@ to StoreManager", name);
    } else
      NSLog(@"Unable to initialize store %@", name);
  }
}

- (void)removeStoreNamed:(NSString *)name
{
  [_stores removeObjectForKey:name];
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

- (NSEnumerator *)storeEnumerator
{
  return [_stores objectEnumerator];
}

- (void)synchronise
{
  NSEnumerator *enumerator = [_stores objectEnumerator];
  id <AgendaStore> store;

  while ((store = [enumerator nextObject]))
    if ([store modified] && [store isWritable])
      [store write];
}

- (id <AgendaStore>)storeContainingEvent:(Event *)event
{
  NSEnumerator *enumerator = [_stores objectEnumerator];
  id <AgendaStore> store;

  while ((store = [enumerator nextObject]))
    if ([store contains:[event UID]])
      return store;
  return nil;
}

- (NSArray *)allEvents
{
  NSMutableArray *all = [NSMutableArray arrayWithCapacity:128];
  NSEnumerator *enumerator = [_stores objectEnumerator];
  id <AgendaStore> store;

  while ((store = [enumerator nextObject]))
    [all addObjectsFromArray:[store events]];
  return all;
}

@end

