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

#ifndef FREERDP_CLIENT_MAC_VIRTUAL_DESKTOP_H
#define FREERDP_CLIENT_MAC_VIRTUAL_DESKTOP_H

#import <Cocoa/Cocoa.h>

extern NSString *const MRDPVirtualDesktopIDKey;
extern NSString *const MRDPVirtualDesktopDisplayIdentifierKey;
extern NSString *const MRDPVirtualDesktopDisplayIndexKey;
extern NSString *const MRDPVirtualDesktopIndexKey;
extern NSString *const MRDPVirtualDesktopGlobalIndexKey;
extern NSString *const MRDPVirtualDesktopCurrentKey;

/**
 * Returns the regular user Spaces currently managed by macOS. The result is empty when the
 * WindowServer's optional Spaces interface is unavailable.
 */
NSArray *mac_virtual_desktops(void);

/** Returns whether direct assignment to a numbered Space is available on this macOS version. */
BOOL mac_virtual_desktop_assignment_available(void);

/** Returns the first Space containing window, or nil when it cannot be determined. */
NSNumber *mac_virtual_desktop_for_window(NSWindow *window);

/** Returns whether spaceID is the Space currently shown on its display. A nil spaceID is current. */
BOOL mac_virtual_desktop_is_current(NSNumber *spaceID);

/** Returns the Space currently shown on screen, falling back to any active Space. */
NSNumber *mac_current_virtual_desktop_for_screen(NSScreen *screen);

/** Returns the WindowServer display identifier of screen, or nil when it cannot be determined. */
NSString *mac_virtual_desktop_display_identifier(NSScreen *screen);

/** Returns the display identifier owning spaceID, or nil when the Space is unknown. */
NSString *mac_virtual_desktop_display_for_space(NSNumber *spaceID);

/** Returns the subset of windows that are no longer on spaceID. */
NSArray *mac_windows_not_on_virtual_desktop(NSArray *windows, NSNumber *spaceID);

/** Moves every supplied NSWindow to a regular user Space. */
BOOL mac_move_windows_to_virtual_desktop(NSArray *windows, NSNumber *spaceID);

/** Uses public AppKit behavior to pull the windows to the user's currently active Space. */
void mac_move_windows_to_current_virtual_desktop(NSArray *windows);

/** Makes the supplied windows visible in every Space, or restores single-Space behavior. */
void mac_set_windows_visible_on_all_virtual_desktops(NSArray *windows, BOOL visibleOnAll);

#endif /* FREERDP_CLIENT_MAC_VIRTUAL_DESKTOP_H */
