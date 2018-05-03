#import <AppKit/AppKit.h>

extern void DFRElementSetControlStripPresenceForIdentifier(NSString *, BOOL);

@interface NSTouchBarItem ()
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end
