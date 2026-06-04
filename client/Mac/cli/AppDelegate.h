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
	NSWindow *spacerWindow;
	rdpContext *context;
	MRDPView *mrdpView;
}

- (void)rdpConnectError:(NSString *)customMessage;

@property(assign) IBOutlet NSWindow *window;
@property(assign) rdpContext *context;

@end
