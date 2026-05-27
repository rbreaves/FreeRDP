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
#import <freerdp/client/disp.h>
#import <freerdp/version.h>

#include <stdlib.h>
#include <string.h>

static AppDelegate *_singleDelegate = nil;
void AppDelegate_ConnectionResultEventHandler(void *context, const ConnectionResultEventArgs *e);
void AppDelegate_ErrorInfoEventHandler(void *ctx, const ErrorInfoEventArgs *e);
void AppDelegate_EmbedWindowEventHandler(void *context, const EmbedWindowEventArgs *e);
void AppDelegate_ResizeWindowEventHandler(void *context, const ResizeWindowEventArgs *e);
void mac_set_view_size(rdpContext *context, MRDPView *view);
static void mac_position_window_top_left(NSWindow *window);
static void mac_maximize_window_minus_menubar(NSWindow *window, MRDPView *view);
static BOOL mac_is_point_on_left_screen_edge(NSPoint point);
static NSURL *mac_find_resource_url(NSString *resourceName, NSString *extension);
static NSImage *mac_load_svg_image(NSString *resourceName, CGFloat pointSize, BOOL templateImage);
static NSImage *mac_render_image_for_size(NSImage *source, CGFloat pointSize, BOOL templateImage);
static NSImage *mac_create_freerdp_vector_icon(CGFloat pointSize, BOOL monochrome, BOOL templateImage);
static NSInteger mac_screen_index_for_screen(NSScreen *screen);
static NSScreen *mac_screen_for_index(NSInteger screenIndex);
static NSString *mac_screen_identifier(NSScreen *screen);
static NSScreen *mac_screen_for_identifier(NSString *identifier);
static NSScreen *mac_preferred_screen(NSWindow *window);
static NSString *mac_display_title(NSScreen *screen, NSInteger screenIndex);
static DISPLAY_CONTROL_MONITOR_LAYOUT mac_display_layout_for_screen(NSScreen *screen,
	                                                               BOOL useVisibleFrame,
	                                                               rdpSettings *settings);

static NSString *const MRDPPreferredScreenIdentifierKey = @"MRDPPreferredScreenIdentifier";

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
	NSStatusItem *statusItem;
	NSMenu *statusMenu;
	NSInteger preferredScreenIndex;
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
- (void)configureMainMenu;
- (void)configureApplicationIcon;
- (void)installStatusItem;
- (void)removeStatusItem;
- (void)statusItemClicked:(id)sender;
- (void)rebuildStatusMenu;
- (void)focusSessionFromMenuItem:(id)sender;
- (void)refreshBitmapFromMenuItem:(id)sender;
- (void)sendPasswordFromMenuItem:(id)sender;
- (void)sendCtrlAltDelFromMenuItem:(id)sender;
- (void)sendRemoteKeyFromMenuItem:(NSMenuItem *)menuItem;
- (void)sendRemoteBreakFromMenuItem:(id)sender;
- (void)showAboutPanel:(id)sender;
- (void)switchMonitorFromMenuItem:(NSMenuItem *)menuItem;
- (void)moveSessionToScreen:(NSScreen *)screen screenIndex:(NSInteger)screenIndex;
- (BOOL)requestRemoteResizeForScreen:(NSScreen *)screen;
- (NSString *)credentialTarget;
- (NSScreen *)preferredScreen;
- (NSInteger)currentScreenIndex;
- (void)loadPreferredScreenFromDefaults;
- (void)savePreferredScreenToDefaults;
@end

@implementation AppDelegate

- (void)dealloc
{
	[self stopLeftEdgeFocusMonitor];
	[self cancelLeftEdgeFocusTimer];
	[self removeStatusItem];
	[statusMenu release];
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

	mfContext *mfc = (mfContext *)context;
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

	if (!decorated && !fullscreen && mfc->fullscreen_mode != 2)
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
	[self loadPreferredScreenFromDefaults];
	[self CreateContext];
	[self ensureClientWindow];
	[self configureMainMenu];
	[self configureApplicationIcon];
	[self installStatusItem];

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

	mfc->view = (void *)mrdpView;

	if (status == 0)
	{
		NSScreen *screen = [self preferredScreen];
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
	[self savePreferredScreenToDefaults];
	[self removeStatusItem];
	freerdp_client_stop(context);
	[mrdpView releaseResources];
	_singleDelegate = nil;
	NSLog(@"Stopped.\n");
	[NSApp terminate:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	(void)sender;

	if (!window || !mrdpView)
		return NO;

	return [window isVisible] && [mrdpView is_connected];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
	return YES;
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	[self focusClientWindow];
}

- (void)windowDidMove:(NSNotification *)notification
{
	(void)notification;
	[self savePreferredScreenToDefaults];
}

- (void)focusClientWindow
{
	if (!window)
		return;

	const BOOL connected = !mrdpView || [mrdpView is_connected];

	[NSApp activateIgnoringOtherApps:YES];

	if (!connected && ![window isVisible])
		return;

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

- (void)configureApplicationIcon
{
	NSImage *dockIcon = mac_load_svg_image(@"freerdp_minimal", 256.0, NO);

	if (dockIcon)
		[NSApp setApplicationIconImage:dockIcon];
}

- (void)configureMainMenu
{
	NSMenu *mainMenu = [NSApp mainMenu];
	if (!mainMenu)
		return;

	NSMenuItem *appMenuItem = ([mainMenu numberOfItems] > 0) ? [mainMenu itemAtIndex:0] : nil;
	NSMenu *appMenu = nil;

	if (appMenuItem)
		[appMenuItem setTitle:@"MacFreeRDP"];
	if (appMenuItem)
	{
		appMenu = [[[NSMenu alloc] initWithTitle:@"MacFreeRDP"] autorelease];

		NSMenuItem *aboutItem = [[[NSMenuItem alloc] initWithTitle:@"About MacFreeRDP"
		                                                 action:@selector(showAboutPanel:)
		                                          keyEquivalent:@""] autorelease];
		[aboutItem setTarget:self];
		[appMenu addItem:aboutItem];
		[appMenu addItem:[NSMenuItem separatorItem]];

		NSMenuItem *hideItem = [[[NSMenuItem alloc] initWithTitle:@"Hide MacFreeRDP"
		                                                action:@selector(hide:)
		                                         keyEquivalent:@"h"] autorelease];
		[hideItem setTarget:NSApp];
		[appMenu addItem:hideItem];

		NSMenuItem *hideOthersItem = [[[NSMenuItem alloc] initWithTitle:@"Hide Others"
		                                                      action:@selector(hideOtherApplications:)
		                                               keyEquivalent:@"h"] autorelease];
		[hideOthersItem setTarget:NSApp];
		[hideOthersItem setKeyEquivalentModifierMask:(NSEventModifierFlagCommand |
		                                            NSEventModifierFlagOption)];
		[appMenu addItem:hideOthersItem];

		NSMenuItem *showAllItem = [[[NSMenuItem alloc] initWithTitle:@"Show All"
		                                                   action:@selector(unhideAllApplications:)
		                                            keyEquivalent:@""] autorelease];
		[showAllItem setTarget:NSApp];
		[appMenu addItem:showAllItem];
		[appMenu addItem:[NSMenuItem separatorItem]];

		NSMenuItem *quitItem = [[[NSMenuItem alloc] initWithTitle:@"Quit MacFreeRDP"
		                                                action:@selector(terminate:)
		                                         keyEquivalent:@"q"] autorelease];
		[quitItem setTarget:NSApp];
		[appMenu addItem:quitItem];

		[appMenuItem setSubmenu:appMenu];
	}

	NSMenuItem *existingRemote = [mainMenu itemWithTitle:@"Remote"];
	if (existingRemote)
		[mainMenu removeItem:existingRemote];

	NSMenuItem *remoteItem = [[[NSMenuItem alloc] initWithTitle:@"Remote"
	                                                   action:nil
	                                            keyEquivalent:@""] autorelease];
	NSMenu *remoteMenu = [[[NSMenu alloc] initWithTitle:@"Remote"] autorelease];

	NSMenuItem *sendPasswordItem = [[[NSMenuItem alloc] initWithTitle:@"Send Password"
	                                                        action:@selector(sendPasswordFromMenuItem:)
	                                                 keyEquivalent:@""] autorelease];
	[sendPasswordItem setTarget:self];
	[remoteMenu addItem:sendPasswordItem];

	NSMenuItem *cadItem = [[[NSMenuItem alloc] initWithTitle:@"Ctrl+Alt+Del"
	                                                  action:@selector(sendCtrlAltDelFromMenuItem:)
	                                           keyEquivalent:@""] autorelease];
	[cadItem setTarget:self];
	[remoteMenu addItem:cadItem];

	NSMenuItem *sendKeysItem = [[[NSMenuItem alloc] initWithTitle:@"Send Keys"
	                                                    action:nil
	                                             keyEquivalent:@""] autorelease];
	NSMenu *sendKeysMenu = [[[NSMenu alloc] initWithTitle:@"Send Keys"] autorelease];
	NSArray *keyEntries = [NSArray arrayWithObjects:
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Home", @"title", @(RDP_SCANCODE_HOME), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"End", @"title", @(RDP_SCANCODE_END), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Forward Delete", @"title", @(RDP_SCANCODE_DELETE), @"tag", nil],
	    [NSNull null],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Num Lock", @"title", @(RDP_SCANCODE_NUMLOCK), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Scroll Lock", @"title", @(RDP_SCANCODE_SCROLLLOCK), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Print Scrn", @"title", @(RDP_SCANCODE_PRINTSCREEN), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Pause", @"title", @(RDP_SCANCODE_PAUSE), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Break", @"title", @(-1), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Insert", @"title", @(RDP_SCANCODE_INSERT), @"tag", nil],
	    [NSNull null],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"F10", @"title", @(RDP_SCANCODE_F10), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"F11", @"title", @(RDP_SCANCODE_F11), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"F12", @"title", @(RDP_SCANCODE_F12), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"F13", @"title", @(RDP_SCANCODE_F13), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"F14", @"title", @(RDP_SCANCODE_F14), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"F15", @"title", @(RDP_SCANCODE_F15), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"F16", @"title", @(RDP_SCANCODE_F16), @"tag", nil],
	    nil];

	for (id entry in keyEntries)
	{
		if ([entry isKindOfClass:[NSNull class]])
		{
			[sendKeysMenu addItem:[NSMenuItem separatorItem]];
			continue;
		}

		NSDictionary *definition = (NSDictionary *)entry;
		NSString *title = [definition objectForKey:@"title"];
		NSInteger tag = [[definition objectForKey:@"tag"] integerValue];
		SEL action = (tag == -1) ? @selector(sendRemoteBreakFromMenuItem:)
		                        : @selector(sendRemoteKeyFromMenuItem:);
		NSMenuItem *keyItem = [[[NSMenuItem alloc] initWithTitle:title
		                                                   action:action
		                                            keyEquivalent:@""] autorelease];
		[keyItem setTarget:self];
		[keyItem setTag:tag];
		[sendKeysMenu addItem:keyItem];
	}

	[sendKeysItem setSubmenu:sendKeysMenu];
	[remoteMenu addItem:sendKeysItem];
	[remoteItem setSubmenu:remoteMenu];
	[mainMenu insertItem:remoteItem atIndex:MIN(1, [mainMenu numberOfItems])];
}

- (void)showAboutPanel:(id)sender
{
	(void)sender;
	NSDictionary *options = [NSDictionary
	    dictionaryWithObjectsAndKeys:@"MacFreeRDP", @"ApplicationName",
	                                 [NSString stringWithFormat:@"FreeRDP %@ (%s)",
	                                                             @FREERDP_VERSION_FULL,
	                                                             FREERDP_GIT_REVISION],
	                                 @"Version",
	                                 ([NSApp applicationIconImage] ?: [NSImage imageNamed:NSImageNameApplicationIcon]),
	                                 @"ApplicationIcon",
	                                 @"Remote Desktop Protocol client for macOS.", @"ApplicationDescription",
	                                 nil];
	[NSApp orderFrontStandardAboutPanelWithOptions:options];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)installStatusItem
{
	if (statusItem)
		return;

	statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength]
	    retain];
	statusMenu = [[NSMenu alloc] initWithTitle:@"MacFreeRDP"];

	NSStatusBarButton *button = [statusItem button];
	if (!button)
		return;

	NSImage *statusIcon = mac_load_svg_image(@"freerdp_minimal_bw",
	                                         [NSStatusBar systemStatusBar].thickness - 4.0, YES);
	if (statusIcon)
		[button setImage:statusIcon];

	[button setTarget:self];
	[button setAction:@selector(statusItemClicked:)];
	[button sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)];
	[button setToolTip:@"MacFreeRDP"];
}

- (void)removeStatusItem
{
	if (!statusItem)
		return;

	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
	[statusItem release];
	statusItem = nil;
}

- (void)statusItemClicked:(id)sender
{
	(void)sender;
	[self rebuildStatusMenu];
	[statusItem popUpStatusItemMenu:statusMenu];
	[[statusItem button] setHighlighted:NO];
}

- (void)rebuildStatusMenu
{
	while ([statusMenu numberOfItems] > 0)
		[statusMenu removeItemAtIndex:0];

	NSArray *screens = [NSScreen screens];
	NSInteger currentScreen = [self currentScreenIndex];

	for (NSUInteger index = 0; index < [screens count]; index++)
	{
		NSScreen *screen = [screens objectAtIndex:index];
		NSMenuItem *menuItem =
		    [[[NSMenuItem alloc] initWithTitle:mac_display_title(screen, (NSInteger)index)
		                                 action:@selector(switchMonitorFromMenuItem:)
		                          keyEquivalent:@""] autorelease];
		[menuItem setTarget:self];
		[menuItem setTag:(NSInteger)index];
		[menuItem setState:((NSInteger)index == currentScreen) ? NSControlStateValueOn
		                                                      : NSControlStateValueOff];
		[statusMenu addItem:menuItem];
	}

	if ([screens count] > 0)
		[statusMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *refreshItem =
	    [[[NSMenuItem alloc] initWithTitle:@"Refresh Bitmap"
	                                 action:@selector(refreshBitmapFromMenuItem:)
	                          keyEquivalent:@""] autorelease];
	[refreshItem setTarget:self];
	[statusMenu addItem:refreshItem];

	NSMenuItem *focusItem =
	    [[[NSMenuItem alloc] initWithTitle:@"Focus Session"
	                                 action:@selector(focusSessionFromMenuItem:)
	                          keyEquivalent:@""] autorelease];
	[focusItem setTarget:self];
	[statusMenu addItem:focusItem];

	[statusMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *quitItem =
	    [[[NSMenuItem alloc] initWithTitle:@"Quit MacFreeRDP"
	                                 action:@selector(terminate:)
	                          keyEquivalent:@""] autorelease];
	[quitItem setTarget:NSApp];
	[statusMenu addItem:quitItem];
}

- (void)focusSessionFromMenuItem:(id)sender
{
	(void)sender;
	[self focusClientWindow];
}

- (void)refreshBitmapFromMenuItem:(id)sender
{
	(void)sender;
	if (mrdpView)
		[mrdpView refreshBitmap];
}

- (void)sendPasswordFromMenuItem:(id)sender
{
	(void)sender;

	if (!mrdpView || ![mrdpView canSendRemoteInput])
	{
		NSBeep();
		return;
	}

	NSString *target = [self credentialTarget];
	NSString *username = nil;
	NSString *domain = nil;

	if (context && context->settings)
	{
		const char *user = freerdp_settings_get_string(context->settings, FreeRDP_Username);
		const char *dom = freerdp_settings_get_string(context->settings, FreeRDP_Domain);
		if (user)
			username = [NSString stringWithCString:user encoding:NSUTF8StringEncoding];
		if (dom)
			domain = [NSString stringWithCString:dom encoding:NSUTF8StringEncoding];
	}

	[self focusClientWindow];
	[mrdpView sendStoredPasswordForServer:target username:username domain:domain];
}

- (void)sendCtrlAltDelFromMenuItem:(id)sender
{
	(void)sender;
	[self focusClientWindow];
	[mrdpView sendRemoteCtrlAltDel];
}

- (void)sendRemoteKeyFromMenuItem:(NSMenuItem *)menuItem
{
	[self focusClientWindow];
	[mrdpView sendRemoteKeyScancode:(UINT32)[menuItem tag]];
}

- (void)sendRemoteBreakFromMenuItem:(id)sender
{
	(void)sender;
	[self focusClientWindow];
	[mrdpView sendRemoteBreakKey];
}

- (void)switchMonitorFromMenuItem:(NSMenuItem *)menuItem
{
	NSInteger screenIndex = [menuItem tag];
	NSScreen *screen = mac_screen_for_index(screenIndex);

	[self moveSessionToScreen:screen screenIndex:screenIndex];
}

- (void)moveSessionToScreen:(NSScreen *)screen screenIndex:(NSInteger)screenIndex
{
	if (!screen)
		return;

	preferredScreenIndex = screenIndex;
	[self savePreferredScreenToDefaults];

	if (!window)
		return;

	rdpSettings *settings = context ? context->settings : NULL;
	mfContext *mfc = (mfContext *)context;
	const BOOL fullscreen = settings && freerdp_settings_get_bool(settings, FreeRDP_Fullscreen) &&
	                        mfc && (mfc->fullscreen_mode != 2);
	const BOOL pseudoFullscreen = mfc && (mfc->fullscreen_mode == 2);
	const BOOL useVisibleFrame = pseudoFullscreen;
	NSRect targetRect = useVisibleFrame ? [screen visibleFrame] : [screen frame];

	if (fullscreen && mrdpView && [mrdpView isInFullScreenMode])
		[mrdpView exitFullScreenModeWithOptions:nil];

	if (!fullscreen && !pseudoFullscreen)
	{
		NSRect frame = [window frame];
		NSRect visibleFrame = [screen visibleFrame];

		frame.origin.x = NSMinX(visibleFrame);
		frame.origin.y = NSMaxY(visibleFrame) - NSHeight(frame);
		[window setFrame:frame display:YES];
		[self focusClientWindow];
		return;
	}

	[window setFrame:targetRect display:YES];

	if (settings)
	{
		const BOOL resizeRequested = [self requestRemoteResizeForScreen:screen];

		if (!resizeRequested && pseudoFullscreen)
			mac_maximize_window_minus_menubar(window, mrdpView);
	}

	if (fullscreen && mrdpView)
		[mrdpView enterFullScreenMode:screen withOptions:nil];

	[self focusClientWindow];
}

- (BOOL)requestRemoteResizeForScreen:(NSScreen *)screen
{
	if (!context || !context->settings || !screen)
		return NO;

	mfContext *mfc = (mfContext *)context;
	rdpSettings *settings = context->settings;
	const BOOL fullscreen = freerdp_settings_get_bool(settings, FreeRDP_Fullscreen) &&
	                        (mfc->fullscreen_mode != 2);
	const BOOL pseudoFullscreen = (mfc->fullscreen_mode == 2);

	if (!fullscreen && !pseudoFullscreen)
		return NO;

	if (!mfc->disp || !mfc->disp->SendMonitorLayout)
		return NO;

	DISPLAY_CONTROL_MONITOR_LAYOUT layout =
	    mac_display_layout_for_screen(screen, pseudoFullscreen, settings);

	if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, layout.Width))
		return NO;
	if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, layout.Height))
		return NO;

	return (mfc->disp->SendMonitorLayout(mfc->disp, 1, &layout) == CHANNEL_RC_OK) ? YES : NO;
}

- (NSString *)credentialTarget
{
	if (!context || !context->settings)
		return nil;

	const char *name = freerdp_settings_get_string(context->settings, FreeRDP_ServerHostname);
	const UINT32 port = freerdp_settings_get_uint32(context->settings, FreeRDP_ServerPort);
	if (!name)
		return nil;

	return [NSString stringWithFormat:@"%@:%u",
	                                  [NSString stringWithCString:name encoding:NSUTF8StringEncoding],
	                                  port];
}

- (NSScreen *)preferredScreen
{
	return mac_screen_for_index(preferredScreenIndex);
}

- (NSInteger)currentScreenIndex
{
	NSInteger currentScreen = mac_screen_index_for_screen([window screen]);

	if (currentScreen != NSNotFound)
		return currentScreen;

	return preferredScreenIndex;
}

- (void)loadPreferredScreenFromDefaults
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *identifier = [defaults stringForKey:MRDPPreferredScreenIdentifierKey];
	NSScreen *screen = mac_screen_for_identifier(identifier);

	if (!screen)
		screen = [NSScreen mainScreen];

	preferredScreenIndex = mac_screen_index_for_screen(screen);
	if (preferredScreenIndex == NSNotFound)
		preferredScreenIndex = 0;
}

- (void)savePreferredScreenToDefaults
{
	NSScreen *screen = [window screen];
	if (!screen)
		screen = [self preferredScreen];

	NSString *identifier = mac_screen_identifier(screen);
	if (!identifier)
		return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:identifier forKey:MRDPPreferredScreenIdentifierKey];
	[defaults synchronize];
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
		else if (strcmp(context->argv[j], "/f:2") == 0 || strcmp(context->argv[j], "-f:2") == 0)
		{
			mfc->fullscreen_mode = 2;
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
	if ([NSApp applicationIconImage])
		[alert setIcon:[NSApp applicationIconImage]];
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
		if (e->result == 0)
		{
			mfContext *mfc = (mfContext *)context;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (mfc && mfc->view)
				{
					NSScreen *screen = [_singleDelegate preferredScreen];
					NSInteger screenIndex = mac_screen_index_for_screen(screen);
					mac_set_view_size(context, mfc->view);
					[_singleDelegate moveSessionToScreen:screen screenIndex:screenIndex];
					[_singleDelegate focusClientWindow];
				}
			});
		}
		else
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
	mfContext *mfc = (mfContext *)context;
	NSWindow *window = [view window];
	NSScreen *screen = mac_preferred_screen(window);
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

	if ((mfc->fullscreen_mode == 2) && [view is_connected])
	{
		mac_maximize_window_minus_menubar(window, view);
	}
	else if (!freerdp_settings_get_bool(context->settings, FreeRDP_Decorations) &&
	    !freerdp_settings_get_bool(context->settings, FreeRDP_Fullscreen))
	{
		mac_position_window_top_left(window);
	}

	// set window to front
	[NSApp activateIgnoringOtherApps:YES];

	if ([view is_connected] && freerdp_settings_get_bool(context->settings, FreeRDP_Fullscreen) &&
	    mfc->fullscreen_mode != 2 &&
	    view && screen && ![view isInFullScreenMode])
	{
		[view enterFullScreenMode:screen withOptions:nil];
	}
}

static void mac_position_window_top_left(NSWindow *window)
{
	if (!window)
		return;

	NSScreen *screen = mac_preferred_screen(window);
	if (!screen)
		return;

	NSRect visibleFrame = [screen visibleFrame];
	NSRect frame = [window frame];
	NSPoint topLeft = NSMakePoint(NSMinX(visibleFrame), NSMaxY(visibleFrame));
	frame.origin.x = topLeft.x;
	frame.origin.y = topLeft.y - NSHeight(frame);
	[window setFrame:frame display:YES];
}

static void mac_maximize_window_minus_menubar(NSWindow *window, MRDPView *view)
{
	if (!window || !view)
		return;

	NSScreen *screen = mac_preferred_screen(window);
	if (!screen)
		return;

	NSRect visibleFrame = [screen visibleFrame];

	NSRect frame = NSMakeRect(
		NSMinX(visibleFrame),
		NSMinY(visibleFrame),
		NSWidth(visibleFrame),
		NSHeight(visibleFrame)
	);

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

static NSURL *mac_find_resource_url(NSString *resourceName, NSString *extension)
{
	NSBundle *bundle = [NSBundle mainBundle];
	NSURL *url = [bundle URLForResource:resourceName withExtension:extension];

	if (url)
		return url;

	NSString *executablePath = [bundle executablePath];
	if (!executablePath)
		executablePath = [[[NSProcessInfo processInfo] arguments] firstObject];
	if (!executablePath)
		return nil;

	NSString *candidate = [[executablePath stringByDeletingLastPathComponent]
	    stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", resourceName,
	                                                           extension]];
	if (![[NSFileManager defaultManager] fileExistsAtPath:candidate])
		return nil;

	return [NSURL fileURLWithPath:candidate];
}

static NSImage *mac_load_svg_image(NSString *resourceName, CGFloat pointSize, BOOL templateImage)
{
	if ([resourceName isEqualToString:@"freerdp_minimal"] && pointSize >= 128.0)
		return mac_create_freerdp_vector_icon(pointSize, NO, templateImage);
	if ([resourceName isEqualToString:@"freerdp_minimal_bw"] && pointSize >= 32.0)
		return mac_create_freerdp_vector_icon(pointSize, YES, templateImage);

	NSURL *url = mac_find_resource_url(resourceName, @"svg");
	NSImage *image = nil;

	if (!url)
		return nil;

	image = [[[NSImage alloc] initWithContentsOfURL:url] autorelease];
	if (!image)
	{
		image = [[[NSWorkspace sharedWorkspace] iconForFile:[url path]] copy];
		[image autorelease];
	}

	if (!image)
		return nil;

	image = mac_render_image_for_size(image, pointSize, templateImage);
	if (!image)
		return nil;

	return image;
}

static NSImage *mac_create_freerdp_vector_icon(CGFloat pointSize, BOOL monochrome, BOOL templateImage)
{
	if (pointSize <= 0.0)
		pointSize = 128.0;

	NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(pointSize, pointSize)] autorelease];
	[image lockFocus];
	[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];

	NSRect bounds = NSMakeRect(0, 0, pointSize, pointSize);
	CGFloat outerRadius = pointSize * 0.486;
	CGFloat innerRadius = pointSize * 0.382;
	CGFloat pupilRadius = pointSize * 0.181;
	NSPoint center = NSMakePoint(NSMidX(bounds), NSMidY(bounds));
	NSPoint pupilCenter = NSMakePoint(center.x + pointSize * 0.135, center.y + pointSize * 0.111);
	NSBezierPath *outerCircle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - outerRadius,
		                                                                        center.y - outerRadius,
		                                                                        outerRadius * 2.0,
		                                                                        outerRadius * 2.0)];
	NSBezierPath *innerCircle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - innerRadius,
		                                                                        center.y - innerRadius,
		                                                                        innerRadius * 2.0,
		                                                                        innerRadius * 2.0)];
	NSBezierPath *pupilCircle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(pupilCenter.x - pupilRadius,
		                                                                        pupilCenter.y - pupilRadius,
		                                                                        pupilRadius * 2.0,
		                                                                        pupilRadius * 2.0)];

	NSColor *primary = monochrome ? [NSColor blackColor]
		                            : [NSColor colorWithCalibratedRed:(7.0 / 255.0)
		                                                       green:(54.0 / 255.0)
		                                                        blue:(83.0 / 255.0)
		                                                       alpha:1.0];
	NSColor *paper = monochrome ? [NSColor whiteColor] : [NSColor whiteColor];
	NSColor *highlight = monochrome ? [NSColor whiteColor]
		                              : [NSColor colorWithCalibratedRed:1.0
		                                                         green:(250.0 / 255.0)
		                                                          blue:(234.0 / 255.0)
		                                                         alpha:1.0];

	[primary setFill];
	[outerCircle fill];
	[paper setFill];
	[innerCircle fill];
	[primary setFill];
	[pupilCircle fill];

	NSBezierPath *highlightPath = [NSBezierPath bezierPath];
	[highlightPath moveToPoint:NSMakePoint(center.x + pointSize * 0.228, center.y + pointSize * 0.269)];
	[highlightPath curveToPoint:NSMakePoint(center.x + pointSize * 0.189, center.y + pointSize * 0.161)
	                 controlPoint1:NSMakePoint(center.x + pointSize * 0.252, center.y + pointSize * 0.229)
	                 controlPoint2:NSMakePoint(center.x + pointSize * 0.240, center.y + pointSize * 0.187)];
	[highlightPath curveToPoint:NSMakePoint(center.x + pointSize * 0.064, center.y + pointSize * 0.089)
	                 controlPoint1:NSMakePoint(center.x + pointSize * 0.136, center.y + pointSize * 0.117)
	                 controlPoint2:NSMakePoint(center.x + pointSize * 0.087, center.y + pointSize * 0.106)];
	[highlightPath curveToPoint:NSMakePoint(center.x + pointSize * 0.017, center.y + pointSize * 0.208)
	                 controlPoint1:NSMakePoint(center.x + pointSize * 0.027, center.y + pointSize * 0.121)
	                 controlPoint2:NSMakePoint(center.x + pointSize * 0.005, center.y + pointSize * 0.168)];
	[highlightPath curveToPoint:NSMakePoint(center.x + pointSize * 0.141, center.y + pointSize * 0.302)
	                 controlPoint1:NSMakePoint(center.x + pointSize * 0.046, center.y + pointSize * 0.264)
	                 controlPoint2:NSMakePoint(center.x + pointSize * 0.114, center.y + pointSize * 0.317)];
	[highlightPath curveToPoint:NSMakePoint(center.x + pointSize * 0.228, center.y + pointSize * 0.269)
	                 controlPoint1:NSMakePoint(center.x + pointSize * 0.183, center.y + pointSize * 0.286)
	                 controlPoint2:NSMakePoint(center.x + pointSize * 0.216, center.y + pointSize * 0.282)];
	[highlight setFill];
	[highlightPath fill];

	[image unlockFocus];
	[image setTemplate:templateImage];
	return image;
}

static NSImage *mac_render_image_for_size(NSImage *source, CGFloat pointSize, BOOL templateImage)
{
	if (!source)
		return nil;

	if (pointSize <= 0.0)
		pointSize = MAX(source.size.width, source.size.height);

	CGFloat backingScale = 2.0;
	for (NSScreen *screen in [NSScreen screens])
		backingScale = MAX(backingScale, [screen backingScaleFactor]);

	const NSInteger pixelSize = MAX(1, (NSInteger)lrint(pointSize * backingScale));
	NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
	    initWithBitmapDataPlanes:NULL
	                  pixelsWide:pixelSize
	                  pixelsHigh:pixelSize
	               bitsPerSample:8
	             samplesPerPixel:4
	                    hasAlpha:YES
	                    isPlanar:NO
	              colorSpaceName:NSCalibratedRGBColorSpace
	                 bytesPerRow:0
	                bitsPerPixel:0] autorelease];
	if (!rep)
		return nil;

	NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	if (!graphicsContext)
		return nil;

	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:graphicsContext];
	[graphicsContext setImageInterpolation:NSImageInterpolationHigh];
	[[NSColor clearColor] set];
	NSRectFill(NSMakeRect(0, 0, pixelSize, pixelSize));
	[source drawInRect:NSMakeRect(0, 0, pixelSize, pixelSize)
	         fromRect:NSZeroRect
	        operation:NSCompositingOperationSourceOver
	         fraction:1.0];
	[NSGraphicsContext restoreGraphicsState];

	NSImage *rendered = [[[NSImage alloc] initWithSize:NSMakeSize(pointSize, pointSize)] autorelease];
	[rendered addRepresentation:rep];
	[rendered setTemplate:templateImage];
	return rendered;
}

static NSInteger mac_screen_index_for_screen(NSScreen *screen)
{
	NSArray *screens = [NSScreen screens];

	if (!screen)
		return NSNotFound;

	for (NSUInteger index = 0; index < [screens count]; index++)
	{
		if ([screens objectAtIndex:index] == screen)
			return (NSInteger)index;
	}

	return NSNotFound;
}

static NSScreen *mac_screen_for_index(NSInteger screenIndex)
{
	NSArray *screens = [NSScreen screens];

	if ((screenIndex >= 0) && ((NSUInteger)screenIndex < [screens count]))
		return [screens objectAtIndex:(NSUInteger)screenIndex];

	if ([NSScreen mainScreen])
		return [NSScreen mainScreen];

	return ([screens count] > 0) ? [screens objectAtIndex:0] : nil;
}

static NSString *mac_screen_identifier(NSScreen *screen)
{
	if (!screen)
		return nil;

	NSNumber *screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
	if (screenNumber)
		return [NSString stringWithFormat:@"display:%u", [screenNumber unsignedIntValue]];

	NSRect frame = [screen frame];
	return [NSString stringWithFormat:@"frame:%.0f:%.0f:%.0f:%.0f", frame.origin.x,
	                                  frame.origin.y, frame.size.width, frame.size.height];
}

static NSScreen *mac_screen_for_identifier(NSString *identifier)
{
	if (!identifier)
		return nil;

	for (NSScreen *screen in [NSScreen screens])
	{
		NSString *candidate = mac_screen_identifier(screen);
		if ([candidate isEqualToString:identifier])
			return screen;
	}

	return nil;
}

static NSScreen *mac_preferred_screen(NSWindow *window)
{
	if (_singleDelegate)
	{
		NSScreen *preferred = [_singleDelegate preferredScreen];
		if (preferred)
			return preferred;
	}

	if (window && [window screen])
		return [window screen];

	return mac_screen_for_index(NSNotFound);
}

static NSString *mac_display_title(NSScreen *screen, NSInteger screenIndex)
{
	NSRect frame = [screen frame];
	NSMutableString *title =
	    [NSMutableString stringWithFormat:@"Display %ld (%.0fx%.0f)", (long)screenIndex + 1,
	                                       frame.size.width, frame.size.height];

	if (screenIndex == mac_screen_index_for_screen([NSScreen mainScreen]))
		[title appendString:@" Primary"];

	return title;
}

static DISPLAY_CONTROL_MONITOR_LAYOUT mac_display_layout_for_screen(NSScreen *screen,
	                                                               BOOL useVisibleFrame,
	                                                               rdpSettings *settings)
{
	DISPLAY_CONTROL_MONITOR_LAYOUT layout = { 0 };
	NSRect frame = useVisibleFrame ? [screen visibleFrame] : [screen frame];
	NSNumber *screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
	const CGDirectDisplayID displayId = screenNumber ? [screenNumber unsignedIntValue] : 0;
	CGSize physicalSize = displayId ? CGDisplayScreenSize(displayId) : CGSizeZero;

	layout.Flags = DISPLAY_CONTROL_MONITOR_PRIMARY;
	layout.Left = 0;
	layout.Top = 0;
	layout.Width = (UINT32)frame.size.width;
	layout.Height = (UINT32)frame.size.height;
	layout.Orientation =
	    (frame.size.height > frame.size.width) ? ORIENTATION_PORTRAIT : ORIENTATION_LANDSCAPE;
	layout.PhysicalWidth = (UINT32)physicalSize.width;
	layout.PhysicalHeight = (UINT32)physicalSize.height;
	layout.DesktopScaleFactor =
	    freerdp_settings_get_uint32(settings, FreeRDP_DesktopScaleFactor);
	layout.DeviceScaleFactor = freerdp_settings_get_uint32(settings, FreeRDP_DeviceScaleFactor);

	if (layout.DesktopScaleFactor == 0)
		layout.DesktopScaleFactor = 100;
	if (layout.DeviceScaleFactor == 0)
		layout.DeviceScaleFactor = 100;

	return layout;
}
