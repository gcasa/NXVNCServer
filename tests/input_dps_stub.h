#import <Foundation/Foundation.h>
@interface NSDPSContext : NSObject
+ (void)setCurrentContext:(NSDPSContext *)context;
@end
@interface NXVNCMockApplication : NSObject
- (NSDPSContext *)context;
@end
extern NXVNCMockApplication *NSApp;
void PScurrentactiveapp(int *);
void PSrealtime(int *);
void PSposteventbycontext(int,float,float,int,int,int,int,int,int,int,int *);
