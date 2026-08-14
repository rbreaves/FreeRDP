/**
 * FreeRDP: A Remote Desktop Protocol Implementation
 * macOS virtual desktop integration
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "MacVirtualDesktop.h"

#import <CoreGraphics/CoreGraphics.h>

#include <dlfcn.h>
#include <stdlib.h>

NSString *const MRDPVirtualDesktopIDKey = @"spaceID";
NSString *const MRDPVirtualDesktopDisplayIdentifierKey = @"displayIdentifier";
NSString *const MRDPVirtualDesktopDisplayIndexKey = @"displayIndex";
NSString *const MRDPVirtualDesktopIndexKey = @"desktopIndex";
NSString *const MRDPVirtualDesktopGlobalIndexKey = @"globalIndex";
NSString *const MRDPVirtualDesktopCurrentKey = @"current";

typedef int (*MRDPSpaceMainConnectionID)(void);
typedef CFArrayRef (*MRDPCopyManagedDisplaySpaces)(int connection);
typedef CFArrayRef (*MRDPCopySpacesForWindows)(int connection, int selector,
                                               CFArrayRef windowList);
typedef void (*MRDPMoveWindowsToManagedSpace)(int connection, CFArrayRef windowList,
                                               uint64_t spaceID);
typedef CGError (*MRDPSpaceSetCompatID)(int connection, uint64_t spaceID, int workspace);
typedef CGError (*MRDPSetWindowListWorkspace)(int connection, uint32_t *windowList,
                                              int windowCount, int workspace);

typedef struct
{
	MRDPSpaceMainConnectionID mainConnectionID;
	MRDPCopyManagedDisplaySpaces copyManagedDisplaySpaces;
	MRDPCopySpacesForWindows copySpacesForWindows;
	MRDPMoveWindowsToManagedSpace moveWindowsToManagedSpace;
	MRDPSpaceSetCompatID spaceSetCompatID;
	MRDPSetWindowListWorkspace setWindowListWorkspace;
} MRDPVirtualDesktopSymbols;

static MRDPVirtualDesktopSymbols g_Spaces;

static void *mac_virtual_desktop_symbol(const char *cgsName, const char *slsName)
{
	void *symbol = slsName ? dlsym(RTLD_DEFAULT, slsName) : NULL;
	if (!symbol)
		symbol = dlsym(RTLD_DEFAULT, cgsName);
	return symbol;
}

static void mac_load_virtual_desktop_symbols(void)
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		g_Spaces.mainConnectionID = (MRDPSpaceMainConnectionID)mac_virtual_desktop_symbol(
		    "CGSMainConnectionID", "SLSMainConnectionID");
		g_Spaces.copyManagedDisplaySpaces =
		    (MRDPCopyManagedDisplaySpaces)mac_virtual_desktop_symbol(
		        "CGSCopyManagedDisplaySpaces", "SLSCopyManagedDisplaySpaces");
		g_Spaces.copySpacesForWindows = (MRDPCopySpacesForWindows)mac_virtual_desktop_symbol(
		    "CGSCopySpacesForWindows", "SLSCopySpacesForWindows");
		g_Spaces.moveWindowsToManagedSpace =
		    (MRDPMoveWindowsToManagedSpace)mac_virtual_desktop_symbol(
		        "CGSMoveWindowsToManagedSpace", "SLSMoveWindowsToManagedSpace");
		g_Spaces.spaceSetCompatID = (MRDPSpaceSetCompatID)mac_virtual_desktop_symbol(
		    "CGSSpaceSetCompatID", "SLSSpaceSetCompatID");
		g_Spaces.setWindowListWorkspace =
		    (MRDPSetWindowListWorkspace)mac_virtual_desktop_symbol(
		        "CGSSetWindowListWorkspace", "SLSSetWindowListWorkspace");
	});
}

static NSNumber *mac_virtual_desktop_id(NSDictionary *space)
{
	id value = [space objectForKey:@"ManagedSpaceID"];
	if (![value isKindOfClass:[NSNumber class]])
		value = [space objectForKey:@"id64"];
	return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static BOOL mac_virtual_desktop_is_user_space(NSDictionary *space)
{
	id type = [space objectForKey:@"type"];
	return ![type isKindOfClass:[NSNumber class]] || ([type integerValue] == 0);
}

static NSArray *mac_virtual_desktop_window_numbers(NSArray *windows)
{
	NSMutableArray *windowNumbers = [NSMutableArray arrayWithCapacity:[windows count]];
	for (id candidate in windows)
	{
		if (![candidate isKindOfClass:[NSWindow class]])
			continue;

		NSInteger windowNumber = [(NSWindow *)candidate windowNumber];
		if ((windowNumber > 0) && ![windowNumbers containsObject:@(windowNumber)])
			[windowNumbers addObject:@(windowNumber)];
	}
	return windowNumbers;
}

/** Returns the union of the Spaces the supplied window numbers currently belong to. */
static NSArray *mac_spaces_for_window_numbers(NSArray *windowNumbers)
{
	if (!g_Spaces.mainConnectionID || !g_Spaces.copySpacesForWindows ||
	    ([windowNumbers count] == 0))
		return nil;

	CFArrayRef spacesRef =
	    g_Spaces.copySpacesForWindows(g_Spaces.mainConnectionID(), 0x7, (CFArrayRef)windowNumbers);
	if (!spacesRef)
		return nil;

	NSArray *spaces = [[(NSArray *)spacesRef copy] autorelease];
	CFRelease(spacesRef);
	return spaces;
}

/** Returns YES when every supplied window is known to sit on spaceID and nowhere else. */
static BOOL mac_window_numbers_all_on_space(NSArray *windowNumbers, NSNumber *spaceID)
{
	NSArray *spaces = mac_spaces_for_window_numbers(windowNumbers);
	if ([spaces count] != 1)
		return NO;

	id actual = [spaces objectAtIndex:0];
	return [actual isKindOfClass:[NSNumber class]] && [actual isEqualToNumber:spaceID];
}

NSString *mac_virtual_desktop_display_identifier(NSScreen *screen)
{
	NSNumber *screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
	if (!screenNumber)
		return nil;

	CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID([screenNumber unsignedIntValue]);
	if (!uuid)
		return nil;

	CFStringRef text = CFUUIDCreateString(kCFAllocatorDefault, uuid);
	CFRelease(uuid);
	if (!text)
		return nil;

	NSString *identifier = [[(NSString *)text copy] autorelease];
	CFRelease(text);
	return identifier;
}

NSArray *mac_virtual_desktops(void)
{
	mac_load_virtual_desktop_symbols();
	if (!g_Spaces.mainConnectionID || !g_Spaces.copyManagedDisplaySpaces)
		return [NSArray array];

	CFArrayRef managedRef = g_Spaces.copyManagedDisplaySpaces(g_Spaces.mainConnectionID());
	if (!managedRef)
		return [NSArray array];

	NSArray *managedDisplays = (NSArray *)managedRef;
	NSMutableArray *desktops = [NSMutableArray array];
	NSUInteger globalIndex = 1;
	for (NSUInteger displayIndex = 0; displayIndex < [managedDisplays count]; displayIndex++)
	{
		id candidate = [managedDisplays objectAtIndex:displayIndex];
		if (![candidate isKindOfClass:[NSDictionary class]])
			continue;

		NSDictionary *display = (NSDictionary *)candidate;
		NSArray *spaces = [display objectForKey:@"Spaces"];
		if (![spaces isKindOfClass:[NSArray class]])
			continue;

		id displayIdentifier = [display objectForKey:@"Display Identifier"];
		if (![displayIdentifier isKindOfClass:[NSString class]])
			displayIdentifier = @"";

		NSDictionary *currentSpace = [display objectForKey:@"Current Space"];
		NSNumber *currentSpaceID = [currentSpace isKindOfClass:[NSDictionary class]]
		                               ? mac_virtual_desktop_id(currentSpace)
		                               : nil;
		NSUInteger desktopIndex = 1;
		for (id spaceCandidate in spaces)
		{
			if (![spaceCandidate isKindOfClass:[NSDictionary class]])
				continue;

			NSDictionary *space = (NSDictionary *)spaceCandidate;
			NSNumber *spaceID = mac_virtual_desktop_id(space);
			if (!spaceID || !mac_virtual_desktop_is_user_space(space))
				continue;

			NSDictionary *desktop = [NSDictionary dictionaryWithObjectsAndKeys:
			    spaceID, MRDPVirtualDesktopIDKey, displayIdentifier,
			    MRDPVirtualDesktopDisplayIdentifierKey, @(displayIndex),
			    MRDPVirtualDesktopDisplayIndexKey, @(desktopIndex),
			    MRDPVirtualDesktopIndexKey, @(globalIndex), MRDPVirtualDesktopGlobalIndexKey,
			    @([spaceID isEqualToNumber:currentSpaceID]), MRDPVirtualDesktopCurrentKey, nil];
			[desktops addObject:desktop];
			desktopIndex++;
			globalIndex++;
		}
	}

	CFRelease(managedRef);
	return desktops;
}

BOOL mac_virtual_desktop_assignment_available(void)
{
	mac_load_virtual_desktop_symbols();
	if (!g_Spaces.mainConnectionID || !g_Spaces.copyManagedDisplaySpaces)
		return NO;

	return (g_Spaces.moveWindowsToManagedSpace != NULL) ||
	       (g_Spaces.spaceSetCompatID && g_Spaces.setWindowListWorkspace);
}

NSNumber *mac_virtual_desktop_for_window(NSWindow *window)
{
	mac_load_virtual_desktop_symbols();
	if (!window)
		return nil;

	NSArray *spaces = mac_spaces_for_window_numbers(mac_virtual_desktop_window_numbers(@[ window ]));
	if (([spaces count] > 0) && [[spaces objectAtIndex:0] isKindOfClass:[NSNumber class]])
		return [spaces objectAtIndex:0];
	return nil;
}

/*
 * The visible Space set is polled from timers running at 10 Hz, so cache it and drop the cache when
 * the WindowServer reports a Space switch.
 */
static NSSet *g_currentSpaceIDs;

static NSSet *mac_current_virtual_desktop_ids(void)
{
	static id observer;
	if (!observer)
	{
		observer = [[[NSWorkspace sharedWorkspace] notificationCenter]
		    addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
		                object:nil
		                 queue:[NSOperationQueue mainQueue]
		            usingBlock:^(NSNotification *notification) {
			            (void)notification;
			            [g_currentSpaceIDs release];
			            g_currentSpaceIDs = nil;
		            }];
		observer = [observer retain];
	}

	if (g_currentSpaceIDs)
		return g_currentSpaceIDs;

	NSMutableSet *identifiers = [NSMutableSet set];
	for (NSDictionary *desktop in mac_virtual_desktops())
	{
		if ([[desktop objectForKey:MRDPVirtualDesktopCurrentKey] boolValue])
			[identifiers addObject:[desktop objectForKey:MRDPVirtualDesktopIDKey]];
	}
	g_currentSpaceIDs = [identifiers copy];
	return g_currentSpaceIDs;
}

BOOL mac_virtual_desktop_is_current(NSNumber *spaceID)
{
	if (!spaceID)
		return YES;

	return [mac_current_virtual_desktop_ids() containsObject:spaceID];
}

NSString *mac_virtual_desktop_display_for_space(NSNumber *spaceID)
{
	if (!spaceID)
		return nil;

	for (NSDictionary *desktop in mac_virtual_desktops())
	{
		if ([[desktop objectForKey:MRDPVirtualDesktopIDKey] isEqualToNumber:spaceID])
			return [desktop objectForKey:MRDPVirtualDesktopDisplayIdentifierKey];
	}
	return nil;
}

NSNumber *mac_current_virtual_desktop_for_screen(NSScreen *screen)
{
	NSString *identifier = mac_virtual_desktop_display_identifier(screen);
	NSArray *screens = [NSScreen screens];
	const BOOL isMainScreen =
	    ([screens count] > 0) && (screen == [screens objectAtIndex:0]);
	NSNumber *fallback = nil;

	for (NSDictionary *desktop in mac_virtual_desktops())
	{
		if (![[desktop objectForKey:MRDPVirtualDesktopCurrentKey] boolValue])
			continue;

		NSNumber *spaceID = [desktop objectForKey:MRDPVirtualDesktopIDKey];
		NSString *desktopIdentifier =
		    [desktop objectForKey:MRDPVirtualDesktopDisplayIdentifierKey];

		if (identifier &&
		    ([desktopIdentifier caseInsensitiveCompare:identifier] == NSOrderedSame))
			return spaceID;
		if (isMainScreen &&
		    ([desktopIdentifier caseInsensitiveCompare:@"Main"] == NSOrderedSame))
			return spaceID;
		if (!fallback)
			fallback = spaceID;
	}

	return fallback;
}

NSArray *mac_windows_not_on_virtual_desktop(NSArray *windows, NSNumber *spaceID)
{
	mac_load_virtual_desktop_symbols();

	NSMutableArray *drifted = [NSMutableArray array];
	if (!spaceID || !g_Spaces.copySpacesForWindows)
		return drifted;

	NSArray *windowNumbers = mac_virtual_desktop_window_numbers(windows);
	if ([windowNumbers count] == 0)
		return drifted;

	/* One round trip covers the common case where nothing drifted. */
	if (mac_window_numbers_all_on_space(windowNumbers, spaceID))
		return drifted;

	for (id candidate in windows)
	{
		if (![candidate isKindOfClass:[NSWindow class]])
			continue;

		NSNumber *actual = mac_virtual_desktop_for_window((NSWindow *)candidate);
		if (actual && ![actual isEqualToNumber:spaceID])
			[drifted addObject:candidate];
	}
	return drifted;
}

static BOOL mac_move_window_numbers_managed(int connection, NSArray *windowNumbers,
                                            NSNumber *spaceID)
{
	if (!g_Spaces.moveWindowsToManagedSpace)
		return NO;

	g_Spaces.moveWindowsToManagedSpace(connection, (CFArrayRef)windowNumbers,
	                                   [spaceID unsignedLongLongValue]);

	/* Without a way to read back the assignment we have to trust the call. */
	if (!g_Spaces.copySpacesForWindows)
		return YES;

	return mac_window_numbers_all_on_space(windowNumbers, spaceID);
}

/*
 * Fallback used when CGSMoveWindowsToManagedSpace is missing or silently ignored (seen on some
 * macOS 14.5 builds): park the target Space on a private compatibility workspace, move the window
 * list onto that workspace, then detach the workspace again.
 */
static BOOL mac_move_window_numbers_compat(int connection, NSArray *windowNumbers,
                                           NSNumber *spaceID)
{
	if (!g_Spaces.spaceSetCompatID || !g_Spaces.setWindowListWorkspace)
		return NO;

	const int workspace = 0x4D465244; /* "MFRD", temporary compatibility workspace. */
	const uint64_t targetSpaceID = [spaceID unsignedLongLongValue];
	const NSUInteger count = [windowNumbers count];
	uint32_t *windowList = (uint32_t *)calloc(count, sizeof(uint32_t));
	if (!windowList)
		return NO;

	for (NSUInteger index = 0; index < count; index++)
		windowList[index] = [[windowNumbers objectAtIndex:index] unsignedIntValue];

	(void)g_Spaces.spaceSetCompatID(connection, targetSpaceID, workspace);
	CGError result = g_Spaces.setWindowListWorkspace(connection, windowList, (int)count, workspace);
	(void)g_Spaces.spaceSetCompatID(connection, targetSpaceID, 0);
	free(windowList);

	if (result != kCGErrorSuccess)
	{
		NSLog(@"Virtual desktop assignment to space %llu failed with CGError %d",
		      (unsigned long long)targetSpaceID, result);
		return NO;
	}
	return YES;
}

BOOL mac_move_windows_to_virtual_desktop(NSArray *windows, NSNumber *spaceID)
{
	mac_load_virtual_desktop_symbols();

	if (!spaceID || !mac_virtual_desktop_assignment_available())
		return NO;

	NSArray *windowNumbers = mac_virtual_desktop_window_numbers(windows);
	if ([windowNumbers count] == 0)
		return NO;

	NSMutableArray *priorBehaviors = [NSMutableArray array];
	for (id candidate in windows)
	{
		if (![candidate isKindOfClass:[NSWindow class]])
			continue;

		NSWindow *sessionWindow = (NSWindow *)candidate;
		NSWindowCollectionBehavior behavior = [sessionWindow collectionBehavior];
		[priorBehaviors addObject:@{ @"window" : sessionWindow, @"behavior" : @(behavior) }];
		/* Both bits override any explicit Space assignment, so they have to go first. */
		behavior &= ~(NSWindowCollectionBehaviorCanJoinAllSpaces |
		              NSWindowCollectionBehaviorMoveToActiveSpace);
		[sessionWindow setCollectionBehavior:behavior];
	}

	const int connection = g_Spaces.mainConnectionID();
	if (mac_move_window_numbers_managed(connection, windowNumbers, spaceID) ||
	    mac_move_window_numbers_compat(connection, windowNumbers, spaceID))
		return YES;

	for (NSDictionary *entry in priorBehaviors)
	{
		NSWindow *sessionWindow = [entry objectForKey:@"window"];
		[sessionWindow
		    setCollectionBehavior:(NSWindowCollectionBehavior)[[entry objectForKey:@"behavior"]
		                                                          unsignedIntegerValue]];
	}
	return NO;
}

void mac_move_windows_to_current_virtual_desktop(NSArray *windows)
{
	NSMutableArray *restoration = [NSMutableArray array];
	NSWindow *primaryWindow = nil;
	for (NSWindow *candidate in windows)
	{
		if (![candidate isKindOfClass:[NSWindow class]])
			continue;
		if (!primaryWindow)
			primaryWindow = candidate;

		NSWindowCollectionBehavior behavior = [candidate collectionBehavior];
		behavior &= ~NSWindowCollectionBehaviorCanJoinAllSpaces;
		behavior &= ~NSWindowCollectionBehaviorMoveToActiveSpace;
		[restoration addObject:@{ @"window" : candidate, @"behavior" : @(behavior) }];
		[candidate setCollectionBehavior:(behavior |
		                                  NSWindowCollectionBehaviorMoveToActiveSpace)];
		[candidate orderFrontRegardless];
	}
	if (primaryWindow)
	{
		/*
		 * MoveToActiveSpace is consumed when the primary window becomes active. Keep it set while
		 * activating the application; otherwise AppKit switches to the window's old Space instead.
		 */
		[NSApp activateIgnoringOtherApps:YES];
		[primaryWindow makeKeyAndOrderFront:nil];
	}

	NSArray *savedRestoration = [restoration copy];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		               for (NSDictionary *entry in savedRestoration)
		               {
			               NSWindow *candidate = [entry objectForKey:@"window"];
			               if (([candidate collectionBehavior] &
			                    NSWindowCollectionBehaviorMoveToActiveSpace) != 0)
			               {
				               [candidate setCollectionBehavior:
				                              (NSWindowCollectionBehavior)[[entry objectForKey:@"behavior"]
				                                                               unsignedIntegerValue]];
			               }
		               }
		               [savedRestoration release];
	               });
}

void mac_set_windows_visible_on_all_virtual_desktops(NSArray *windows, BOOL visibleOnAll)
{
	for (NSWindow *candidate in windows)
	{
		if (![candidate isKindOfClass:[NSWindow class]])
			continue;

		NSWindowCollectionBehavior behavior = [candidate collectionBehavior];
		behavior &= ~NSWindowCollectionBehaviorMoveToActiveSpace;
		if (visibleOnAll)
			behavior |= NSWindowCollectionBehaviorCanJoinAllSpaces;
		else
			behavior &= ~NSWindowCollectionBehaviorCanJoinAllSpaces;
		[candidate setCollectionBehavior:behavior];
	}
}
