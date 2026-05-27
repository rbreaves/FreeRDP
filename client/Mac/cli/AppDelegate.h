//
//  AppDelegate.h
//  MacClient2
//
//  Created by Benoît et Kathy on 2013-05-08.
//
//

#import <Cocoa/Cocoa.h>
#import <MRDPView.h>
#import <mfreerdp.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
{
  @public
	NSWindow *window;
	rdpContext *context;
	MRDPView *mrdpView;
}

- (void)rdpConnectError:(NSString *)customMessage;
- (void)refreshBitmapFromMenuItem:(id)sender;

@property(assign) IBOutlet NSWindow *window;
@property(assign) rdpContext *context;

@end
