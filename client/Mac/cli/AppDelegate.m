//
//  AppDelegate.m
//  MacClient2
//
//  Created by Benoît et Kathy on 2013-05-08.
//
//

#import "AppDelegate.h"
#import <mfreerdp.h>
#import <mf_client.h>
#import <MRDPView.h>

#import <winpr/assert.h>
#import <freerdp/client/cmdline.h>

#include <stdlib.h>
#include <string.h>

static AppDelegate *_singleDelegate = nil;
void AppDelegate_ConnectionResultEventHandler(void *context, const ConnectionResultEventArgs *e);
void AppDelegate_ErrorInfoEventHandler(void *ctx, const ErrorInfoEventArgs *e);
void AppDelegate_EmbedWindowEventHandler(void *context, const EmbedWindowEventArgs *e);
void AppDelegate_ResizeWindowEventHandler(void *context, const ResizeWindowEventArgs *e);
void mac_set_view_size(rdpContext *context, MRDPView *view);
static void mac_position_window_top_left(NSWindow *window);
static BOOL mac_is_point_on_left_screen_edge(NSPoint point);

@interface MRDPClientWindow : NSWindow
@end

@implementation MRDPClientWindow

- (BOOL)canBecomeKeyWindow
{
	return YES;
}

- (BOOL)canBecomeMainWindow
{
	return YES;
}

@end

@interface AppDelegate ()
{
	id leftEdgeMouseMonitor;
	NSTimer *leftEdgeFocusTimer;
}
- (void)ensureClientWindow;
- (void)startLeftEdgeFocusMonitor;
- (void)stopLeftEdgeFocusMonitor;
- (void)handleGlobalMouseEvent:(NSEvent *)event;
- (void)cancelLeftEdgeFocusTimer;
- (void)scheduleLeftEdgeFocusTimer;
- (void)leftEdgeFocusTimerFired:(NSTimer *)timer;
- (void)focusClientWindow;
- (void)applyWindowDecorationsFromSettings;
@end

@implementation AppDelegate

- (void)dealloc
{
	[self stopLeftEdgeFocusMonitor];
	[self cancelLeftEdgeFocusTimer];
	[super dealloc];
}

@synthesize window = window;

@synthesize context = context;

- (void)ensureClientWindow
{
	if ([window isKindOfClass:[MRDPClientWindow class]])
		return;

	NSRect contentRect = NSMakeRect(100, 100, 1024, 768);
	NSWindowStyleMask styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
	NSRect frameRect = NSZeroRect;
	BOOL wasVisible = NO;

	if (window)
	{
		contentRect = [window contentRectForFrameRect:[window frame]];
		styleMask = [window styleMask];
		frameRect = [window frame];
		wasVisible = [window isVisible];
	}

	MRDPClientWindow *newWindow = [[MRDPClientWindow alloc] initWithContentRect:contentRect
	                                                            styleMask:styleMask
	                                                              backing:NSBackingStoreBuffered
	                                                                defer:NO];
	[newWindow setAcceptsMouseMovedEvents:YES];
	[newWindow setLevel:NSNormalWindowLevel];
	[newWindow setDelegate:self];
	[newWindow setOpaque:NO];
	[newWindow setBackgroundColor:[NSColor clearColor]];

	if (!NSIsEmptyRect(frameRect))
		[newWindow setFrame:frameRect display:NO];

	if (window)
	{
		[window orderOut:self];
		[window setDelegate:nil];
	}

	window = newWindow;

	if (wasVisible)
		[window orderFront:self];
}

- (void)applyWindowDecorationsFromSettings
{
	if (!window || !context || !context->settings)
		return;

	const BOOL decorated = freerdp_settings_get_bool(context->settings, FreeRDP_Decorations);
	const BOOL fullscreen = freerdp_settings_get_bool(context->settings, FreeRDP_Fullscreen);
	NSWindowStyleMask styleMask = NSWindowStyleMaskResizable;

	if (decorated)
	{
		styleMask |= NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
		             NSWindowStyleMaskMiniaturizable;
		[window setTitleVisibility:NSWindowTitleVisible];
		[window setTitlebarAppearsTransparent:NO];
	}
	else
	{
		styleMask = NSWindowStyleMaskBorderless;
		[window setTitleVisibility:NSWindowTitleHidden];
		[window setTitlebarAppearsTransparent:YES];
	}

	[window setStyleMask:styleMask];
	[window setMovable:decorated];
	[window setMovableByWindowBackground:NO];
	[window setOpaque:NO];
	[window setBackgroundColor:[NSColor clearColor]];

	if (!decorated && !fullscreen)
		mac_position_window_top_left(window);
}

- (void)startLeftEdgeFocusMonitor
{
	if (leftEdgeMouseMonitor)
		return;

	leftEdgeMouseMonitor = [NSEvent
	    addGlobalMonitorForEventsMatchingMask:(NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged |
	                                         NSEventMaskRightMouseDragged |
	                                         NSEventMaskOtherMouseDragged)
	                            handler:^(NSEvent *event) {
		                            dispatch_async(dispatch_get_main_queue(), ^{
			                            [self handleGlobalMouseEvent:event];
		                            });
	                            }];
}

- (void)stopLeftEdgeFocusMonitor
{
	if (!leftEdgeMouseMonitor)
		return;

	[NSEvent removeMonitor:leftEdgeMouseMonitor];
	leftEdgeMouseMonitor = nil;
}

- (void)handleGlobalMouseEvent:(NSEvent *)event
{
	(void)event;

	if ([NSApp isActive])
	{
		[self cancelLeftEdgeFocusTimer];
		return;
	}

	if (mac_is_point_on_left_screen_edge([NSEvent mouseLocation]))
		[self scheduleLeftEdgeFocusTimer];
	else
		[self cancelLeftEdgeFocusTimer];
}

- (void)cancelLeftEdgeFocusTimer
{
	if (!leftEdgeFocusTimer)
		return;

	[leftEdgeFocusTimer invalidate];
	leftEdgeFocusTimer = nil;
}

- (void)scheduleLeftEdgeFocusTimer
{
	if (leftEdgeFocusTimer || [NSApp isActive])
		return;

	leftEdgeFocusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
	                                                     target:self
	                                                   selector:@selector(leftEdgeFocusTimerFired:)
	                                                   userInfo:nil
	                                                    repeats:NO];
}

- (void)leftEdgeFocusTimerFired:(NSTimer *)timer
{
	if (leftEdgeFocusTimer != timer)
		return;

	leftEdgeFocusTimer = nil;

	if ([NSApp isActive])
		return;

	if (!mac_is_point_on_left_screen_edge([NSEvent mouseLocation]))
		return;

	[self focusClientWindow];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	int status;
	mfContext *mfc;
	_singleDelegate = self;
	[self CreateContext];
	[self ensureClientWindow];

	if (!window)
	{
		window = [[MRDPClientWindow alloc]
		    initWithContentRect:NSMakeRect(100, 100, 1024, 768)
		            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
		                       NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
		              backing:NSBackingStoreBuffered
		                defer:NO];
		[window setAcceptsMouseMovedEvents:YES];
		[window setLevel:NSNormalWindowLevel];
		[window setDelegate:self];
		[window setOpaque:NO];
		[window setBackgroundColor:[NSColor clearColor]];
	}

	status = [self ParseCommandLineArguments];
	mfc = (mfContext *)context;
	WINPR_ASSERT(mfc);
	[self applyWindowDecorationsFromSettings];
	[self startLeftEdgeFocusMonitor];
	[self focusClientWindow];

	mfc->view = (void *)mrdpView;

	if (status == 0)
	{
		NSScreen *screen = [[NSScreen screens] objectAtIndex:0];
		NSRect screenFrame = [screen frame];
		rdpSettings *settings = context->settings;

		WINPR_ASSERT(settings);

		if (freerdp_settings_get_bool(settings, FreeRDP_Fullscreen))
		{
			(void)freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth,
			                                  screenFrame.size.width);
			(void)freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight,
			                                  screenFrame.size.height);
		}

		PubSub_SubscribeConnectionResult(context->pubSub, AppDelegate_ConnectionResultEventHandler);
		PubSub_SubscribeErrorInfo(context->pubSub, AppDelegate_ErrorInfoEventHandler);
		PubSub_SubscribeEmbedWindow(context->pubSub, AppDelegate_EmbedWindowEventHandler);
		PubSub_SubscribeResizeWindow(context->pubSub, AppDelegate_ResizeWindowEventHandler);
		freerdp_client_start(context);
		NSString *winTitle;
		const char *WindowTitle = freerdp_settings_get_string(settings, FreeRDP_WindowTitle);

		if (WindowTitle && WindowTitle[0])
		{
			winTitle = [[NSString alloc]
			    initWithFormat:@"%@", [NSString stringWithCString:WindowTitle
			                                             encoding:NSUTF8StringEncoding]];
		}
		else
		{
			const char *name = freerdp_settings_get_string(settings, FreeRDP_ServerHostname);
			const UINT32 port = freerdp_settings_get_uint32(settings, FreeRDP_ServerPort);
			winTitle = [[NSString alloc]
			    initWithFormat:@"%@:%u",
			                   [NSString stringWithCString:name encoding:NSUTF8StringEncoding],
			                   port];
		}

		[window setTitle:winTitle];
	}
	else
	{
		[NSApp terminate:self];
	}
}

- (void)applicationWillBecomeActive:(NSNotification *)notification
{
	[mrdpView resume];
	[self focusClientWindow];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
	[self focusClientWindow];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
	[mrdpView pause];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	NSLog(@"Stopping...\n");
	freerdp_client_stop(context);
	[mrdpView releaseResources];
	_singleDelegate = nil;
	NSLog(@"Stopped.\n");
	[NSApp terminate:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
	return YES;
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	[self focusClientWindow];
}

- (void)focusClientWindow
{
	if (!window)
		return;

	[NSApp activateIgnoringOtherApps:YES];

	if (![window isVisible])
		[window orderFront:self];

	if (![window isMainWindow])
		[window makeMainWindow];

	if (![window isKeyWindow])
		[window makeKeyWindow];

	if (mrdpView && ([window firstResponder] != mrdpView))
	{
		[window setInitialFirstResponder:mrdpView];
		[window makeFirstResponder:mrdpView];
	}

	[[window contentView] setNeedsDisplay:YES];
}

- (int)ParseCommandLineArguments
{
	int i;
	int length;
	int status;
	char *cptr;
	NSArray *args = [[NSProcessInfo processInfo] arguments];
	context->argc = (int)[args count];
	context->argv = malloc(sizeof(char *) * context->argc);
	i = 0;

	for (NSString *str in args)
	{
		/* filter out some arguments added by XCode */
		if ([str isEqualToString:@"YES"])
			continue;

		if ([str isEqualToString:@"-NSDocumentRevisionsDebugMode"])
			continue;

		length = (int)([str lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1);
		cptr = (char *)malloc(length);
		sprintf_s(cptr, length, "%s", [str UTF8String]);
		context->argv[i++] = cptr;
	}

	mfContext *mfc = (mfContext *)context;
	int filtered_argc = 1;
	for (int j = 1; j < i; j++)
	{
		if (strcmp(context->argv[j], "--chroma-key") == 0 && j + 1 < i)
		{
			mfc->chromaKeyEnabled = TRUE;
			j++;
			unsigned int colorVal;
			if (sscanf(context->argv[j], "#%x", &colorVal) == 1 || sscanf(context->argv[j], "%x", &colorVal) == 1)
			{
				mfc->chromaKeyColor = colorVal;
			}
		}
		else if (strcmp(context->argv[j], "--chroma-tolerance") == 0 && j + 1 < i)
		{
			j++;
			mfc->chromaKeyTolerance = (float)atof(context->argv[j]);
		}
		else
		{
			context->argv[filtered_argc++] = context->argv[j];
		}
	}

	context->argc = filtered_argc;
	status = freerdp_client_settings_parse_command_line(context->settings, context->argc,
	                                                    context->argv, FALSE);
	freerdp_client_settings_command_line_status_print(context->settings, status, context->argc,
	                                                  context->argv);

	return status;
}

- (void)CreateContext
{
	RDP_CLIENT_ENTRY_POINTS clientEntryPoints = WINPR_C_ARRAY_INIT;

	clientEntryPoints.Size = sizeof(RDP_CLIENT_ENTRY_POINTS);
	clientEntryPoints.Version = RDP_CLIENT_INTERFACE_VERSION;
	RdpClientEntry(&clientEntryPoints);
	context = freerdp_client_context_new(&clientEntryPoints);
}

- (void)ReleaseContext
{
	mfContext *mfc;
	MRDPView *view;
	mfc = (mfContext *)context;
	view = (MRDPView *)mfc->view;
	[view exitFullScreenModeWithOptions:nil];
	[view releaseResources];
	[view release];
	mfc->view = nil;
	freerdp_client_context_free(context);
	context = nil;
}

/** *********************************************************************
 * called when we fail to connect to a RDP server - Make sure this is called from the main thread.
 ***********************************************************************/

- (void)rdpConnectError:(NSString *)withMessage
{
	mfContext *mfc;
	MRDPView *view;
	mfc = (mfContext *)context;
	view = (MRDPView *)mfc->view;
	[view exitFullScreenModeWithOptions:nil];
	NSString *message = withMessage ? withMessage : @"Error connecting to server";
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:message];
	[alert beginSheetModalForWindow:[self window]
	                  modalDelegate:self
	                 didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:)
	                    contextInfo:nil];
}

/** *********************************************************************
 * just a terminate selector for above call
 ***********************************************************************/

- (void)alertDidEnd:(NSAlert *)a returnCode:(NSInteger)rc contextInfo:(void *)ci
{
	[NSApp terminate:nil];
}

@end

/** *********************************************************************
 * On connection error, display message and quit application
 ***********************************************************************/

void AppDelegate_ConnectionResultEventHandler(void *ctx, const ConnectionResultEventArgs *e)
{
	rdpContext *context = (rdpContext *)ctx;
	NSLog(@"ConnectionResult event result:%d\n", e->result);

	if (_singleDelegate)
	{
		if (e->result != 0)
		{
			NSString *message = nil;
			DWORD code = freerdp_get_last_error(context);
			switch (code)
			{
				case FREERDP_ERROR_AUTHENTICATION_FAILED:
					message = [NSString
					    stringWithFormat:@"%@", @"Authentication failure, check credentials."];
					break;
				default:
					break;
			}

			// Making sure this should be invoked on the main UI thread.
			[_singleDelegate performSelectorOnMainThread:@selector(rdpConnectError:)
			                                  withObject:message
			                               waitUntilDone:FALSE];
		}
	}
}

void AppDelegate_ErrorInfoEventHandler(void *ctx, const ErrorInfoEventArgs *e)
{
	NSLog(@"ErrorInfo event code:%d\n", e->code);

	if (_singleDelegate)
	{
		// Retrieve error message associated with error code
		NSString *message = nil;

		if (e->code != ERRINFO_NONE)
		{
			const char *errorMessage = freerdp_get_error_info_string(e->code);
			message = [[NSString alloc] initWithUTF8String:errorMessage];
		}

		// Making sure this should be invoked on the main UI thread.
		[_singleDelegate performSelectorOnMainThread:@selector(rdpConnectError:)
		                                  withObject:message
		                               waitUntilDone:TRUE];
		[message release];
	}
}

void AppDelegate_EmbedWindowEventHandler(void *ctx, const EmbedWindowEventArgs *e)
{
	rdpContext *context = (rdpContext *)ctx;

	if (_singleDelegate)
	{
		mfContext *mfc = (mfContext *)context;
		_singleDelegate->mrdpView = mfc->view;

		if (_singleDelegate->window)
		{
			[[_singleDelegate->window contentView] addSubview:mfc->view];

			dispatch_async(dispatch_get_main_queue(), ^{
				[_singleDelegate focusClientWindow];

				NSLog(@"Window: isKeyWindow=%d, isMainWindow=%d",
					[_singleDelegate->window isKeyWindow],
					[_singleDelegate->window isMainWindow]);
				NSLog(@"View: acceptsFirstResponder=%d, isFirstResponder=%d",
					[mfc->view acceptsFirstResponder],
					[mfc->view isEqual:[_singleDelegate->window firstResponder]]);

				mac_set_view_size(context, mfc->view);
			});
		}
		else
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				mac_set_view_size(context, mfc->view);
			});
		}
	}
}

void AppDelegate_ResizeWindowEventHandler(void *ctx, const ResizeWindowEventArgs *e)
{
	rdpContext *context = (rdpContext *)ctx;
	(void)fprintf(stderr, "ResizeWindowEventHandler: %d %d\n", e->width, e->height);

	if (_singleDelegate)
	{
		mfContext *mfc = (mfContext *)context;
		dispatch_async(dispatch_get_main_queue(), ^{
			mac_set_view_size(context, mfc->view);
		});
	}
}

void mac_set_view_size(rdpContext *context, MRDPView *view)
{
	NSWindow *window = [view window];
	// set client area to specified dimensions
	NSRect innerRect;
	innerRect.origin.x = 0;
	innerRect.origin.y = 0;
	innerRect.size.width = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth);
	innerRect.size.height = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopHeight);
	[view setFrame:innerRect];
	// calculate window of same size, but keep position
	NSRect outerRect = [window frame];
	outerRect.size = [window frameRectForContentRect:innerRect].size;
	// we are not in RemoteApp mode, disable larger than resolution
	[window setContentMaxSize:innerRect.size];
	// set window to given area
	[window setFrame:outerRect display:YES];

	if (!freerdp_settings_get_bool(context->settings, FreeRDP_Decorations) &&
	    !freerdp_settings_get_bool(context->settings, FreeRDP_Fullscreen))
	{
		mac_position_window_top_left(window);
	}

	// set window to front
	[NSApp activateIgnoringOtherApps:YES];

	if (freerdp_settings_get_bool(context->settings, FreeRDP_Fullscreen))
		[window toggleFullScreen:nil];
}

static void mac_position_window_top_left(NSWindow *window)
{
	if (!window)
		return;

	NSScreen *screen = [window screen];
	if (!screen)
		screen = [NSScreen mainScreen];
	if (!screen)
		return;

	NSRect visibleFrame = [screen visibleFrame];
	NSRect frame = [window frame];
	NSPoint topLeft = NSMakePoint(NSMinX(visibleFrame), NSMaxY(visibleFrame));
	frame.origin.x = topLeft.x;
	frame.origin.y = topLeft.y - NSHeight(frame);
	[window setFrame:frame display:YES];
}

static BOOL mac_is_point_on_left_screen_edge(NSPoint point)
{
	for (NSScreen *screen in [NSScreen screens])
	{
		NSRect frame = [screen frame];
		if (!NSPointInRect(point, frame))
			continue;

		return (point.x <= (NSMinX(frame) + 1.0)) ? YES : NO;
	}

	return NO;
}
