/**
 * FreeRDP: A Remote Desktop Protocol Implementation
 * MacFreeRDP
 *
 * Copyright 2012 Thomas Goddard
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

#include <winpr/windows.h>

#include "mf_client.h"
#import "mfreerdp.h"
#import "MRDPView.h"
#import "MRDPCursor.h"
#import "Clipboard.h"
#import "PasswordDialog.h"
#import "CertificateDialog.h"
#import "MacKeychain.h"
#import <QuartzCore/QuartzCore.h>

#include <winpr/crt.h>
#include <winpr/assert.h>
#include <winpr/input.h>
#include <winpr/synch.h>
#include <winpr/sysinfo.h>

#include <math.h>
#include <string.h>
#include <float.h>
#include <freerdp/constants.h>

#import "freerdp/freerdp.h"
#import "freerdp/types.h"
#import "freerdp/config.h"
#import "freerdp/channels/channels.h"
#import "freerdp/gdi/gdi.h"
#import "freerdp/gdi/dc.h"
#import "freerdp/gdi/region.h"
#import "freerdp/graphics.h"
#import "freerdp/client/file.h"
#import "freerdp/client/cmdline.h"
#import "freerdp/log.h"
#import "freerdp/input.h"
#import "freerdp/scancode.h"

#import <CoreGraphics/CoreGraphics.h>

#define TAG CLIENT_TAG("mac")

static BOOL mf_Pointer_New(rdpContext *context, rdpPointer *pointer);
static void mf_Pointer_Free(rdpContext *context, rdpPointer *pointer);
static BOOL mf_Pointer_Set(rdpContext *context, rdpPointer *pointer);
static BOOL mf_Pointer_SetNull(rdpContext *context);
static BOOL mf_Pointer_SetDefault(rdpContext *context);
static BOOL mf_Pointer_SetPosition(rdpContext *context, UINT32 x, UINT32 y);

static BOOL mac_begin_paint(rdpContext *context);
static BOOL mac_end_paint(rdpContext *context);
static BOOL mac_desktop_resize(rdpContext *context);

static void input_activity_cb(freerdp *instance);

static DWORD WINAPI mac_client_thread(void *param);
static BOOL mac_scroll_flags_from_deltas(CGFloat dx, CGFloat dy, UINT16 *outFlags);
static void windows_to_apple_cords(MRDPView *view, NSRect *r);
static CGContextRef mac_create_bitmap_context(rdpContext *context);
static BOOL mac_is_chroma_key_pixel(const mfContext *mfc, uint32_t pixel);
static UINT32 mac_chroma_key_max_diff(const mfContext *mfc, uint32_t pixel);
static void mac_apply_chroma_key_feathering(const mfContext *mfc, const uint32_t *source,
                                            uint32_t *buffer, size_t width, size_t height);
static BOOL mac_additional_transparency_for_pixel(const mfContext *mfc, uint32_t pixel,
	                                             UINT32 *transparency, BOOL *blur);
static void mac_release_mask_data(void *info, const void *data, size_t size);
static BOOL mac_is_resize_cursor(NSCursor *cursor);
static BOOL mac_view_point_to_buffer_point(MRDPView *view, const mfContext *mfc,
	                                       rdpContext *context, NSPoint viewPoint,
	                                       int *outX, int *outY);
static BOOL mac_has_chroma_key_margin(const mfContext *mfc, const rdpGdi *gdi, int x, int y,
	                                  int radius);
static NSRect mac_smart_sizing_display_rect(MRDPView *view, rdpContext *context);
static BOOL mac_send_rdp_scancode(rdpInput *input, UINT32 rdpScancode);
static NSScreen *mac_startup_preferred_screen(void);
static BOOL mac_screen_is_selected(rdpSettings *settings, UINT32 screenIndex);
static NSRect mac_pseudo_fullscreen_frame(NSScreen *screen);
static NSRect mac_safe_screen_frame(NSScreen *screen);
static BOOL mac_monitor_from_screen(NSScreen *screen, UINT32 screenIndex, mfContext *mfc,
                                    BOOL useVisibleFrame, rdpMonitor *monitor);
static UINT32 mac_taskbar_hide_size_for_context(mfContext *mfc, NSRect frame);
static NSRect mac_remote_frame_with_taskbar(NSRect frame, mfContext *mfc);
static NSString *mac_dialog_string_from_utf8(const char *value);
static NSString *mac_dialog_setting_string(const rdpSettings *settings, size_t key);
static NSString *mac_resolve_stored_password(NSString *serverName, NSString *username,
	                                         NSString *domain);
static UINT32 mac_char_to_scancode(unichar character, BOOL *outNeedsShift);
static BOOL mac_modifier_keyswap_applies(const mfContext *mfc, const rdpSettings *settings);
static MF_MODIFIER_KEYSWAP_MODE mac_modifier_keyswap_mode(const mfContext *mfc,
                                                          const rdpSettings *settings);
static UINT32 mac_modifier_keyswap_scancode(UINT32 flag, MF_MODIFIER_KEYSWAP_MODE mode,
                                            UINT32 scancode);
static DWORD fixKeyCode(DWORD keyCode, unichar keyChar, enum APPLE_KEYBOARD_TYPE type);
static BOOL updateFlagStates(rdpInput *input, UINT32 modFlags, UINT32 aKbdModFlags,
                             MF_MODIFIER_KEYSWAP_MODE keyswapMode);
static BOOL ensureModifierFlagStates(rdpInput *input, UINT32 modFlags,
                                     MF_MODIFIER_KEYSWAP_MODE keyswapMode);
static BOOL releaseFlagStates(rdpInput *input, UINT32 aKbdModFlags,
                              MF_MODIFIER_KEYSWAP_MODE keyswapMode);

static NSString *const MRDPPreferredScreenIdentifierKey = @"MRDPPreferredScreenIdentifier";

static const int64_t MRDP_PASS_THROUGH_EVENT_TAG = 0x4D52445050544852LL;
static const NSEventMask MRDP_PASS_THROUGH_MONITOR_MASK =
	NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged | NSEventMaskRightMouseDragged |
	NSEventMaskOtherMouseDragged | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown |
	NSEventMaskOtherMouseDown;

typedef struct
{
	int x1;
	int y1;
	int x2;
	int y2;
} MRDPWindowDragCandidateRect;

static int mrdp_int_compare(const void *left, const void *right)
{
	const int a = *(const int *)left;
	const int b = *(const int *)right;
	return (a > b) - (a < b);
}

static BOOL mrdp_add_unique_edge(int *edges, size_t *count, size_t capacity, int value)
{
	for (size_t i = 0; i < *count; i++)
	{
		if (edges[i] == value)
			return TRUE;
	}

	if (*count >= capacity)
		return FALSE;

	edges[(*count)++] = value;
	return TRUE;
}

static UINT32 mrdp_integral_rect_count(const UINT32 *integral, size_t stride, int x1, int y1,
                                       int x2, int y2)
{
	return integral[(size_t)y2 * stride + (size_t)x2] -
	       integral[(size_t)y1 * stride + (size_t)x2] -
	       integral[(size_t)y2 * stride + (size_t)x1] +
	       integral[(size_t)y1 * stride + (size_t)x1];
}

static double mrdp_edge_support(const uint8_t *edgeMask, size_t stride, int start, int end,
                                int fixed, BOOL horizontal)
{
	UINT32 count = 0;
	UINT32 support = 0;

	if (end <= start)
		return 0.0;

	for (int i = start; i < end; i++)
	{
		count++;
		if (horizontal ? edgeMask[(size_t)fixed * stride + (size_t)i]
		               : edgeMask[(size_t)i * stride + (size_t)fixed])
			support++;
	}

	return count ? (double)support / (double)count : 0.0;
}

static BOOL mrdp_reconstruct_window_drag_rect(const uint8_t *mask, const UINT32 *component,
                                              size_t componentCount, size_t width, size_t height,
                                              int startX, int startY,
                                              MRDPWindowDragCandidateRect *outRect)
{
	if (!mask || !component || !outRect || (componentCount == 0) || (width == 0) ||
	    (height == 0))
		return FALSE;

	int minX = (int)width;
	int minY = (int)height;
	int maxX = 0;
	int maxY = 0;
	for (size_t i = 0; i < componentCount; i++)
	{
		const int x = (int)(component[i] % width);
		const int y = (int)(component[i] / width);
		minX = MIN(minX, x);
		minY = MIN(minY, y);
		maxX = MAX(maxX, x);
		maxY = MAX(maxY, y);
	}

	const int boxW = maxX - minX + 1;
	const int boxH = maxY - minY + 1;
	const size_t boxArea = (size_t)boxW * (size_t)boxH;
	if ((boxW <= 0) || (boxH <= 0))
		return FALSE;

	if ((double)componentCount >= (double)boxArea * 0.96)
	{
		*outRect = (MRDPWindowDragCandidateRect){ minX, minY, maxX + 1, maxY + 1 };
		return TRUE;
	}

	UINT32 *verticalEdges = (UINT32 *)calloc(width + 1, sizeof(UINT32));
	UINT32 *horizontalEdges = (UINT32 *)calloc(height + 1, sizeof(UINT32));
	UINT32 *integral = (UINT32 *)calloc((width + 1) * (height + 1), sizeof(UINT32));
	uint8_t *verticalEdgeMask = (uint8_t *)calloc((width + 1) * height, sizeof(uint8_t));
	uint8_t *horizontalEdgeMask = (uint8_t *)calloc((height + 1) * width, sizeof(uint8_t));
	if (!verticalEdges || !horizontalEdges || !integral || !verticalEdgeMask ||
	    !horizontalEdgeMask)
	{
		free(verticalEdges);
		free(horizontalEdges);
		free(integral);
		free(verticalEdgeMask);
		free(horizontalEdgeMask);
		return FALSE;
	}

	for (size_t i = 0; i < componentCount; i++)
	{
		const int x = (int)(component[i] % width);
		const int y = (int)(component[i] / width);
		const size_t index = (size_t)y * width + (size_t)x;
		if ((x == 0) || !mask[index - 1])
		{
			verticalEdges[x]++;
			verticalEdgeMask[(size_t)y * (width + 1) + (size_t)x] = 1;
		}
		if ((x == (int)width - 1) || !mask[index + 1])
		{
			verticalEdges[x + 1]++;
			verticalEdgeMask[(size_t)y * (width + 1) + (size_t)(x + 1)] = 1;
		}
		if ((y == 0) || !mask[index - width])
		{
			horizontalEdges[y]++;
			horizontalEdgeMask[(size_t)y * width + (size_t)x] = 1;
		}
		if ((y == (int)height - 1) || !mask[index + width])
		{
			horizontalEdges[y + 1]++;
			horizontalEdgeMask[(size_t)(y + 1) * width + (size_t)x] = 1;
		}
	}

	const size_t integralStride = width + 1;
	for (size_t y = 0; y < height; y++)
	{
		UINT32 row = 0;
		for (size_t x = 0; x < width; x++)
		{
			row += mask[y * width + x] ? 1U : 0U;
			integral[(y + 1) * integralStride + (x + 1)] =
			    integral[y * integralStride + (x + 1)] + row;
		}
	}

	enum
	{
		MRDP_MAX_RECONSTRUCTION_EDGES = 96
	};
	int xEdges[MRDP_MAX_RECONSTRUCTION_EDGES];
	int yEdges[MRDP_MAX_RECONSTRUCTION_EDGES];
	size_t xEdgeCount = 0;
	size_t yEdgeCount = 0;
	const UINT32 minEdgeSupport =
	    (UINT32)MAX(4, MIN(32, (int)(sqrt((double)componentCount) / 6.0)));

	mrdp_add_unique_edge(xEdges, &xEdgeCount, MRDP_MAX_RECONSTRUCTION_EDGES, minX);
	mrdp_add_unique_edge(xEdges, &xEdgeCount, MRDP_MAX_RECONSTRUCTION_EDGES, maxX + 1);
	mrdp_add_unique_edge(yEdges, &yEdgeCount, MRDP_MAX_RECONSTRUCTION_EDGES, minY);
	mrdp_add_unique_edge(yEdges, &yEdgeCount, MRDP_MAX_RECONSTRUCTION_EDGES, maxY + 1);

	for (size_t x = 0; x <= width; x++)
	{
		if (verticalEdges[x] >= minEdgeSupport)
			mrdp_add_unique_edge(xEdges, &xEdgeCount, MRDP_MAX_RECONSTRUCTION_EDGES, (int)x);
	}
	for (size_t y = 0; y <= height; y++)
	{
		if (horizontalEdges[y] >= minEdgeSupport)
			mrdp_add_unique_edge(yEdges, &yEdgeCount, MRDP_MAX_RECONSTRUCTION_EDGES, (int)y);
	}

	qsort(xEdges, xEdgeCount, sizeof(int), mrdp_int_compare);
	qsort(yEdges, yEdgeCount, sizeof(int), mrdp_int_compare);

	BOOL found = FALSE;
	double bestScore = -DBL_MAX;
	MRDPWindowDragCandidateRect bestRect = { minX, minY, maxX + 1, maxY + 1 };
	const int minCandidateW = MIN(48, MAX(12, (int)width / 32));
	const int minCandidateH = MIN(32, MAX(12, (int)height / 48));

	for (size_t xi1 = 0; xi1 < xEdgeCount; xi1++)
	{
		for (size_t xi2 = xi1 + 1; xi2 < xEdgeCount; xi2++)
		{
			const int x1 = xEdges[xi1];
			const int x2 = xEdges[xi2];
			if ((x2 - x1 < minCandidateW) || (startX < x1) || (startX >= x2))
				continue;

			for (size_t yi1 = 0; yi1 < yEdgeCount; yi1++)
			{
				for (size_t yi2 = yi1 + 1; yi2 < yEdgeCount; yi2++)
				{
					const int y1 = yEdges[yi1];
					const int y2 = yEdges[yi2];
					if ((y2 - y1 < minCandidateH) || (startY < y1) || (startY >= y2))
						continue;

					const UINT32 visible =
					    mrdp_integral_rect_count(integral, integralStride, x1, y1, x2, y2);
					if (visible < minEdgeSupport)
						continue;

					const double candidateArea = (double)(x2 - x1) * (double)(y2 - y1);
					const double fill = (double)visible / candidateArea;
					const double top =
					    mrdp_edge_support(horizontalEdgeMask, width, x1, x2, y1, TRUE);
					const double bottom =
					    mrdp_edge_support(horizontalEdgeMask, width, x1, x2, y2, TRUE);
					const double left =
					    mrdp_edge_support(verticalEdgeMask, width + 1, y1, y2, x1, FALSE);
					const double right =
					    mrdp_edge_support(verticalEdgeMask, width + 1, y1, y2, x2, FALSE);
					if ((top < 0.20) || ((top + bottom + left + right) < 0.85))
						continue;
					const double downward =
					    1.0 - MIN(1.0, (double)(startY - y1) / MAX(1.0, (double)(y2 - y1)));
					double boundary = 0.0;
					if ((x1 == 0) || (x2 == (int)width))
						boundary += 0.25;
					if ((y1 == 0) || (y2 == (int)height))
						boundary += 0.25;

					double score = (top * 4.0) + ((left + right) * 1.5) + bottom +
					               (fill * 2.0) + (downward * 1.5) + boundary;
					score += sqrt(candidateArea / MAX(1.0, (double)componentCount));

					if (!found || (score > bestScore))
					{
						found = TRUE;
						bestScore = score;
						bestRect = (MRDPWindowDragCandidateRect){ x1, y1, x2, y2 };
					}
				}
			}
		}
	}

	free(verticalEdges);
	free(horizontalEdges);
	free(integral);
	free(verticalEdgeMask);
	free(horizontalEdgeMask);

	if (!found)
		return FALSE;

	*outRect = bestRect;
	return TRUE;
}

@implementation MRDPView

@synthesize is_connected;

- (int)rdpStart:(rdpContext *)rdp_context
{
	rdpSettings *settings;
	EmbedWindowEventArgs e;
	[self initializeView];

	WINPR_ASSERT(rdp_context);
	context = rdp_context;
	mfc = (mfContext *)rdp_context;
	chromaKeyRepaintRequested = NO;
	[self startMousePassThroughMonitor];

	instance = context->instance;
	WINPR_ASSERT(instance);

	settings = context->settings;
	WINPR_ASSERT(settings);

	EventArgsInit(&e, "mfreerdp");
	e.embed = TRUE;
	e.handle = (void *)self;
	if (PubSub_OnEmbedWindow(context->pubSub, context, &e) < 0)
		return -1;

	NSScreen *screen = mac_startup_preferred_screen();
	NSRect screenFrame = [screen frame];
	NSRect visibleFrame = mac_pseudo_fullscreen_frame(screen);

	if (!mac_apply_display_properties(mfc, mfc->fullscreen_mode == 2))
		return -1;

	if (!freerdp_settings_get_bool(settings, FreeRDP_UseMultimon) &&
	    freerdp_settings_get_bool(settings, FreeRDP_Fullscreen) && mfc->fullscreen_mode != 2 &&
	    !freerdp_settings_get_bool(settings, FreeRDP_SmartSizing))
	{
		if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, screenFrame.size.width))
			return -1;
		if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, screenFrame.size.height))
			return -1;
	}
	else if (!freerdp_settings_get_bool(settings, FreeRDP_UseMultimon) &&
	         (mfc->fullscreen_mode == 2) &&
	         !freerdp_settings_get_bool(settings, FreeRDP_SmartSizing))
	{
		NSRect remoteFrame = mac_remote_frame_with_taskbar(visibleFrame, mfc);
		if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth,
		                                 (UINT32)remoteFrame.size.width))
			return -1;
		if (!freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight,
		                                 (UINT32)remoteFrame.size.height))
			return -1;
	}

	mfc->client_height = freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);
	mfc->client_width = freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);

	if (!(mfc->common.thread =
	          CreateThread(nullptr, 0, mac_client_thread, (void *)context, 0, &mfc->mainThreadId)))
	{
		WLog_ERR(TAG, "failed to create client thread");
		return -1;
	}

	return 0;
}

static NSScreen *mac_startup_preferred_screen(void)
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *identifier = [defaults stringForKey:MRDPPreferredScreenIdentifierKey];

	if (identifier)
	{
		for (NSScreen *screen in [NSScreen screens])
		{
			NSNumber *screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
			NSString *candidate = nil;

			if (screenNumber)
				candidate = [NSString stringWithFormat:@"display:%u", [screenNumber unsignedIntValue]];
			else
			{
				NSRect frame = [screen frame];
				candidate = [NSString stringWithFormat:@"frame:%.0f:%.0f:%.0f:%.0f",
				                                   frame.origin.x, frame.origin.y,
				                                   frame.size.width, frame.size.height];
			}

			if ([candidate isEqualToString:identifier])
				return screen;
		}
	}

	return [NSScreen mainScreen] ?: [[NSScreen screens] firstObject];
}

static BOOL mac_screen_is_selected(rdpSettings *settings, UINT32 screenIndex)
{
	const UINT32 count = freerdp_settings_get_uint32(settings, FreeRDP_NumMonitorIds);

	if (count == 0)
		return TRUE;

	for (UINT32 i = 0; i < count; i++)
	{
		const UINT32 *id =
		    freerdp_settings_get_pointer_array(settings, FreeRDP_MonitorIds, i);
		if (id && (*id == screenIndex))
			return TRUE;
	}

	return FALSE;
}

static NSRect mac_pseudo_fullscreen_frame(NSScreen *screen)
{
	if (!screen)
		return NSZeroRect;

	NSRect frame = [screen frame];
	NSRect visibleFrame = [screen visibleFrame];
	CGFloat menuBarHeight = NSMaxY(frame) - NSMaxY(visibleFrame);
	if (menuBarHeight < 1.0)
	{
		NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
		menuBarHeight = statusBar ? [statusBar thickness] : 24.0;
	}
	menuBarHeight = ceil(MAX(menuBarHeight, 24.0));

	frame.size.height = MAX(1.0, NSHeight(frame) - menuBarHeight);
	return frame;
}

static NSRect mac_safe_screen_frame(NSScreen *screen)
{
	if (!screen)
		return NSZeroRect;

	NSRect screenFrame = [screen frame];
	NSRect safeFrame = [screen visibleFrame];
	CGFloat reservedTop = NSMaxY(screenFrame) - NSMaxY(safeFrame);
	if (reservedTop < 1.0)
	{
		NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
		reservedTop = statusBar ? [statusBar thickness] : 24.0;
	}
	reservedTop = ceil(MAX(reservedTop, 24.0));

	const CGFloat safeMaxY = NSMaxY(screenFrame) - reservedTop;
	if (NSMaxY(safeFrame) > safeMaxY)
		safeFrame.size.height = MAX(1.0, safeFrame.size.height - (NSMaxY(safeFrame) - safeMaxY));

	if (NSHeight(safeFrame) > (safeMaxY - NSMinY(safeFrame)))
		safeFrame.size.height = MAX(1.0, safeMaxY - NSMinY(safeFrame));

	return safeFrame;
}

static UINT32 mac_taskbar_hide_size_for_context(mfContext *mfc, NSRect frame)
{
	if (!mfc || !mfc->taskbarHide || (mfc->fullscreen_mode != 2) ||
	    (mfc->taskbarHideHeight == 0))
		return 0;

	const UINT32 position = mfc->taskbarHidePosition;
	const CGFloat limit = (position == 0 || position == 1) ? NSHeight(frame) : NSWidth(frame);
	return (UINT32)MIN((CGFloat)mfc->taskbarHideHeight, MAX(0.0, limit - 1.0));
}

static NSRect mac_remote_frame_with_taskbar(NSRect frame, mfContext *mfc)
{
	const UINT32 size = mac_taskbar_hide_size_for_context(mfc, frame);
	if (size == 0)
		return frame;

	if (mfc->taskbarHidePosition == 0)
	{
		frame.origin.y -= size;
		frame.size.height += size;
	}
	else if (mfc->taskbarHidePosition == 1)
		frame.size.height += size;
	else if (mfc->taskbarHidePosition == 2)
	{
		frame.origin.x -= size;
		frame.size.width += size;
	}
	else if (mfc->taskbarHidePosition == 3)
		frame.size.width += size;

	return frame;
}

static BOOL mac_monitor_from_screen(NSScreen *screen, UINT32 screenIndex, mfContext *mfc,
                                    BOOL useVisibleFrame, rdpMonitor *monitor)
{
	if (!screen || !mfc || !mfc->common.context.settings || !monitor)
		return FALSE;

	rdpSettings *settings = mfc->common.context.settings;
	NSRect screenFrame = [screen frame];
	NSRect frame = mac_remote_frame_with_taskbar(useVisibleFrame ? mac_pseudo_fullscreen_frame(screen)
	                                                             : mac_safe_screen_frame(screen),
	                                            mfc);
	NSNumber *screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
	const CGDirectDisplayID displayId = screenNumber ? [screenNumber unsignedIntValue] : 0;
	CGSize physicalSize = displayId ? CGDisplayScreenSize(displayId) : CGSizeZero;
	const BOOL primary = (screen == [NSScreen mainScreen]) ||
	                     (screenFrame.origin.x == 0 && screenFrame.origin.y == 0);

	if ((frame.size.width <= 0) || (frame.size.height <= 0))
		return FALSE;

	*monitor = (rdpMonitor){ 0 };
	monitor->orig_screen = screenIndex;
	monitor->x = (INT32)round(frame.origin.x);
	monitor->y = (INT32)round(-NSMaxY(frame));
	monitor->width = (INT32)round(frame.size.width);
	monitor->height = (INT32)round(frame.size.height);
	monitor->is_primary = primary ? TRUE : FALSE;
	monitor->attributes.physicalWidth = (UINT32)round(physicalSize.width);
	monitor->attributes.physicalHeight = (UINT32)round(physicalSize.height);
	monitor->attributes.orientation =
	    (frame.size.height > frame.size.width) ? ORIENTATION_PORTRAIT : ORIENTATION_LANDSCAPE;
	monitor->attributes.desktopScaleFactor =
	    freerdp_settings_get_uint32(settings, FreeRDP_DesktopScaleFactor);
	monitor->attributes.deviceScaleFactor =
	    freerdp_settings_get_uint32(settings, FreeRDP_DeviceScaleFactor);

	if (monitor->attributes.desktopScaleFactor == 0)
		monitor->attributes.desktopScaleFactor = 100;
	if (monitor->attributes.deviceScaleFactor == 0)
		monitor->attributes.deviceScaleFactor = 100;

	return TRUE;
}

BOOL mac_apply_display_properties(mfContext *mfc, BOOL useVisibleFrame)
{
	if (!mfc || !mfc->common.context.settings)
		return FALSE;

	rdpSettings *settings = mfc->common.context.settings;
	if (!freerdp_settings_get_bool(settings, FreeRDP_UseMultimon))
		return TRUE;

	NSArray *screens = [NSScreen screens];
	const NSUInteger screenCount = [screens count];
	if (screenCount == 0)
		return FALSE;

	rdpMonitor *monitors = (rdpMonitor *)calloc(screenCount, sizeof(rdpMonitor));
	if (!monitors)
		return FALSE;

	UINT32 monitorCount = 0;
	for (NSUInteger i = 0; i < screenCount; i++)
	{
		if (!mac_screen_is_selected(settings, (UINT32)i))
			continue;

		rdpMonitor monitor = { 0 };
		if (!mac_monitor_from_screen([screens objectAtIndex:i], (UINT32)i, mfc,
		                             useVisibleFrame, &monitor))
		{
			free(monitors);
			return FALSE;
		}

		monitors[monitorCount++] = monitor;
	}

	if (monitorCount == 0)
	{
		free(monitors);
		return FALSE;
	}

	BOOL hasPrimary = FALSE;
	for (UINT32 i = 0; i < monitorCount; i++)
	{
		if (monitors[i].is_primary)
		{
			hasPrimary = TRUE;
			break;
		}
	}
	if (!hasPrimary)
		monitors[0].is_primary = TRUE;

	BOOL success = freerdp_settings_set_monitor_def_array_sorted(settings, monitors, monitorCount);
	if (success && freerdp_settings_get_bool(settings, FreeRDP_UseMultimon))
	{
		INT32 minX = monitors[0].x;
		INT32 minY = monitors[0].y;
		INT32 maxX = monitors[0].x + monitors[0].width;
		INT32 maxY = monitors[0].y + monitors[0].height;

		for (UINT32 i = 1; i < monitorCount; i++)
		{
			minX = MIN(minX, monitors[i].x);
			minY = MIN(minY, monitors[i].y);
			maxX = MAX(maxX, monitors[i].x + monitors[i].width);
			maxY = MAX(maxY, monitors[i].y + monitors[i].height);
		}

		success = freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth,
		                                      (UINT32)(maxX - minX)) &&
		          freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight,
		                                      (UINT32)(maxY - minY));
	}

	free(monitors);
	return success;
}

static NSString *mac_dialog_string_from_utf8(const char *value)
{
	if (!value)
		return nil;

	NSString *string = [NSString stringWithCString:value encoding:NSUTF8StringEncoding];
	if (!string || ([string length] == 0))
		return nil;

	return string;
}

static NSString *mac_dialog_setting_string(const rdpSettings *settings, size_t key)
{
	if (!settings)
		return nil;

	return mac_dialog_string_from_utf8(freerdp_settings_get_string(settings, key));
}

static NSString *mac_resolve_stored_password(NSString *serverName, NSString *username,
	                                         NSString *domain)
{
	NSString *password = nil;

	if (username && ([username length] > 0))
		password = mac_keychain_copy_password(serverName, username, domain);

	if (!password && username && ([username length] > 0) && (!domain || ([domain length] == 0)))
	{
		NSRange slash = [username rangeOfString:@"\\"];
		if (slash.location != NSNotFound && slash.location > 0 && (slash.location + 1) < [username length])
		{
			NSString *splitDomain = [username substringToIndex:slash.location];
			NSString *splitUser = [username substringFromIndex:(slash.location + 1)];
			password = mac_keychain_copy_password(serverName, splitUser, splitDomain);
		}
	}

	if (!password && username && ([username length] > 0) && domain && ([domain length] > 0))
	{
		password = mac_keychain_copy_password(serverName, username, nil);
		if (!password)
		{
			NSString *combinedUser = [NSString stringWithFormat:@"%@\\%@", domain, username];
			password = mac_keychain_copy_password(serverName, combinedUser, nil);
		}
	}

	return password;
}

static UINT32 mac_char_to_scancode(unichar character, BOOL *outNeedsShift)
{
	*outNeedsShift = FALSE;

	static const UINT32 letterScancodes[26] = {
	    RDP_SCANCODE_KEY_A, RDP_SCANCODE_KEY_B, RDP_SCANCODE_KEY_C, RDP_SCANCODE_KEY_D,
	    RDP_SCANCODE_KEY_E, RDP_SCANCODE_KEY_F, RDP_SCANCODE_KEY_G, RDP_SCANCODE_KEY_H,
	    RDP_SCANCODE_KEY_I, RDP_SCANCODE_KEY_J, RDP_SCANCODE_KEY_K, RDP_SCANCODE_KEY_L,
	    RDP_SCANCODE_KEY_M, RDP_SCANCODE_KEY_N, RDP_SCANCODE_KEY_O, RDP_SCANCODE_KEY_P,
	    RDP_SCANCODE_KEY_Q, RDP_SCANCODE_KEY_R, RDP_SCANCODE_KEY_S, RDP_SCANCODE_KEY_T,
	    RDP_SCANCODE_KEY_U, RDP_SCANCODE_KEY_V, RDP_SCANCODE_KEY_W, RDP_SCANCODE_KEY_X,
	    RDP_SCANCODE_KEY_Y, RDP_SCANCODE_KEY_Z
	};
	static const UINT32 digitScancodes[10] = {
	    RDP_SCANCODE_KEY_0, RDP_SCANCODE_KEY_1, RDP_SCANCODE_KEY_2, RDP_SCANCODE_KEY_3,
	    RDP_SCANCODE_KEY_4, RDP_SCANCODE_KEY_5, RDP_SCANCODE_KEY_6, RDP_SCANCODE_KEY_7,
	    RDP_SCANCODE_KEY_8, RDP_SCANCODE_KEY_9
	};

	if (character >= 'a' && character <= 'z')
		return letterScancodes[character - 'a'];

	if (character >= 'A' && character <= 'Z') {
		*outNeedsShift = TRUE;
		return letterScancodes[character - 'A'];
	}

	if (character >= '0' && character <= '9')
		return digitScancodes[character - '0'];

	switch (character) {
		case ' ': return RDP_SCANCODE_SPACE;
		case '\t': return RDP_SCANCODE_TAB;
		case '!': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_1;
		case '@': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_2;
		case '#': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_3;
		case '$': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_4;
		case '%': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_5;
		case '^': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_6;
		case '&': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_7;
		case '*': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_8;
		case '(': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_9;
		case ')': *outNeedsShift = TRUE; return RDP_SCANCODE_KEY_0;
		case '-': return RDP_SCANCODE_OEM_MINUS;
		case '_': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_MINUS;
		case '=': return RDP_SCANCODE_OEM_PLUS;
		case '+': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_PLUS;
		case '[': return RDP_SCANCODE_OEM_4;
		case '{': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_4;
		case ']': return RDP_SCANCODE_OEM_6;
		case '}': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_6;
		case ';': return RDP_SCANCODE_OEM_1;
		case ':': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_1;
		case '\'': return RDP_SCANCODE_OEM_7;
		case '"': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_7;
		case ',': return RDP_SCANCODE_OEM_COMMA;
		case '<': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_COMMA;
		case '.': return RDP_SCANCODE_OEM_PERIOD;
		case '>': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_PERIOD;
		case '/': return RDP_SCANCODE_OEM_2;
		case '?': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_2;
		case '\\': return RDP_SCANCODE_OEM_5;
		case '|': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_5;
		case '`': return RDP_SCANCODE_OEM_3;
		case '~': *outNeedsShift = TRUE; return RDP_SCANCODE_OEM_3;
		default: return 0;
	}
}

DWORD WINAPI mac_client_thread(void *param)
{
	@autoreleasepool
	{
		int status;
		DWORD rc;
		HANDLE events[16] = WINPR_C_ARRAY_INIT;
		HANDLE inputEvent;
		DWORD nCount;
		DWORD nCountTmp;
		DWORD nCountBase;
		rdpContext *context = (rdpContext *)param;
		mfContext *mfc = (mfContext *)context;
		freerdp *instance = context->instance;
		MRDPView *view = mfc->view;
		rdpSettings *settings = context->settings;
		status = freerdp_connect(context->instance);

		if (!status)
		{
			[view setIs_connected:0];
			return 0;
		}

		[view setIs_connected:1];
		nCount = 0;
		events[nCount++] = mfc->stopEvent;

		if (!(inputEvent =
		          freerdp_get_message_queue_event_handle(instance, FREERDP_INPUT_MESSAGE_QUEUE)))
		{
			WLog_ERR(TAG, "failed to get input event handle");
			goto disconnect;
		}

		events[nCount++] = inputEvent;

		nCountBase = nCount;

		while (!freerdp_shall_disconnect_context(instance->context))
		{
			nCount = nCountBase;
			{
				if (!(nCountTmp = freerdp_get_event_handles(context, &events[nCount], 16 - nCount)))
				{
					WLog_ERR(TAG, "freerdp_get_event_handles failed");
					break;
				}

				nCount += nCountTmp;
			}
			rc = WaitForMultipleObjects(nCount, events, FALSE, INFINITE);

			if (rc >= (WAIT_OBJECT_0 + nCount))
			{
				WLog_ERR(TAG, "WaitForMultipleObjects failed (0x%08X)", rc);
				break;
			}

			if (rc == WAIT_OBJECT_0)
			{
				/* stop event triggered */
				break;
			}

			if (WaitForSingleObject(inputEvent, 0) == WAIT_OBJECT_0)
			{
				input_activity_cb(instance);
			}

			{
				if (!freerdp_check_event_handles(context))
				{
					WLog_ERR(TAG, "freerdp_check_event_handles failed");
					break;
				}
			}
		}

	disconnect:
		[view setIs_connected:0];
		freerdp_disconnect(instance);

		ExitThread(0);
		return 0;
	}
}

- (id)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];

	if (self)
	{
		// Initialization code here.
	}

	return self;
}

- (void)viewDidLoad
{
	[self initializeView];
}

- (void)initializeView
{
	if (!initialized)
	{
		cursors = [[NSMutableArray alloc] initWithCapacity:10];
		// setup a mouse tracking area
		NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
		    initWithRect:[self visibleRect]
		         options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
		                 NSTrackingCursorUpdate | NSTrackingEnabledDuringMouseDrag |
		                 NSTrackingActiveWhenFirstResponder
		           owner:self
		        userInfo:nil];
		[self addTrackingArea:trackingArea];
		// Set the default cursor
		currentCursor = [NSCursor arrowCursor];
		[self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[self setOpaque:NO];
		initialized = YES;
	}
}

- (void)ensureAdditionalTransparencyBlurView
{
	NSView *superview = [self superview];
	if (!superview)
		return;
	NSRect blurBounds = context ? mac_smart_sizing_display_rect(self, context) : [self bounds];
	NSRect blurFrame = [self convertRect:blurBounds toView:superview];

	if (!additionalTransparencyBlurView)
	{
		additionalTransparencyBlurView = [[NSVisualEffectView alloc] initWithFrame:blurFrame];
		[additionalTransparencyBlurView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[additionalTransparencyBlurView setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
		[additionalTransparencyBlurView setMaterial:NSVisualEffectMaterialHUDWindow];
		[additionalTransparencyBlurView setState:NSVisualEffectStateActive];
		[additionalTransparencyBlurView setWantsLayer:YES];

		additionalTransparencyBlurMaskLayer = [[CALayer layer] retain];
		[[additionalTransparencyBlurView layer] setMask:additionalTransparencyBlurMaskLayer];
	}

	if ([additionalTransparencyBlurView superview] != superview)
	{
		[additionalTransparencyBlurView removeFromSuperview];
		[superview addSubview:additionalTransparencyBlurView
		           positioned:NSWindowBelow
		           relativeTo:self];
	}

	[additionalTransparencyBlurView setFrame:blurFrame];
	[additionalTransparencyBlurMaskLayer setFrame:[additionalTransparencyBlurView bounds]];
}

- (void)updateAdditionalTransparencyBlurMask:(uint8_t *)maskData
                                      width:(size_t)width
                                     height:(size_t)height
{
	if (!maskData || width == 0 || height == 0)
	{
		[additionalTransparencyBlurView setHidden:YES];
		[additionalTransparencyBlurMaskLayer setContents:nil];
		free(maskData);
		return;
	}

	uint8_t *rgbaMask = (uint8_t *)calloc(width * height, 4);
	if (!rgbaMask)
	{
		[additionalTransparencyBlurView setHidden:YES];
		free(maskData);
		return;
	}

	for (size_t i = 0; i < width * height; i++)
	{
		rgbaMask[(i * 4) + 0] = 0xFF;
		rgbaMask[(i * 4) + 1] = 0xFF;
		rgbaMask[(i * 4) + 2] = 0xFF;
		rgbaMask[(i * 4) + 3] = maskData[i];
	}
	free(maskData);

	[self ensureAdditionalTransparencyBlurView];
	if (!additionalTransparencyBlurView || !additionalTransparencyBlurMaskLayer)
	{
		free(rgbaMask);
		return;
	}

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, rgbaMask, width * height * 4,
	                                                          mac_release_mask_data);
	CGImageRef maskImage = CGImageCreate(width, height, 8, 32, width * 4, colorSpace,
	                                     kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
	                                     provider, NULL, FALSE, kCGRenderingIntentDefault);
	if (!maskImage)
	{
		[additionalTransparencyBlurView setHidden:YES];
		CGDataProviderRelease(provider);
		CGColorSpaceRelease(colorSpace);
		return;
	}

	[additionalTransparencyBlurView setHidden:NO];
	[additionalTransparencyBlurMaskLayer setContents:(id)maskImage];
	[additionalTransparencyBlurMaskLayer setContentsGravity:kCAGravityResize];
	[additionalTransparencyBlurMaskLayer setFrame:[additionalTransparencyBlurView bounds]];

	CGImageRelease(maskImage);
	CGDataProviderRelease(provider);
	CGColorSpaceRelease(colorSpace);
}

	- (void)startMousePassThroughMonitor
	{
		if (mousePassThroughMonitor)
			return;

		__block MRDPView *blockSelf = self;
		mousePassThroughMonitor = [NSEvent
		    addGlobalMonitorForEventsMatchingMask:MRDP_PASS_THROUGH_MONITOR_MASK
		                            handler:^(NSEvent *event) {
			                            [blockSelf handleGlobalMouseEvent:event];
		                            }];
	}

	- (void)stopMousePassThroughMonitor
	{
		if (!mousePassThroughMonitor)
			return;

		[NSEvent removeMonitor:mousePassThroughMonitor];
		mousePassThroughMonitor = nil;
	}

	- (void)scheduleMousePassThroughSync
	{
		if (mousePassThroughSyncScheduled)
			return;

		mousePassThroughSyncScheduled = YES;
		dispatch_async(dispatch_get_main_queue(), ^{
			self->mousePassThroughSyncScheduled = NO;
			[self syncMousePassThroughStateForScreenPoint:[NSEvent mouseLocation]];
		});
	}

- (void)setCursor:(NSCursor *)cursor
{
	self->currentCursor = cursor;
	dispatch_async(dispatch_get_main_queue(), ^{
		[[self window] invalidateCursorRectsForView:self];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"MRDPRemoteCursorDidUpdate"
		                                                    object:self];
	});
}

- (NSCursor *)currentRemoteCursor
{
	return currentCursor ?: [NSCursor arrowCursor];
}

- (void)resetCursorRects
{
	[self addCursorRect:[self visibleRect] cursor:[self currentRemoteCursor]];
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
	if (!is_connected || !instance || !instance->context || !instance->context->input)
		return [super performKeyEquivalent:event];

	const MF_MODIFIER_KEYSWAP_MODE keyswapMode =
	    mac_modifier_keyswap_mode(mfc, instance->context->settings);
	if (keyswapMode == MF_MODIFIER_KEYSWAP_NONE)
		return [super performKeyEquivalent:event];

	const DWORD modFlags = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
	if ((modFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption |
	                 NSEventModifierFlagCommand)) == 0)
		return [super performKeyEquivalent:event];

	NSString *characters = [event charactersIgnoringModifiers];
	if ([characters length] == 0)
		return [super performKeyEquivalent:event];

	DWORD keyCode = [event keyCode];
	unichar keyChar = [characters characterAtIndex:0];
	keyCode = fixKeyCode(keyCode, keyChar, mfc->appleKeyboardType);

	DWORD vkcode = GetVirtualKeyCodeFromKeycode(keyCode, WINPR_KEYCODE_TYPE_APPLE);
	DWORD scancode = GetVirtualScanCodeFromVirtualKeyCode(vkcode, 4);
	DWORD keyFlags = (scancode & KBDEXT);
	scancode &= 0xFF;

	[self flagsChanged:event];
	ensureModifierFlagStates(instance->context->input, modFlags, keyswapMode);

	(void)freerdp_input_send_keyboard_event(instance->context->input,
	                                        keyFlags | KBD_FLAGS_DOWN, scancode);
	(void)freerdp_input_send_keyboard_event(instance->context->input,
	                                        keyFlags | KBD_FLAGS_RELEASE, scancode);
	return YES;
}

- (void)selectAll:(id)sender
{
	(void)sender;
	NSEvent *event = [NSApp currentEvent];
	if (event && ([event type] == NSEventTypeKeyDown) && [self performKeyEquivalent:event])
		return;

	if (!is_connected || !instance || !instance->context || !instance->context->input)
		return;

	const MF_MODIFIER_KEYSWAP_MODE keyswapMode =
	    mac_modifier_keyswap_mode(mfc, instance->context->settings);
	if (keyswapMode != MF_MODIFIER_KEYSWAP_APPLE_TO_PC)
		return;

	rdpInput *input = instance->context->input;
	(void)freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, RDP_SCANCODE_LCONTROL);
	(void)freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, RDP_SCANCODE_KEY_A);
	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_KEY_A);
	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_LCONTROL);
}

- (void)passMouseEventThrough:(NSEvent *)event
{
	NSWindow *window = [self window];
	CGEventRef sourceEvent = [event CGEvent];

	if (!window || !sourceEvent)
		return;

	CGEventRef forwardedEvent = CGEventCreateCopy(sourceEvent);
	if (!forwardedEvent)
		return;

	CGEventSetIntegerValueField(forwardedEvent, kCGEventSourceUserData,
	                            MRDP_PASS_THROUGH_EVENT_TAG);
	[window setIgnoresMouseEvents:YES];
	CGEventPost(kCGHIDEventTap, forwardedEvent);
	CFRelease(forwardedEvent);

	dispatch_async(dispatch_get_main_queue(), ^{
		[window setIgnoresMouseEvents:NO];
	});
}

- (void)syncMousePassThroughStateForScreenPoint:(NSPoint)screenPoint
{
	NSWindow *window = [self window];
	BOOL shouldIgnore = NO;
	NSPoint viewPoint = NSZeroPoint;

	if (window && mfc && mfc->chromaKeyEnabled && NSPointInRect(screenPoint, [window frame]))
	{
		NSPoint windowPoint = [window convertPointFromScreen:screenPoint];
		viewPoint = [self convertPoint:windowPoint fromView:nil];
		shouldIgnore = [self isPixelTransparent:viewPoint];
	}

	if (mousePassThroughArmed == shouldIgnore)
		return;

	mousePassThroughArmed = shouldIgnore;
	[window setIgnoresMouseEvents:shouldIgnore];

	if (shouldIgnore)
	{
		NSLog(@"MRDP pass-through armed view=(%.1f, %.1f)", viewPoint.x, viewPoint.y);
	}
	else
	{
		NSLog(@"MRDP pass-through disarmed");
	}
}

- (void)handleGlobalMouseEvent:(NSEvent *)event
{
	NSWindow *window = [self window];
	if (!window)
		return;

	NSPoint screenPoint = [NSEvent mouseLocation];
	if (mousePassThroughArmed && NSPointInRect(screenPoint, [window frame]) &&
	    (([event type] == NSEventTypeLeftMouseDown) || ([event type] == NSEventTypeRightMouseDown) ||
	     ([event type] == NSEventTypeOtherMouseDown)))
	{
		NSLog(@"MRDP pass-through click observed while armed screen=(%.1f, %.1f)", screenPoint.x,
		      screenPoint.y);
	}

	[self syncMousePassThroughStateForScreenPoint:screenPoint];
}

- (void)logTransparentClickForEvent:(NSEvent *)event viewPoint:(NSPoint)viewPoint
{
	if (([event type] != NSEventTypeLeftMouseDown) && ([event type] != NSEventTypeRightMouseDown) &&
	    ([event type] != NSEventTypeOtherMouseDown))
	{
		return;
	}

	rdpGdi *gdi = context->gdi;
	if (!gdi || !gdi->primary_buffer)
		return;

	NSRect bounds = [self bounds];
	if (!NSPointInRect(viewPoint, bounds))
	{
		NSLog(@"MRDP pass-through click attempt: point outside view bounds view=(%.1f, %.1f)",
		      viewPoint.x, viewPoint.y);
		return;
	}

	CGFloat width = NSWidth(bounds);
	CGFloat height = NSHeight(bounds);
	if (width <= 0 || height <= 0)
		return;

	CGFloat xScale = (CGFloat)gdi->width / width;
	CGFloat yScale = (CGFloat)gdi->height / height;
	int bx = (int)floor(viewPoint.x * xScale);
	int by = (int)floor((height - viewPoint.y) * yScale);

	if (bx < 0 || bx >= (int)gdi->width || by < 0 || by >= (int)gdi->height)
	{
		NSLog(@"MRDP pass-through click attempt: point outside buffer view=(%.1f, %.1f) buffer=(%d, %d)",
		      viewPoint.x, viewPoint.y, bx, by);
		return;
	}

	uint32_t *buffer = (uint32_t *)gdi->primary_buffer;
	uint32_t pixel = buffer[(size_t)by * (size_t)gdi->width + (size_t)bx];
	BOOL alphaTransparent = (((pixel >> 24) & 0xFF) == 0);
	BOOL chromaTransparent = mac_is_chroma_key_pixel(mfc, pixel);

	NSLog(@"MRDP pass-through click attempt: pixel=0x%08X buffer=(%d,%d) view=(%.1f,%.1f) "
	      @"alphaTransparent=%d chromaTransparent=%d chromaKey=0x%06X",
	      pixel, bx, by, viewPoint.x, viewPoint.y, alphaTransparent, chromaTransparent,
	      mfc->chromaKeyColor);
}

- (void)syncRemoteInputForTransparentClick:(NSEvent *)event
{
	if (!self.is_connected)
		return;

	NSEventType type = [event type];
	if ((type != NSEventTypeLeftMouseDown) && (type != NSEventTypeRightMouseDown) &&
	    (type != NSEventTypeOtherMouseDown))
	{
		return;
	}

	NSPoint windowLoc = [event locationInWindow];
	int x = (int)windowLoc.x;
	int y = (int)windowLoc.y;
	mf_scale_mouse_event(context, PTR_FLAGS_MOVE, x, y);

	int button = -1;
	switch (type)
	{
		case NSEventTypeLeftMouseDown:
			button = 0;
			break;
		case NSEventTypeRightMouseDown:
			button = 1;
			break;
		case NSEventTypeOtherMouseDown:
			button = (int)[event buttonNumber];
			break;
		default:
			break;
	}

	if (button >= 0)
	{
		mf_press_mouse_button(context, button, x, y, TRUE);
		mf_press_mouse_button(context, button, x, y, FALSE);
		NSLog(@"MRDP remote pointer moved and clicked before pass-through x=%d y=%d button=%d",
		      x, y, button);
	}
}

- (BOOL)isPixelTransparent:(NSPoint)viewPoint
{
	if (!mfc->chromaKeyEnabled)
		return NO;

	int bx = 0;
	int by = 0;
	if (!mac_view_point_to_buffer_point(self, mfc, context, viewPoint, &bx, &by))
		return NO;

	rdpGdi *gdi = context->gdi;
	uint32_t *buffer = (uint32_t *)gdi->primary_buffer;
	uint32_t pixel = buffer[(size_t)by * (size_t)gdi->width + (size_t)bx];
	if (!mac_is_chroma_key_pixel(mfc, pixel))
		return NO;

	if (mac_is_resize_cursor([NSCursor currentSystemCursor]))
		return NO;

	return mac_has_chroma_key_margin(mfc, gdi, bx, by, 8);
}

- (BOOL)shouldPassMouseEventThrough:(NSEvent *)event
{
	NSEventType type = [event type];
	if ((deferredWindowDragArmed || deferredWindowDragActive || deferredWindowDragCancelled) &&
	    ((type == NSEventTypeLeftMouseDragged) || (type == NSEventTypeLeftMouseUp)))
	{
		return NO;
	}

	CGEventRef cgEvent = [event CGEvent];
	if (cgEvent &&
	    (CGEventGetIntegerValueField(cgEvent, kCGEventSourceUserData) ==
	     MRDP_PASS_THROUGH_EVENT_TAG))
	{
		return NO;
	}

	NSPoint windowLoc = [event locationInWindow];
	NSPoint viewPoint = [self convertPoint:windowLoc fromView:nil];
	BOOL transparent = [self isPixelTransparent:viewPoint];
	if (transparent)
	{
		[self logTransparentClickForEvent:event viewPoint:viewPoint];
		[self syncRemoteInputForTransparentClick:event];
	}

	[self syncMousePassThroughStateForScreenPoint:[NSEvent mouseLocation]];

	return transparent;
}

- (CGFloat)windowDragTitlebarHeight
{
	if (mfc && mfc->windowDragTitlebarHeight > 0)
		return (CGFloat)mfc->windowDragTitlebarHeight;

	return 40.0;
}

- (NSRect)windowDragTitlebarRectForWindowRect:(NSRect)windowRect
{
	if (NSIsEmptyRect(windowRect))
		return NSZeroRect;

	const CGFloat maxY = NSMaxY(windowRect);
	const CGFloat minY = MAX(NSMinY(windowRect), maxY - [self windowDragTitlebarHeight]);
	return NSMakeRect(NSMinX(windowRect), minY, NSWidth(windowRect), maxY - minY);
}

- (BOOL)isPointInWindowDragTitlebar:(NSPoint)point
{
	if (!mfc || !mfc->chromaKeyEnabled || !context || !context->gdi ||
	    !context->gdi->primary_buffer)
	{
		NSRect displayRect = mac_smart_sizing_display_rect(self, context);
		if (NSIsEmptyRect(displayRect))
			displayRect = [self bounds];
		return NSPointInRect(point, [self windowDragTitlebarRectForWindowRect:displayRect]);
	}

	NSRect windowRect = [self deferredWindowDragRectForPoint:point];

	if (NSIsEmptyRect(windowRect))
		return NO;

	return NSPointInRect(point, [self windowDragTitlebarRectForWindowRect:windowRect]);
}

- (BOOL)shouldDeferWindowDragAtPoint:(NSPoint)point
{
	return context && context->settings &&
	       freerdp_settings_get_bool(context->settings, FreeRDP_DisableFullWindowDrag) &&
	       [self isPointInWindowDragTitlebar:point];
}

- (NSRect)fallbackDeferredWindowDragRectForPoint:(NSPoint)point
{
	const CGFloat side = 96.0;
	NSRect bounds = [self bounds];
	NSRect rect = NSMakeRect(point.x - side / 2.0, point.y - side / 2.0, side, side);

	if ((NSWidth(bounds) <= 0) || (NSHeight(bounds) <= 0))
		return rect;

	rect.origin.x = MIN(MAX(NSMinX(rect), NSMinX(bounds)), MAX(NSMinX(bounds), NSMaxX(bounds) - side));
	rect.origin.y = MIN(MAX(NSMinY(rect), NSMinY(bounds)), MAX(NSMinY(bounds), NSMaxY(bounds) - side));
	return NSIntersectionRect(rect, bounds);
}

- (BOOL)detectedDeferredWindowDragRectForPoint:(NSPoint)point outRect:(NSRect *)outRect
{
	if (!mfc || !mfc->chromaKeyEnabled || !context || !context->gdi)
		return NO;

	rdpGdi *gdi = context->gdi;
	uint32_t *buffer = (uint32_t *)gdi->primary_buffer;
	int startX = 0;
	int startY = 0;
	if (!buffer || !mac_view_point_to_buffer_point(self, mfc, context, point, &startX, &startY))
		return NO;

	if (mac_is_chroma_key_pixel(mfc, buffer[(size_t)startY * (size_t)gdi->width + (size_t)startX]))
		return NO;

	const size_t width = gdi->width;
	const size_t height = gdi->height;
	const size_t count = width * height;
	if ((width == 0) || (height == 0) || (count == 0))
		return NO;

	uint8_t *visited = (uint8_t *)calloc(count, sizeof(uint8_t));
	UINT32 *queue = (UINT32 *)malloc(count * sizeof(UINT32));
	if (!visited || !queue)
	{
		free(visited);
		free(queue);
		return NO;
	}

	size_t head = 0;
	size_t tail = 0;
	queue[tail++] = (UINT32)((size_t)startY * width + (size_t)startX);
	visited[(size_t)startY * width + (size_t)startX] = 1;

	while (head < tail)
	{
		UINT32 index = queue[head++];
		int x = (int)(index % width);
		int y = (int)(index / width);

		const int nx[4] = { x - 1, x + 1, x, x };
		const int ny[4] = { y, y, y - 1, y + 1 };
		for (int i = 0; i < 4; i++)
		{
			if ((nx[i] < 0) || (ny[i] < 0) || (nx[i] >= (int)width) || (ny[i] >= (int)height))
				continue;

			const size_t next = (size_t)ny[i] * width + (size_t)nx[i];
			if (visited[next] || mac_is_chroma_key_pixel(mfc, buffer[next]))
				continue;

			visited[next] = 1;
			queue[tail++] = (UINT32)next;
		}
	}

	MRDPWindowDragCandidateRect candidate = { 0 };
	BOOL reconstructed = mrdp_reconstruct_window_drag_rect(visited, queue, tail, width, height,
	                                                       startX, startY, &candidate);
	free(visited);
	free(queue);
	if (!reconstructed)
		return NO;

	NSRect displayRect = mac_smart_sizing_display_rect(self, context);
	if ((NSWidth(displayRect) <= 0) || (NSHeight(displayRect) <= 0))
		return NO;

	CGFloat sx = NSWidth(displayRect) / (CGFloat)width;
	CGFloat sy = NSHeight(displayRect) / (CGFloat)height;
	NSRect rect = NSMakeRect(NSMinX(displayRect) + (CGFloat)candidate.x1 * sx,
	                         NSMaxY(displayRect) - (CGFloat)candidate.y2 * sy,
	                         (CGFloat)(candidate.x2 - candidate.x1) * sx,
	                         (CGFloat)(candidate.y2 - candidate.y1) * sy);
	rect = NSIntersectionRect(NSInsetRect(rect, -1.0, -1.0), [self bounds]);
	if (NSIsEmptyRect(rect))
		return NO;

	if (outRect)
		*outRect = rect;
	return YES;
}

- (NSRect)deferredWindowDragRectForPoint:(NSPoint)point
{
	NSRect rect = NSZeroRect;
	if ([self detectedDeferredWindowDragRectForPoint:point outRect:&rect])
		return rect;

	return [self fallbackDeferredWindowDragRectForPoint:point];
}

- (NSRect)deferredWindowDragOutlineForPoint:(NSPoint)point
{
	CGFloat dx = point.x - deferredWindowDragStartPoint.x;
	CGFloat dy = point.y - deferredWindowDragStartPoint.y;
	return NSOffsetRect(deferredWindowDragBaseRect, dx, dy);
}

- (void)setDeferredWindowDragNeedsDisplayForRect:(NSRect)rect
{
	if (!NSIsEmptyRect(rect))
		[self setNeedsDisplayInRect:NSInsetRect(rect, -4.0, -4.0)];
}

- (void)setWindowDragTitlebarPreviewVisible:(BOOL)visible
{
	if (windowDragTitlebarPreviewVisible == visible)
		return;

	windowDragTitlebarPreviewVisible = visible;
	[self setNeedsDisplay:YES];
}

- (void)drawWindowDragTitlebarPreview
{
	const CGFloat titlebarHeight = [self windowDragTitlebarHeight];
	NSRect displayRect = mac_smart_sizing_display_rect(self, context);

	if ((titlebarHeight <= 0) || (NSWidth(displayRect) <= 0) || (NSHeight(displayRect) <= 0))
		return;

	[[NSColor colorWithCalibratedRed:0.0 green:0.42 blue:1.0 alpha:0.32] setFill];

	if (!mfc || !mfc->chromaKeyEnabled || !context || !context->gdi ||
	    !context->gdi->primary_buffer)
	{
		NSRect rect = [self windowDragTitlebarRectForWindowRect:displayRect];
		NSRectFillUsingOperation(NSIntegralRect(rect), NSCompositingOperationSourceOver);
		return;
	}

	rdpGdi *gdi = context->gdi;
	uint32_t *buffer = (uint32_t *)gdi->primary_buffer;
	const size_t width = gdi->width;
	const size_t height = gdi->height;
	const size_t count = width * height;
	if ((width == 0) || (height == 0) || (count == 0))
		return;

	uint8_t *visited = (uint8_t *)calloc(count, sizeof(uint8_t));
	UINT32 *queue = (UINT32 *)malloc(count * sizeof(UINT32));
	if (!visited || !queue)
	{
		free(visited);
		free(queue);
		return;
	}

	const CGFloat sx = NSWidth(displayRect) / (CGFloat)width;
	const CGFloat sy = NSHeight(displayRect) / (CGFloat)height;

	for (size_t i = 0; i < count; i++)
	{
		if (visited[i] || mac_is_chroma_key_pixel(mfc, buffer[i]))
			continue;

		size_t head = 0;
		size_t tail = 0;
		int minX = (int)(i % width);
		int maxX = minX;
		int minY = (int)(i / width);
		int maxY = minY;
		queue[tail++] = (UINT32)i;
		visited[i] = 1;

		while (head < tail)
		{
			UINT32 index = queue[head++];
			int x = (int)(index % width);
			int y = (int)(index / width);
			minX = MIN(minX, x);
			maxX = MAX(maxX, x);
			minY = MIN(minY, y);
			maxY = MAX(maxY, y);

			const int nx[4] = { x - 1, x + 1, x, x };
			const int ny[4] = { y, y, y - 1, y + 1 };
			for (int n = 0; n < 4; n++)
			{
				if ((nx[n] < 0) || (ny[n] < 0) || (nx[n] >= (int)width) ||
				    (ny[n] >= (int)height))
					continue;

				const size_t next = (size_t)ny[n] * width + (size_t)nx[n];
				if (visited[next] || mac_is_chroma_key_pixel(mfc, buffer[next]))
					continue;

				visited[next] = 1;
				queue[tail++] = (UINT32)next;
			}
		}

		NSRect rect = NSMakeRect(NSMinX(displayRect) + (CGFloat)minX * sx,
		                         NSMaxY(displayRect) - (CGFloat)(maxY + 1) * sy,
		                         (CGFloat)(maxX - minX + 1) * sx,
		                         (CGFloat)(maxY - minY + 1) * sy);
		rect = NSIntersectionRect(NSInsetRect(rect, -1.0, -1.0), [self bounds]);
		rect = [self windowDragTitlebarRectForWindowRect:rect];
		if (!NSIsEmptyRect(rect))
			NSRectFillUsingOperation(NSIntegralRect(rect), NSCompositingOperationSourceOver);
	}

	free(visited);
	free(queue);
}

- (void)beginDeferredWindowDragAtPoint:(NSPoint)point
{
	deferredWindowDragActive = YES;
	deferredWindowDragStartPoint = point;
	deferredWindowDragCurrentPoint = point;
	deferredWindowDragBaseRect = [self deferredWindowDragRectForPoint:point];
	deferredWindowDragOutlineRect = deferredWindowDragBaseRect;
	[self setDeferredWindowDragNeedsDisplayForRect:deferredWindowDragOutlineRect];
}

- (void)updateDeferredWindowDragToPoint:(NSPoint)point
{
	NSRect oldRect = deferredWindowDragOutlineRect;
	deferredWindowDragCurrentPoint = point;
	deferredWindowDragOutlineRect = [self deferredWindowDragOutlineForPoint:point];
	[self setDeferredWindowDragNeedsDisplayForRect:NSUnionRect(oldRect, deferredWindowDragOutlineRect)];
}

- (void)endDeferredWindowDrag
{
	deferredWindowDragArmed = NO;
	if (deferredWindowDragActive)
		[self setDeferredWindowDragNeedsDisplayForRect:deferredWindowDragOutlineRect];
	deferredWindowDragActive = NO;
	deferredWindowDragBaseRect = NSZeroRect;
	deferredWindowDragOutlineRect = NSZeroRect;
}

- (void)cancelDeferredWindowDrag
{
	if (!deferredWindowDragArmed && !deferredWindowDragActive)
		return;

	const int x = (int)deferredWindowDragStartPoint.x;
	const int y = (int)deferredWindowDragStartPoint.y;
	[self endDeferredWindowDrag];
	deferredWindowDragCancelled = YES;

	if ([self is_connected])
		mf_press_mouse_button(context, 0, x, y, FALSE);
}

- (void)sendDeferredWindowDragAttemptFromPoint:(NSPoint)startPoint toPoint:(NSPoint)endPoint retry:(BOOL)retry
{
	const int startX = (int)startPoint.x;
	const int startY = (int)startPoint.y;
	const int endX = (int)endPoint.x;
	const int endY = (int)endPoint.y;
	const int midX = (startX + endX) / 2;
	const int midY = (startY + endY) / 2;

	if (retry)
	{
		mf_scale_mouse_event(context, PTR_FLAGS_MOVE, startX, startY);
		mf_press_mouse_button(context, 0, startX, startY, TRUE);
	}

	mf_scale_mouse_event(context, PTR_FLAGS_MOVE, midX, midY);
	mf_scale_mouse_event(context, PTR_FLAGS_MOVE, endX, endY);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.015 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		               if ([self is_connected])
			               mf_scale_mouse_event(self->context, PTR_FLAGS_MOVE, endX, endY);
	               });

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.035 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		               if ([self is_connected])
			               mf_press_mouse_button(self->context, 0, endX, endY, FALSE);
	               });
}

- (BOOL)isDeferredWindowDragMoveVisibleAtPoint:(NSPoint)point expectedRect:(NSRect)expectedRect
{
	NSRect actualRect = NSZeroRect;
	if (![self detectedDeferredWindowDragRectForPoint:point outRect:&actualRect])
		return NO;

	const CGFloat toleranceX = MAX(8.0, NSWidth(expectedRect) * 0.08);
	const CGFloat toleranceY = MAX(8.0, NSHeight(expectedRect) * 0.08);
	return (fabs(NSMinX(actualRect) - NSMinX(expectedRect)) <= toleranceX) &&
	       (fabs(NSMinY(actualRect) - NSMinY(expectedRect)) <= toleranceY) &&
	       (fabs(NSWidth(actualRect) - NSWidth(expectedRect)) <= toleranceX) &&
	       (fabs(NSHeight(actualRect) - NSHeight(expectedRect)) <= toleranceY);
}

- (void)verifyDeferredWindowDragFromPoint:(NSPoint)startPoint
                                  toPoint:(NSPoint)endPoint
                             expectedRect:(NSRect)expectedRect
                                  attempt:(NSUInteger)attempt
{
	if (![self is_connected])
		return;

	[self refreshBitmap];
	if ([self isDeferredWindowDragMoveVisibleAtPoint:endPoint expectedRect:expectedRect])
		return;

	WLog_WARN(TAG,
	          "Deferred window drag move not verified on attempt %" PRIu32
	          " from %.0f,%.0f to %.0f,%.0f",
	          (UINT32)attempt, startPoint.x, startPoint.y, endPoint.x, endPoint.y);

	if (attempt >= 6)
	{
		WLog_WARN(TAG, "Deferred window drag giving up after %" PRIu32 " attempts",
		          (UINT32)attempt);
		return;
	}

	WLog_WARN(TAG, "Retrying deferred window drag move, attempt %" PRIu32, (UINT32)(attempt + 1));
	[self sendDeferredWindowDragAttemptFromPoint:startPoint toPoint:endPoint retry:YES];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		               [self verifyDeferredWindowDragFromPoint:startPoint
		                                                toPoint:endPoint
		                                           expectedRect:expectedRect
		                                                attempt:attempt + 1];
	               });
}

- (void)commitDeferredWindowDragAtPoint:(NSPoint)point
{
	const NSPoint startPoint = deferredWindowDragStartPoint;
	const NSRect expectedRect = [self deferredWindowDragOutlineForPoint:point];

	[self sendDeferredWindowDragAttemptFromPoint:startPoint toPoint:point retry:NO];
	[self endDeferredWindowDrag];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
	               dispatch_get_main_queue(), ^{
		               [self verifyDeferredWindowDragFromPoint:startPoint
		                                                toPoint:point
		                                           expectedRect:expectedRect
		                                                attempt:1];
	               });
}

- (void)mouseMoved:(NSEvent *)event
{
	[super mouseMoved:event];
	[self syncMousePassThroughStateForScreenPoint:[NSEvent mouseLocation]];

	if (!self.is_connected)
		return;

	NSPoint loc = [event locationInWindow];
	int x = (int)loc.x;
	int y = (int)loc.y;
	mf_scale_mouse_event(context, PTR_FLAGS_MOVE, x, y);
}

- (void)mouseDown:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}

	NSPoint windowLoc = [event locationInWindow];
	dragRefreshPending = NO;
	dragRefreshStartPoint = windowLoc;
	deferredWindowDragArmed = [self shouldDeferWindowDragAtPoint:windowLoc];
	deferredWindowDragActive = NO;
	deferredWindowDragCancelled = NO;
	deferredWindowDragEscapeSuppressed = NO;
	deferredWindowDragStartPoint = windowLoc;
	deferredWindowDragCurrentPoint = windowLoc;

	[super mouseDown:event];

	if (!self.is_connected)
		return;

	int x = (int)windowLoc.x;
	int y = (int)windowLoc.y;
	mf_press_mouse_button(context, 0, x, y, TRUE);
}

- (void)mouseUp:(NSEvent *)event
{
	if (deferredWindowDragCancelled)
	{
		deferredWindowDragCancelled = NO;
		dragRefreshPending = NO;
		return;
	}

	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}

	NSPoint windowLoc = [event locationInWindow];

	[super mouseUp:event];

	if (!self.is_connected)
	{
		[self endDeferredWindowDrag];
		return;
	}

	int x = (int)windowLoc.x;
	int y = (int)windowLoc.y;
	if (deferredWindowDragActive)
	{
		[self commitDeferredWindowDragAtPoint:windowLoc];
		if (dragRefreshPending)
			[self schedulePostDragRefresh];
		dragRefreshPending = NO;
		return;
	}

	mf_press_mouse_button(context, 0, x, y, FALSE);
	[self endDeferredWindowDrag];

	if (dragRefreshPending)
		[self schedulePostDragRefresh];
	dragRefreshPending = NO;
}

- (void)rightMouseDown:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}

	NSPoint windowLoc = [event locationInWindow];

	[super rightMouseDown:event];

	if (!self.is_connected)
		return;

	int x = (int)windowLoc.x;
	int y = (int)windowLoc.y;
	mf_press_mouse_button(context, 1, x, y, TRUE);
}

- (void)rightMouseUp:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}

	NSPoint windowLoc = [event locationInWindow];

	[super rightMouseUp:event];

	if (!self.is_connected)
		return;

	int x = (int)windowLoc.x;
	int y = (int)windowLoc.y;
	mf_press_mouse_button(context, 1, x, y, FALSE);
}

- (void)otherMouseDown:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}

	NSPoint windowLoc = [event locationInWindow];

	[super otherMouseDown:event];

	if (!self.is_connected)
		return;

	int x = (int)windowLoc.x;
	int y = (int)windowLoc.y;
	int pressed = [event buttonNumber];
	mf_press_mouse_button(context, pressed, x, y, TRUE);
}

- (void)otherMouseUp:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}

	NSPoint windowLoc = [event locationInWindow];

	[super otherMouseUp:event];

	if (!self.is_connected)
		return;

	int x = (int)windowLoc.x;
	int y = (int)windowLoc.y;
	int pressed = [event buttonNumber];
	mf_press_mouse_button(context, pressed, x, y, FALSE);
}

- (void)scrollWheel:(NSEvent *)event
{
	[super scrollWheel:event];

	if (!self.is_connected)
		return;

	const CGFloat dx = [event hasPreciseScrollingDeltas] ? [event scrollingDeltaX] : [event deltaX];
	const CGFloat dy = [event hasPreciseScrollingDeltas] ? [event scrollingDeltaY] : [event deltaY];
	UINT16 flags = 0;
	if (!mac_scroll_flags_from_deltas(dx, dy, &flags))
		return;

	NSPoint windowLoc = [event locationInWindow];
	mf_scale_mouse_event(context, flags, (UINT16)windowLoc.x, (UINT16)windowLoc.y);
}

- (void)mouseDragged:(NSEvent *)event
{
	if (deferredWindowDragCancelled)
		return;

	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}

	NSPoint windowLoc = [event locationInWindow];

	[super mouseDragged:event];

	if (!self.is_connected)
		return;

	const CGFloat dx = windowLoc.x - dragRefreshStartPoint.x;
	const CGFloat dy = windowLoc.y - dragRefreshStartPoint.y;
	if ((fabs(dx) > 3.0) || (fabs(dy) > 3.0))
		dragRefreshPending = YES;

	if (deferredWindowDragArmed)
	{
		if (!deferredWindowDragActive && dragRefreshPending)
			[self beginDeferredWindowDragAtPoint:dragRefreshStartPoint];
		if (deferredWindowDragActive)
			[self updateDeferredWindowDragToPoint:windowLoc];
		return;
	}

	int x = (int)windowLoc.x;
	int y = (int)windowLoc.y;
	mf_scale_mouse_event(context, PTR_FLAGS_MOVE, x, y);
}

static DWORD fixKeyCode(DWORD keyCode, unichar keyChar, enum APPLE_KEYBOARD_TYPE type)
{
	/**
	 * In 99% of cases, the given key code is truly keyboard independent.
	 * This function handles the remaining 1% of edge cases.
	 *
	 * Hungarian Keyboard: This is 'QWERTZ' and not 'QWERTY'.
	 * The '0' key is on the left of the '1' key, where '~' is on a US keyboard.
	 * A special 'i' letter key with acute is found on the right of the left shift key.
	 * On the hungarian keyboard, the 'i' key is at the left of the 'Y' key
	 * Some international keyboards have a corresponding key which would be at
	 * the left of the 'Z' key when using a QWERTY layout.
	 *
	 * The Apple Hungarian keyboard sends inverted key codes for the '0' and 'i' keys.
	 * When using the US keyboard layout, key codes are left as-is (inverted).
	 * When using the Hungarian keyboard layout, key codes are swapped (non-inverted).
	 * This means that when using the Hungarian keyboard layout with a US keyboard,
	 * the keys corresponding to '0' and 'i' will effectively be inverted.
	 *
	 * To fix the '0' and 'i' key inversion, we use the corresponding output character
	 * provided by OS X and check for a character to key code mismatch: for instance,
	 * when the output character is '0' for the key code corresponding to the 'i' key.
	 */
#if 0
	switch (keyChar)
	{
		case '0':
		case 0x00A7: /* section sign */
			if (keyCode == APPLE_VK_ISO_Section)
				keyCode = APPLE_VK_ANSI_Grave;

			break;

		case 0x00ED: /* latin small letter i with acute */
		case 0x00CD: /* latin capital letter i with acute */
			if (keyCode == APPLE_VK_ANSI_Grave)
				keyCode = APPLE_VK_ISO_Section;

			break;
	}

#endif

	/* Perform keycode correction for all ISO keyboards */

	if (type == APPLE_KEYBOARD_TYPE_ISO)
	{
		if (keyCode == APPLE_VK_ANSI_Grave)
			keyCode = APPLE_VK_ISO_Section;
		else if (keyCode == APPLE_VK_ISO_Section)
			keyCode = APPLE_VK_ANSI_Grave;
	}

	return keyCode;
}

- (BOOL)isEscapeKeyEvent:(NSEvent *)event
{
	NSString *characters = [event charactersIgnoringModifiers];
	if ([characters length] > 0 && [characters characterAtIndex:0] == 0x1B)
		return YES;

	return [event keyCode] == 0x35;
}

- (void)flagsChanged:(NSEvent *)event
{
	if (!is_connected)
		return;

	DWORD modFlags = [event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;

	WINPR_ASSERT(instance);
	WINPR_ASSERT(instance->context);

	rdpInput *input = instance->context->input;
	MF_MODIFIER_KEYSWAP_MODE keyswapMode =
	    mac_modifier_keyswap_mode(mfc, instance->context->settings);

#if defined(WITH_DEBUG_KBD)
	WLog_DBG(TAG, "flagsChanged: modFlags: 0x%04X kbdModFlags: 0x%04X", modFlags, kbdModFlags);
#endif

	updateFlagStates(input, modFlags, kbdModFlags, keyswapMode);
	kbdModFlags = modFlags;
}

- (void)keyDown:(NSEvent *)event
{
	DWORD keyCode;
	DWORD keyFlags;
	DWORD vkcode;
	DWORD scancode;
	unichar keyChar;
	NSString *characters;

	NSLog(@"MRDPView keyDown called, is_connected=%d", is_connected);

	if (!is_connected)
		return;

	if ([self isEscapeKeyEvent:event] && (deferredWindowDragArmed || deferredWindowDragActive))
	{
		deferredWindowDragEscapeSuppressed = YES;
		[self cancelDeferredWindowDrag];
		return;
	}

	[self flagsChanged:event];
	ensureModifierFlagStates(instance->context->input,
	                         [event modifierFlags] &
	                             NSEventModifierFlagDeviceIndependentFlagsMask,
	                         mac_modifier_keyswap_mode(mfc, instance->context->settings));

	keyFlags = KBD_FLAGS_DOWN;
	keyCode = [event keyCode];
	characters = [event charactersIgnoringModifiers];

	if ([characters length] > 0)
	{
		keyChar = [characters characterAtIndex:0];
		keyCode = fixKeyCode(keyCode, keyChar, mfc->appleKeyboardType);
	}

	vkcode = GetVirtualKeyCodeFromKeycode(keyCode, WINPR_KEYCODE_TYPE_APPLE);
	scancode = GetVirtualScanCodeFromVirtualKeyCode(vkcode, 4);
	keyFlags |= (scancode & KBDEXT) ? KBDEXT : 0;
	scancode &= 0xFF;
	vkcode &= 0xFF;

#if defined(WITH_DEBUG_KBD)
	WLog_DBG(TAG, "keyDown: keyCode: 0x%04X scancode: 0x%04X vkcode: 0x%04X keyFlags: %d name: %s",
	         keyCode, scancode, vkcode, keyFlags, GetVirtualKeyName(vkcode));
#endif

	WINPR_ASSERT(instance->context);
	freerdp_input_send_keyboard_event(instance->context->input, keyFlags, scancode);
}

- (void)keyUp:(NSEvent *)event
{
	DWORD keyCode;
	DWORD keyFlags;
	DWORD vkcode;
	DWORD scancode;
	unichar keyChar;
	NSString *characters;

	if (!is_connected)
		return;

	if ([self isEscapeKeyEvent:event] && deferredWindowDragEscapeSuppressed)
	{
		deferredWindowDragEscapeSuppressed = NO;
		return;
	}

	[self flagsChanged:event];

	keyFlags = KBD_FLAGS_RELEASE;
	keyCode = [event keyCode];
	characters = [event charactersIgnoringModifiers];

	if ([characters length] > 0)
	{
		keyChar = [characters characterAtIndex:0];
		keyCode = fixKeyCode(keyCode, keyChar, mfc->appleKeyboardType);
	}

	vkcode = GetVirtualKeyCodeFromKeycode(keyCode, WINPR_KEYCODE_TYPE_APPLE);
	scancode = GetVirtualScanCodeFromVirtualKeyCode(vkcode, 4);
	keyFlags |= (scancode & KBDEXT) ? KBDEXT : 0;
	scancode &= 0xFF;
	vkcode &= 0xFF;
#if defined(WITH_DEBUG_KBD)
	WLog_DBG(TAG, "keyUp: key: 0x%04X scancode: 0x%04X vkcode: 0x%04X keyFlags: %d name: %s",
	         keyCode, scancode, vkcode, keyFlags, GetVirtualKeyName(vkcode));
#endif
	WINPR_ASSERT(instance->context);
	freerdp_input_send_keyboard_event(instance->context->input, keyFlags, scancode);
}

static BOOL updateFlagState(rdpInput *input, DWORD modFlags, DWORD aKbdModFlags, DWORD flag,
                            MF_MODIFIER_KEYSWAP_MODE keyswapMode)
{
	BOOL press = ((modFlags & flag) != 0) && ((aKbdModFlags & flag) == 0);
	BOOL release = ((modFlags & flag) == 0) && ((aKbdModFlags & flag) != 0);
	DWORD keyFlags = 0;
	const char *name = nullptr;
	DWORD scancode = 0;

	if ((modFlags & flag) == (aKbdModFlags & flag))
		return TRUE;

	switch (flag)
	{
		case NSEventModifierFlagCapsLock:
			name = "NSEventModifierFlagCapsLock";
			scancode = RDP_SCANCODE_CAPSLOCK;
			release = press = TRUE;
			break;
		case NSEventModifierFlagShift:
			name = "NSEventModifierFlagShift";
			scancode = RDP_SCANCODE_LSHIFT;
			break;

		case NSEventModifierFlagControl:
			name = "NSEventModifierFlagControl";
			scancode = RDP_SCANCODE_LCONTROL;
			break;

		case NSEventModifierFlagOption:
			name = "NSEventModifierFlagOption";
			scancode = RDP_SCANCODE_LMENU;
			break;

		case NSEventModifierFlagCommand:
			name = "NSEventModifierFlagCommand";
			scancode = RDP_SCANCODE_LWIN;
			break;

		case NSEventModifierFlagNumericPad:
			name = "NSEventModifierFlagNumericPad";
			scancode = RDP_SCANCODE_NUMLOCK;
			release = press = TRUE;
			break;

		case NSEventModifierFlagHelp:
			name = "NSEventModifierFlagHelp";
			scancode = RDP_SCANCODE_HELP;
			break;

		case NSEventModifierFlagFunction:
			name = "NSEventModifierFlagFunction";
			scancode = RDP_SCANCODE_HELP;
			break;

		default:
			WLog_ERR(TAG, "Invalid flag: 0x%08" PRIx32 ", not supported", flag);
			return FALSE;
	}

	scancode = mac_modifier_keyswap_scancode(flag, keyswapMode, scancode);
	keyFlags = (scancode & KBDEXT);
	scancode &= 0xFF;

#if defined(WITH_DEBUG_KBD)
	if (press || release)
		WLog_DBG(TAG, "changing flag %s[0x%08" PRIx32 "] to %s", name, flag,
		         press ? "DOWN" : "RELEASE");
#endif

	if (press)
	{
		if (!freerdp_input_send_keyboard_event(input, keyFlags | KBD_FLAGS_DOWN, scancode))
			return FALSE;
	}

	if (release)
	{
		if (!freerdp_input_send_keyboard_event(input, keyFlags | KBD_FLAGS_RELEASE, scancode))
			return FALSE;
	}

	return TRUE;
}

static BOOL updateFlagStates(rdpInput *input, UINT32 modFlags, UINT32 aKbdModFlags,
                             MF_MODIFIER_KEYSWAP_MODE keyswapMode)
{
	updateFlagState(input, modFlags, aKbdModFlags, NSEventModifierFlagCapsLock, keyswapMode);
	updateFlagState(input, modFlags, aKbdModFlags, NSEventModifierFlagShift, keyswapMode);
	updateFlagState(input, modFlags, aKbdModFlags, NSEventModifierFlagControl, keyswapMode);
	updateFlagState(input, modFlags, aKbdModFlags, NSEventModifierFlagOption, keyswapMode);
	updateFlagState(input, modFlags, aKbdModFlags, NSEventModifierFlagCommand, keyswapMode);
	updateFlagState(input, modFlags, aKbdModFlags, NSEventModifierFlagNumericPad, keyswapMode);
	return TRUE;
}

static BOOL ensureModifierFlagStates(rdpInput *input, UINT32 modFlags,
                                     MF_MODIFIER_KEYSWAP_MODE keyswapMode)
{
	if (!input || (keyswapMode == MF_MODIFIER_KEYSWAP_NONE))
		return TRUE;

	const UINT32 flags[] = { NSEventModifierFlagControl, NSEventModifierFlagOption,
		                     NSEventModifierFlagCommand };
	const UINT32 scancodes[] = { RDP_SCANCODE_LCONTROL, RDP_SCANCODE_LMENU,
		                         RDP_SCANCODE_LWIN };

	for (size_t i = 0; i < sizeof(flags) / sizeof(flags[0]); i++)
	{
		if ((modFlags & flags[i]) == 0)
			continue;

		UINT32 scancode = mac_modifier_keyswap_scancode(flags[i], keyswapMode, scancodes[i]);
		if (!freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, scancode))
			return FALSE;
	}

	return TRUE;
}

static BOOL mac_modifier_keyswap_applies(const mfContext *mfc, const rdpSettings *settings)
{
	if (!mfc || (mfc->modifierKeyswapMode == MF_MODIFIER_KEYSWAP_NONE))
		return FALSE;

	if (mfc->modifierKeyswapFilter[0] == '\0')
		return TRUE;

	const char *host = settings ? freerdp_settings_get_string(settings, FreeRDP_ServerHostname) : NULL;
	if (!host || (host[0] == '\0'))
		return FALSE;

	char filter[sizeof(mfc->modifierKeyswapFilter)];
	strncpy(filter, mfc->modifierKeyswapFilter, sizeof(filter) - 1);
	filter[sizeof(filter) - 1] = '\0';

	char *token = strtok(filter, ",;\r\n\t ");
	while (token)
	{
		if (strcmp(token, host) == 0)
			return TRUE;
		token = strtok(NULL, ",;\r\n\t ");
	}

	return FALSE;
}

static MF_MODIFIER_KEYSWAP_MODE mac_modifier_keyswap_mode(const mfContext *mfc,
                                                          const rdpSettings *settings)
{
	return mac_modifier_keyswap_applies(mfc, settings) ? mfc->modifierKeyswapMode
	                                                   : MF_MODIFIER_KEYSWAP_NONE;
}

static UINT32 mac_modifier_keyswap_scancode(UINT32 flag, MF_MODIFIER_KEYSWAP_MODE mode,
                                            UINT32 scancode)
{
	if (mode == MF_MODIFIER_KEYSWAP_APPLE_TO_PC)
	{
		if (flag == NSEventModifierFlagCommand)
			return RDP_SCANCODE_LCONTROL;
		if (flag == NSEventModifierFlagControl)
			return RDP_SCANCODE_LWIN;
	}
	else if (mode == MF_MODIFIER_KEYSWAP_PC_TO_APPLE)
	{
		if (flag == NSEventModifierFlagOption)
			return RDP_SCANCODE_LCONTROL;
		if (flag == NSEventModifierFlagCommand)
			return RDP_SCANCODE_LMENU;
		if (flag == NSEventModifierFlagControl)
			return RDP_SCANCODE_LWIN;
	}

	return scancode;
}

static BOOL mac_send_rdp_scancode(rdpInput *input, UINT32 rdpScancode)
{
	WINPR_ASSERT(input);
	return freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, rdpScancode) &&
	       freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, rdpScancode);
}

- (BOOL)canSendRemoteInput
{
	return is_connected && instance && instance->context && instance->context->input;
}

- (void)sendRemoteUnicodeString:(NSString *)string
{
	if (![self canSendRemoteInput] || !string)
		return;

	if (!instance || !instance->context || !instance->context->settings ||
	    !freerdp_settings_get_bool(instance->context->settings, FreeRDP_UnicodeInput))
	{
		NSBeep();
		return;
	}

	rdpInput *input = instance->context->input;
	NSUInteger length = [string length];

	WLog_INFO(TAG, "MAC_SEND_PASSWORD_TRACE begin length=%zu", (size_t)length);

	for (NSUInteger index = 0; index < length; index++)
	{
		const unichar character = [string characterAtIndex:index];
		WLog_INFO(TAG, "MAC_SEND_PASSWORD_TRACE index=%zu code=U+%04X",
		          (size_t)index, (unsigned int)character);
		const BOOL downSent = freerdp_input_send_unicode_keyboard_event(input, 0, character);
		Sleep(10);
		const BOOL upSent =
		    freerdp_input_send_unicode_keyboard_event(input, KBD_FLAGS_RELEASE, character);
		Sleep(10);
		WLog_INFO(TAG, "MAC_SEND_PASSWORD_TRACE index=%zu sent down=%d up=%d",
		          (size_t)index, downSent, upSent);
	}

	WLog_INFO(TAG, "MAC_SEND_PASSWORD_TRACE end length=%zu", (size_t)length);
}

- (BOOL)sendRemoteClipboardString:(NSString *)string
{
	if (![self canSendRemoteInput] || !string || ([string length] == 0) || !mfc || !mfc->clipboard ||
	    !mfc->cliprdr || !mfc->clipboardSync)
		return NO;

	const char *data = [string cStringUsingEncoding:NSUTF8StringEncoding];
	const size_t dataLen = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	if (!data || (dataLen == 0))
		return NO;

	BOOL storedFormat = FALSE;
	const UINT32 plainTextFormatId = ClipboardRegisterFormat(mfc->clipboard, "text/plain");
	storedFormat |= ClipboardSetData(mfc->clipboard, plainTextFormatId, data, dataLen + 1);

	storedFormat |= ClipboardSetData(mfc->clipboard, CF_TEXT, data, dataLen + 1);

	NSData *unicodeData = [string dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
	if (unicodeData && ([unicodeData length] > 0))
	{
		NSMutableData *unicodeClipboardData = [[unicodeData mutableCopy] autorelease];
		const WCHAR nullTerminator = 0;
		[unicodeClipboardData appendBytes:&nullTerminator length:sizeof(nullTerminator)];
		storedFormat |= ClipboardSetData(mfc->clipboard, CF_UNICODETEXT,
		                                  [unicodeClipboardData bytes],
		                                  [unicodeClipboardData length]);
	}

	if (!storedFormat)
		return NO;

	return (mac_cliprdr_send_client_format_list(mfc->cliprdr) != 0);
}

- (void)sendRemoteStringViaKeyboard:(NSString *)string
{
	if (![self canSendRemoteInput] || !string || ([string length] == 0))
		return;

	WLog_INFO(TAG, "Sending password via keyboard (%zu chars)", [string length]);
	rdpInput *input = instance->context->input;
	NSUInteger length = [string length];

	for (NSUInteger index = 0; index < length; index++) {
		const unichar character = [string characterAtIndex:index];
		BOOL needsShift = FALSE;
		const UINT32 scancode = mac_char_to_scancode(character, &needsShift);

		if (scancode == 0) {
			WLog_INFO(TAG, "SKIPPED unmapped char[%zu]: U+%04X (decimal %d)",
			          index, character, (int)character);
			continue;
		}

		WLog_INFO(TAG, "Sending char[%zu]: '%c' (U+%04X) scancode=0x%04X shift=%d",
		          index, (character >= 32 && character < 127) ? character : '?', character, scancode, needsShift);

		if (needsShift)
			(void)freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, RDP_SCANCODE_LSHIFT);

		(void)freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, scancode);
		(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, scancode);

		if (needsShift)
			(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_LSHIFT);
	}
}

- (void)sendStoredPasswordForServer:(NSString *)serverName
	               username:(NSString *)username
	                 domain:(NSString *)domain
{
	NSString *keychainPromptKey = [NSString stringWithFormat:@"FreeRDP_KeychainPrompt_%@", serverName];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if (![defaults boolForKey:keychainPromptKey])
	{
		NSAlert *alert = [NSAlert new];
		alert.messageText = @"Allow Keychain Access";
		alert.informativeText = [NSString stringWithFormat:@"FreeRDP would like to access the keychain to retrieve the password for %@.\n\nThis will only be asked once.", serverName];
		[alert addButtonWithTitle:@"Allow"];
		[alert addButtonWithTitle:@"Deny"];
		alert.alertStyle = NSAlertStyleInformational;

		NSModalResponse response = [alert runModal];
		[alert release];

		if (response == NSAlertFirstButtonReturn)
		{
			[defaults setBool:YES forKey:keychainPromptKey];
		}
		else
		{
			NSBeep();
			return;
		}
	}

	NSString *password = mac_resolve_stored_password(serverName, username, domain);

	if ((!password || ([password length] == 0)) && instance && instance->context &&
	    instance->context->settings)
	{
		password = mac_dialog_setting_string(instance->context->settings, FreeRDP_Password);
	}

	if (!password || ([password length] == 0))
	{
		NSBeep();
		return;
	}

	WLog_INFO(TAG, "sendStoredPasswordForServer: password length=%zu", [password length]);

	if (!instance || !instance->context || !instance->context->settings ||
	    !freerdp_settings_get_bool(instance->context->settings, FreeRDP_UnicodeInput))
	{
		WLog_INFO(TAG, "Unicode input unavailable; not sending password without modifier keys");
		NSBeep();
		return;
	}

	WLog_INFO(TAG, "Sending password via Unicode character input");
	[self sendRemoteUnicodeString:password];
}

- (void)sendRemoteKeyScancode:(UINT32)rdpScancode
{
	if (![self canSendRemoteInput])
		return;

	rdpInput *input = instance->context->input;

	if (rdpScancode == RDP_SCANCODE_PAUSE)
	{
		(void)freerdp_input_send_keyboard_pause_event(input);
		return;
	}

	(void)mac_send_rdp_scancode(input, rdpScancode);
}

- (void)sendRemoteCtrlAltDel
{
	if (![self canSendRemoteInput])
		return;

	rdpInput *input = instance->context->input;
	(void)freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, RDP_SCANCODE_LCONTROL);
	(void)freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, RDP_SCANCODE_LMENU);
	(void)freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, RDP_SCANCODE_DELETE);
	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_DELETE);
	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_LMENU);
	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_LCONTROL);
}

- (void)sendRemoteBreakKey
{
	if (![self canSendRemoteInput])
		return;

	rdpInput *input = instance->context->input;
	(void)freerdp_input_send_keyboard_event_ex(input, TRUE, FALSE, RDP_SCANCODE_LCONTROL);
	(void)freerdp_input_send_keyboard_pause_event(input);
	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_LCONTROL);
}

- (void)refreshBitmap
{
	if (!instance || !instance->context || !instance->context->gdi)
		return;

	[self requestRemoteDesktopRefresh];

	rdpGdi *gdi = instance->context->gdi;
	(void)gdi_InvalidateRegion(gdi->primary->hdc, 0, 0, (INT32)gdi->width, (INT32)gdi->height);
	[self setNeedsDisplay:YES];
}

- (void)requestRemoteDesktopRefresh
{
	if (!instance || !instance->context || !instance->context->update ||
	    !instance->context->update->RefreshRect)
		return;

	rdpContext *rdpContext = instance->context;
	rdpGdi *gdi = rdpContext->gdi;
	rdpSettings *settings = rdpContext->settings;
	if (!gdi || !settings || !freerdp_settings_get_bool(settings, FreeRDP_RefreshRect))
		return;
	if ((gdi->width == 0) || (gdi->height == 0))
		return;

	RECTANGLE_16 area = { 0 };
	area.left = 0;
	area.top = 0;
	area.right = (UINT16)MIN(gdi->width - 1, UINT16_MAX);
	area.bottom = (UINT16)MIN(gdi->height - 1, UINT16_MAX);
	(void)rdpContext->update->RefreshRect(rdpContext, 1, &area);
}

- (void)scheduleChromaKeyRefreshSweep
{
	if (!mfc || !mfc->chromaKeyEnabled)
		return;

	NSArray *delays = @[ @0.5, @1.0, @2.0, @4.0, @8.0, @12.0 ];
	for (NSNumber *delay in delays)
	{
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
		                             (int64_t)([delay doubleValue] * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			               if (self->mfc && self->mfc->chromaKeyEnabled && [self is_connected])
				               [self refreshBitmap];
		               });
	}
}

- (void)schedulePostDragRefresh
{
	NSArray *delays = @[ @0.05, @0.2, @0.6 ];
	for (NSNumber *delay in delays)
	{
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
		                             (int64_t)([delay doubleValue] * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			               if ([self is_connected])
				               [self refreshBitmap];
		               });
	}
}

static BOOL releaseFlagStates(rdpInput *input, UINT32 aKbdModFlags,
                              MF_MODIFIER_KEYSWAP_MODE keyswapMode)
{
	BOOL rc = updateFlagStates(input, 0, aKbdModFlags, keyswapMode);

	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_LCONTROL);
	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_LMENU);
	(void)freerdp_input_send_keyboard_event_ex(input, FALSE, FALSE, RDP_SCANCODE_LWIN);
	return rc;
}

static BOOL mac_is_chroma_key_pixel(const mfContext *mfc, uint32_t pixel)
{
	if (!mfc || !mfc->chromaKeyEnabled)
		return FALSE;

	const float tolerance = fminf(fmaxf(mfc->chromaKeyTolerance, 0.0f), 255.0f);
	return (mac_chroma_key_max_diff(mfc, pixel) <= (UINT32)lrintf(tolerance))
	           ? TRUE
	           : FALSE;
}

static UINT32 mac_chroma_key_max_diff(const mfContext *mfc, uint32_t pixel)
{
	if (!mfc)
		return UINT32_MAX;

	uint32_t targetColor = mfc->chromaKeyColor;
	uint8_t targetR = (targetColor >> 16) & 0xFF;
	uint8_t targetG = (targetColor >> 8) & 0xFF;
	uint8_t targetB = targetColor & 0xFF;
	uint8_t b = (pixel >> 0) & 0xFF;
	uint8_t g = (pixel >> 8) & 0xFF;
	uint8_t r = (pixel >> 16) & 0xFF;
	float diffR = fabsf((float)r - (float)targetR);
	float diffG = fabsf((float)g - (float)targetG);
	float diffB = fabsf((float)b - (float)targetB);
	float maxDiff = fmaxf(fmaxf(diffR, diffG), diffB);

	return (UINT32)lrintf(maxDiff);
}

static void mac_apply_chroma_key_feathering(const mfContext *mfc, const uint32_t *source,
                                            uint32_t *buffer, size_t width, size_t height)
{
	if (!mfc || !mfc->chromaKeyFeatheringEnabled || !source || !buffer || width == 0 ||
	    height == 0)
		return;

	const UINT32 tolerance =
	    (UINT32)lrintf(fminf(fmaxf(mfc->chromaKeyTolerance, 0.0f), 255.0f));
	const UINT32 fringeThreshold = MIN(255, tolerance + 96);

	for (size_t y = 0; y < height; y++)
	{
		for (size_t x = 0; x < width; x++)
		{
			const size_t index = (y * width) + x;
			const uint32_t pixel = source[index];
			if (mac_is_chroma_key_pixel(mfc, pixel))
				continue;

			const UINT32 diff = mac_chroma_key_max_diff(mfc, pixel);
			if ((diff <= tolerance) || (diff > fringeThreshold))
				continue;

			BOOL nearChroma = FALSE;
			if ((x > 0) && mac_is_chroma_key_pixel(mfc, source[index - 1]))
				nearChroma = TRUE;
			else if (((x + 1) < width) && mac_is_chroma_key_pixel(mfc, source[index + 1]))
				nearChroma = TRUE;
			else if ((y > 0) && mac_is_chroma_key_pixel(mfc, source[index - width]))
				nearChroma = TRUE;
			else if (((y + 1) < height) && mac_is_chroma_key_pixel(mfc, source[index + width]))
				nearChroma = TRUE;

			if (!nearChroma)
				continue;

			buffer[index] = 0x00000000;
		}
	}
}

static BOOL mac_additional_transparency_for_pixel(const mfContext *mfc, uint32_t pixel,
	                                             UINT32 *transparency, BOOL *blur)
{
	if (!mfc)
		return FALSE;

	size_t maxAdditionalColors =
	    sizeof(mfc->additionalTransparencyColors) / sizeof(mfc->additionalTransparencyColors[0]);
	size_t colorCount = MIN(mfc->additionalTransparencyColorCount, maxAdditionalColors);
	uint8_t b = (pixel >> 0) & 0xFF;
	uint8_t g = (pixel >> 8) & 0xFF;
	uint8_t r = (pixel >> 16) & 0xFF;

	for (size_t i = 0; i < colorCount; i++)
	{
		uint32_t targetColor = mfc->additionalTransparencyColors[i];
		uint8_t targetR = (targetColor >> 16) & 0xFF;
		uint8_t targetG = (targetColor >> 8) & 0xFF;
		uint8_t targetB = targetColor & 0xFF;
		UINT32 tolerance = MIN(mfc->additionalTransparencyTolerances[i], 255);
		UINT32 diffR = (r > targetR) ? (UINT32)(r - targetR) : (UINT32)(targetR - r);
		UINT32 diffG = (g > targetG) ? (UINT32)(g - targetG) : (UINT32)(targetG - g);
		UINT32 diffB = (b > targetB) ? (UINT32)(b - targetB) : (UINT32)(targetB - b);
		UINT32 maxDiff = MAX(MAX(diffR, diffG), diffB);

		if (maxDiff <= tolerance)
		{
			if (transparency)
				*transparency = MIN(mfc->additionalTransparencyLevels[i], 100);
			if (blur)
				*blur = mfc->additionalTransparencyBlur[i];
			return TRUE;
		}
	}

	return FALSE;
}

static void mac_release_mask_data(void *info, const void *data, size_t size)
{
	(void)info;
	(void)size;
	free((void *)data);
}

static BOOL mac_is_resize_cursor(NSCursor *cursor)
{
	if (!cursor)
		return FALSE;

	if ((cursor == [NSCursor resizeLeftRightCursor]) ||
	    (cursor == [NSCursor resizeUpDownCursor]))
	{
		return TRUE;
	}

	return [cursor isEqual:[NSCursor resizeLeftRightCursor]] ||
	       [cursor isEqual:[NSCursor resizeUpDownCursor]];
}

static BOOL mac_view_point_to_buffer_point(MRDPView *view, const mfContext *mfc,
	                                       rdpContext *context, NSPoint viewPoint,
	                                       int *outX, int *outY)
{
	rdpGdi *gdi = context ? context->gdi : NULL;
	if (!view || !mfc || !mfc->chromaKeyEnabled || !gdi || !gdi->primary_buffer)
		return FALSE;

	NSRect bounds = mac_smart_sizing_display_rect(view, context);
	if (!NSPointInRect(viewPoint, bounds))
		return FALSE;

	CGFloat width = NSWidth(bounds);
	CGFloat height = NSHeight(bounds);
	if (width <= 0 || height <= 0)
		return FALSE;

	CGFloat xScale = (CGFloat)gdi->width / width;
	CGFloat yScale = (CGFloat)gdi->height / height;
	int bx = (int)floor((viewPoint.x - NSMinX(bounds)) * xScale);
	int by = (int)floor((NSMaxY(bounds) - viewPoint.y) * yScale);

	if (bx < 0 || bx >= (int)gdi->width || by < 0 || by >= (int)gdi->height)
		return FALSE;

	if (outX)
		*outX = bx;
	if (outY)
		*outY = by;

	return TRUE;
}

static BOOL mac_has_chroma_key_margin(const mfContext *mfc, const rdpGdi *gdi, int x, int y,
	                                  int radius)
{
	uint32_t *buffer = gdi ? (uint32_t *)gdi->primary_buffer : NULL;

	if (!mfc || !gdi || !buffer || radius < 1)
		return FALSE;

	for (int dy = -radius; dy <= radius; dy++)
	{
		for (int dx = -radius; dx <= radius; dx++)
		{
			if ((dx == 0) && (dy == 0))
				continue;

			const int nx = x + dx;
			const int ny = y + dy;

			if (nx < 0 || nx >= (int)gdi->width || ny < 0 || ny >= (int)gdi->height)
				return FALSE;

			const uint32_t pixel = buffer[(size_t)ny * (size_t)gdi->width + (size_t)nx];
			if (!mac_is_chroma_key_pixel(mfc, pixel))
				return FALSE;
		}
	}

	return TRUE;
}

- (void)releaseResources
{
	[self endDeferredWindowDrag];
	[self stopMousePassThroughMonitor];
	[[self window] setIgnoresMouseEvents:NO];
	mousePassThroughArmed = NO;
	[additionalTransparencyBlurView removeFromSuperview];
	[additionalTransparencyBlurView release];
	additionalTransparencyBlurView = nil;
	[additionalTransparencyBlurMaskLayer release];
	additionalTransparencyBlurMaskLayer = nil;

	for (int i = 0; i < argc; i++)
		free(argv[i]);

	if (!is_connected)
		return;

	free(pixel_data);
}

- (CGImageRef)createChromaKeyImage
{
	if (!self->bitmap_context ||
	    (!mfc->chromaKeyEnabled && (mfc->additionalTransparencyColorCount == 0)))
	{
		[self updateAdditionalTransparencyBlurMask:NULL width:0 height:0];
		return CGBitmapContextCreateImage(self->bitmap_context);
	}

	rdpGdi *gdi = context->gdi;

	uint8_t *source = (uint8_t *)gdi->primary_buffer;
	const size_t width = gdi->width;
	const size_t height = gdi->height;
	const size_t pixelCount = width * height;
	const size_t sourceStride = gdi->stride;
	const size_t imageStride = width * sizeof(uint32_t);
	uint32_t *originalBuffer = (uint32_t *)malloc(pixelCount * sizeof(uint32_t));
	uint32_t *imageBuffer = (uint32_t *)malloc(pixelCount * sizeof(uint32_t));
	uint32_t *buffer = imageBuffer;
	uint8_t *blurMask = NULL;
	BOOL hasBlur = FALSE;

	if (!source || !originalBuffer || !imageBuffer || (width == 0) || (height == 0) ||
	    (sourceStride < imageStride))
	{
		free(originalBuffer);
		free(imageBuffer);
		[self updateAdditionalTransparencyBlurMask:NULL width:0 height:0];
		return NULL;
	}

	for (size_t y = 0; y < height; y++)
		memcpy(&originalBuffer[y * width], &source[y * sourceStride], imageStride);
	memcpy(imageBuffer, originalBuffer, pixelCount * sizeof(uint32_t));

	size_t maxAdditionalColors =
	    sizeof(mfc->additionalTransparencyBlur) / sizeof(mfc->additionalTransparencyBlur[0]);
	size_t additionalColorCount = MIN(mfc->additionalTransparencyColorCount, maxAdditionalColors);
	for (size_t i = 0; i < additionalColorCount; i++)
	{
		if (mfc->additionalTransparencyBlur[i])
		{
			hasBlur = TRUE;
			break;
		}
	}

	if (hasBlur)
		blurMask = (uint8_t *)calloc(pixelCount, sizeof(uint8_t));

	size_t chromaPixelCount = 0;
	for (size_t i = 0; i < pixelCount; i++)
	{
		uint32_t pixel = buffer[i];

		if (mac_is_chroma_key_pixel(mfc, pixel))
		{
			chromaPixelCount++;
			buffer[i] = 0x00000000;
		}
		else
		{
			UINT32 transparency = 0;
			BOOL blur = FALSE;
			if (!mac_additional_transparency_for_pixel(mfc, pixel, &transparency, &blur))
				continue;
			UINT32 alpha = 255 - (transparency * 255 / 100);
			uint32_t color = pixel & 0x00FFFFFF;
			if (blur)
			{
				color = pixel & 0x00FFFFFF;
				if (blurMask)
					blurMask[i] = 0xFF;
			}
			buffer[i] = color | (alpha << 24);
		}
	}

	if (mfc->chromaKeyEnabled)
		mac_apply_chroma_key_feathering(mfc, originalBuffer, buffer, width, height);

	if (blurMask)
		[self updateAdditionalTransparencyBlurMask:blurMask width:width height:height];
	else
		[self updateAdditionalTransparencyBlurMask:NULL width:0 height:0];

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, imageBuffer,
	                                                          pixelCount * sizeof(uint32_t),
	                                                          mac_release_mask_data);
	if (provider)
		imageBuffer = NULL;
	CGImageRef cgImage = NULL;
	if (colorSpace && provider)
	{
		cgImage = CGImageCreate(width, height, 8, 32, imageStride, colorSpace,
		                        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
		                        provider, NULL, FALSE, kCGRenderingIntentDefault);
	}
	if (provider)
		CGDataProviderRelease(provider);
	if (colorSpace)
		CGColorSpaceRelease(colorSpace);
	free(originalBuffer);
	free(imageBuffer);

	if (!chromaKeyRepaintRequested && (chromaPixelCount > (pixelCount / 20)))
	{
		chromaKeyRepaintRequested = YES;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self scheduleChromaKeyRefreshSweep];
		});
	}

	return cgImage;
}

- (void)drawRect:(NSRect)rect
{
	if (!context)
		return;

	if (self->bitmap_context)
	{
		CGContextRef cgContext = [[NSGraphicsContext currentContext] CGContext];
		CGImageRef cgImage = [self createChromaKeyImage];
		NSRect drawRect = mac_smart_sizing_display_rect(self, context);
		CGContextSaveGState(cgContext);
		CGContextClearRect(cgContext, [self bounds]);
		if (cgImage)
		{
			CGContextClipToRect(
			    cgContext, CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height));
			CGContextDrawImage(cgContext, drawRect, cgImage);
			CGImageRelease(cgImage);
		}
		CGContextRestoreGState(cgContext);
	}
	else
	{
		/* Fill the screen with black */
		[[NSColor blackColor] set];
		NSRectFill([self bounds]);
	}

	if (deferredWindowDragActive)
	{
		NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSIntegralRect(deferredWindowDragOutlineRect)];
		CGFloat dash[2] = { 6.0, 4.0 };
		[path setLineWidth:2.0];
		[path setLineDash:dash count:2 phase:0.0];
		[[NSColor colorWithCalibratedWhite:1.0 alpha:0.92] setStroke];
		[path stroke];

		path = [NSBezierPath bezierPathWithRect:NSIntegralRect(NSInsetRect(deferredWindowDragOutlineRect, 1.0, 1.0))];
		[path setLineWidth:1.0];
		[path setLineDash:dash count:2 phase:0.0];
		[[NSColor colorWithCalibratedWhite:0.0 alpha:0.55] setStroke];
		[path stroke];
	}

	if (windowDragTitlebarPreviewVisible)
		[self drawWindowDragTitlebarPreview];

	[self scheduleMousePassThroughSync];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"MRDPMultimonFramebufferDidUpdate"
	                                                    object:self];
}

- (CGImageRef)newFramebufferImage
{
	if (!context || !self->bitmap_context)
		return NULL;

	return [self createChromaKeyImage];
}

- (BOOL)isRemotePixelTransparentAtX:(int)x y:(int)y
{
	if (!mfc || !mfc->chromaKeyEnabled || !context || !context->gdi ||
	    !context->gdi->primary_buffer)
		return NO;

	rdpGdi *gdi = context->gdi;
	if (x < 0 || y < 0 || x >= (int)gdi->width || y >= (int)gdi->height)
		return NO;

	uint32_t *buffer = (uint32_t *)gdi->primary_buffer;
	uint32_t pixel = buffer[(size_t)y * (size_t)gdi->width + (size_t)x];
	if (!mac_is_chroma_key_pixel(mfc, pixel))
		return NO;

	if (mac_is_resize_cursor([NSCursor currentSystemCursor]))
		return NO;

	return mac_has_chroma_key_margin(mfc, gdi, x, y, 8);
}

- (void)sendRemoteMouseEventWithFlags:(UINT16)flags x:(UINT16)x y:(UINT16)y
{
	if (!self.is_connected || !mfc)
		return;

	freerdp_client_send_button_event(&mfc->common, FALSE, flags, x, y);
}

- (void)sendRemoteScrollWithDeltaX:(CGFloat)dx deltaY:(CGFloat)dy x:(UINT16)x y:(UINT16)y
{
	UINT16 flags = 0;
	if (!mac_scroll_flags_from_deltas(dx, dy, &flags))
		return;

	[self sendRemoteMouseEventWithFlags:flags x:x y:y];
}

- (void)sendRemoteMouseButton:(int)button x:(UINT16)x y:(UINT16)y down:(BOOL)down
{
	UINT16 flags = down ? PTR_FLAGS_DOWN : 0;

	switch (button)
	{
		case 0:
			flags |= PTR_FLAGS_BUTTON1;
			break;
		case 1:
			flags |= PTR_FLAGS_BUTTON2;
			break;
		case 2:
			flags |= PTR_FLAGS_BUTTON3;
			break;
		default:
			return;
	}

	[self sendRemoteMouseEventWithFlags:flags x:x y:y];
}

- (void)onPasteboardTimerFired:(NSTimer *)timer
{
	UINT32 formatId;
	BOOL formatMatch;
	int changeCount;
	NSData *formatData;
	NSString *formatString;
	const char *formatType;
	NSPasteboardItem *item;
	changeCount = (int)[pasteboard_rd changeCount];

	if (changeCount == pasteboard_changecount)
		return;

	pasteboard_changecount = changeCount;
	NSArray *items = [pasteboard_rd pasteboardItems];

	if ([items count] < 1)
		return;

	item = [items objectAtIndex:0];
	/**
	 * System-Declared Uniform Type Identifiers:
	 * https://developer.apple.com/library/ios/documentation/Miscellaneous/Reference/UTIRef/Articles/System-DeclaredUniformTypeIdentifiers.html
	 */
	formatMatch = FALSE;

	NSArray *classes = [NSArray arrayWithObject:[NSURL class]];
	NSDictionary *options =
	    [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
	                                forKey:NSPasteboardURLReadingFileURLsOnlyKey];
	NSArray *urls = [pasteboard_rd readObjectsForClasses:classes options:options];
	NSMutableString *uriList = [NSMutableString string];

	for (NSURL *url in urls)
	{
		if (![url isFileURL])
			continue;

		NSURL *pathURL = [url filePathURL];
		NSString *path = [pathURL path];
		if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path])
			continue;

		[uriList appendString:[pathURL absoluteString]];
		[uriList appendString:@"\r\n"];
	}

	if ([uriList length] > 0)
	{
		const char *data = [uriList cStringUsingEncoding:NSUTF8StringEncoding];
		const size_t dataLen = [uriList lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		formatId = ClipboardRegisterFormat(mfc->clipboard, "text/uri-list");
		ClipboardSetData(mfc->clipboard, formatId, data, dataLen + 1);
		formatMatch = TRUE;
	}

	for (NSString *type in [item types])
	{
		if (formatMatch)
			break;

		formatType = [type UTF8String];

		if (strcmp(formatType, "public.utf8-plain-text") == 0)
		{
			formatData = [item dataForType:type];

			if (formatData == nil)
			{
				break;
			}

			formatString = [[NSString alloc] initWithData:formatData encoding:NSUTF8StringEncoding];

			const char *data = [formatString cStringUsingEncoding:NSUTF8StringEncoding];
			const size_t dataLen = [formatString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
			formatId = ClipboardRegisterFormat(mfc->clipboard, "text/plain");
			ClipboardSetData(mfc->clipboard, formatId, data, dataLen + 1);
			[formatString release];

			formatMatch = TRUE;

			break;
		}
	}

	if (!formatMatch)
		ClipboardEmpty(mfc->clipboard);

	if (mfc->clipboardSync)
		mac_cliprdr_send_client_format_list(mfc->cliprdr);
}

- (void)pause
{
	[self parkRemotePointer];

	dispatch_async(dispatch_get_main_queue(), ^{
		[self->pasteboard_timer invalidate];
	});
	NSArray *trackingAreas = self.trackingAreas;

	for (NSTrackingArea *ta in trackingAreas)
	{
		[self removeTrackingArea:ta];
	}
	releaseFlagStates(instance->context->input, kbdModFlags,
	                  mac_modifier_keyswap_mode(mfc, instance->context->settings));
	kbdModFlags = 0;
}

- (void)parkRemotePointer
{
	if (!self.is_connected || !context)
		return;

	rdpSettings *settings = context->settings;
	if (!settings)
		return;

	const UINT32 width = freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);
	const UINT32 height = freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);
	if ((width == 0) || (height == 0))
		return;

	const int inset = 64;
	const int x = (width > (UINT32)(inset * 2)) ? inset : (int)(width / 2);
	const int y = (height > (UINT32)(inset * 2)) ? inset : (int)(height / 2);

	mf_scale_mouse_event(context, PTR_FLAGS_MOVE, x, y);
	NSLog(@"MRDP parked remote pointer on focus loss x=%d y=%d", x, y);
}

- (void)resume
{
	if (!self.is_connected)
		return;

	releaseFlagStates(instance->context->input, kbdModFlags,
	                  mac_modifier_keyswap_mode(mfc, instance->context->settings));
	kbdModFlags = 0;
	freerdp_input_send_focus_in_event(instance->context->input, 0);

	dispatch_async(dispatch_get_main_queue(), ^{
		self->pasteboard_timer =
		    [NSTimer scheduledTimerWithTimeInterval:0.5
		                                     target:self
		                                   selector:@selector(onPasteboardTimerFired:)
		                                   userInfo:nil
		                                    repeats:YES];

		NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
		    initWithRect:[self visibleRect]
		         options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
		                 NSTrackingCursorUpdate | NSTrackingEnabledDuringMouseDrag |
		                 NSTrackingActiveWhenFirstResponder
		           owner:self
		        userInfo:nil];
		[self addTrackingArea:trackingArea];
		[trackingArea release];
	});
}

- (void)setScrollOffset:(int)xOffset y:(int)yOffset w:(int)width h:(int)height
{
	WINPR_ASSERT(mfc);

	mfc->yCurrentScroll = yOffset;
	mfc->xCurrentScroll = xOffset;
	mfc->client_height = height;
	mfc->client_width = width;
}

static void mac_OnChannelConnectedEventHandler(void *context, const ChannelConnectedEventArgs *e)
{
	rdpSettings *settings;
	mfContext *mfc = (mfContext *)context;

	WINPR_ASSERT(mfc);
	WINPR_ASSERT(e);

	settings = mfc->common.context.settings;
	WINPR_ASSERT(settings);

	if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
	{
		mac_cliprdr_init(mfc, (CliprdrClientContext *)e->pInterface);
	}
	else if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
	{
		mfc->disp = (DispClientContext *)e->pInterface;
	}
	else if (strcmp(e->name, ENCOMSP_SVC_CHANNEL_NAME) == 0)
	{
	}
	else
		freerdp_client_OnChannelConnectedEventHandler(context, e);
}

static void mac_OnChannelDisconnectedEventHandler(void *context,
                                                  const ChannelDisconnectedEventArgs *e)
{
	rdpSettings *settings;
	mfContext *mfc = (mfContext *)context;

	WINPR_ASSERT(mfc);
	WINPR_ASSERT(e);

	settings = mfc->common.context.settings;
	WINPR_ASSERT(settings);

	if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
	{
		mac_cliprdr_uninit(mfc, (CliprdrClientContext *)e->pInterface);
	}
	else if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
	{
		mfc->disp = NULL;
	}
	else if (strcmp(e->name, ENCOMSP_SVC_CHANNEL_NAME) == 0)
	{
	}
	else
		freerdp_client_OnChannelDisconnectedEventHandler(context, e);
}

BOOL mac_pre_connect(freerdp *instance)
{
	rdpSettings *settings;
	rdpUpdate *update;

	WINPR_ASSERT(instance);
	WINPR_ASSERT(instance->context);

	update = instance->context->update;
	WINPR_ASSERT(update);

	update->BeginPaint = mac_begin_paint;
	update->EndPaint = mac_end_paint;
	update->DesktopResize = mac_desktop_resize;

	settings = instance->context->settings;
	WINPR_ASSERT(settings);

	if (!freerdp_settings_get_string(settings, FreeRDP_ServerHostname))
	{
		WLog_ERR(TAG, "error: server hostname was not specified with /v:<server>[:port]");
		return FALSE;
	}

	if (!freerdp_settings_set_uint32(settings, FreeRDP_OsMajorType, OSMAJORTYPE_MACINTOSH))
		return FALSE;
	if (!freerdp_settings_set_uint32(settings, FreeRDP_OsMinorType, OSMINORTYPE_MACINTOSH))
		return FALSE;
	PubSub_SubscribeChannelConnected(instance->context->pubSub, mac_OnChannelConnectedEventHandler);
	PubSub_SubscribeChannelDisconnected(instance->context->pubSub,
	                                    mac_OnChannelDisconnectedEventHandler);

	return TRUE;
}

BOOL mac_post_connect(freerdp *instance)
{
	rdpGdi *gdi;
	rdpPointer rdp_pointer = WINPR_C_ARRAY_INIT;
	mfContext *mfc;
	MRDPView *view;

	WINPR_ASSERT(instance);

	mfc = (mfContext *)instance->context;
	WINPR_ASSERT(mfc);

	view = (MRDPView *)mfc->view;
	WINPR_ASSERT(view);

	rdp_pointer.size = sizeof(rdpPointer);
	rdp_pointer.New = mf_Pointer_New;
	rdp_pointer.Free = mf_Pointer_Free;
	rdp_pointer.Set = mf_Pointer_Set;
	rdp_pointer.SetNull = mf_Pointer_SetNull;
	rdp_pointer.SetDefault = mf_Pointer_SetDefault;
	rdp_pointer.SetPosition = mf_Pointer_SetPosition;

	if (!gdi_init(instance, PIXEL_FORMAT_BGRX32))
		return FALSE;

	gdi = instance->context->gdi;
	view->bitmap_context = mac_create_bitmap_context(instance->context);
	graphics_register_pointer(instance->context->graphics, &rdp_pointer);
	/* setup pasteboard (aka clipboard) for copy operations (write only) */
	view->pasteboard_wr = [NSPasteboard generalPasteboard];
	/* setup pasteboard for read operations */
	dispatch_async(dispatch_get_main_queue(), ^{
		view->pasteboard_rd = [NSPasteboard generalPasteboard];
		view->pasteboard_changecount = -1;
	});
	[view resume];
	[view scheduleChromaKeyRefreshSweep];
	mfc->appleKeyboardType = mac_detect_keyboard_type();
	return TRUE;
}

void mac_post_disconnect(freerdp *instance)
{
	mfContext *mfc;
	MRDPView *view;
	if (!instance || !instance->context)
		return;

	mfc = (mfContext *)instance->context;
	view = (MRDPView *)mfc->view;

	[view pause];

	PubSub_UnsubscribeChannelConnected(instance->context->pubSub,
	                                   mac_OnChannelConnectedEventHandler);
	PubSub_UnsubscribeChannelDisconnected(instance->context->pubSub,
	                                      mac_OnChannelDisconnectedEventHandler);
	gdi_free(instance);
}

static BOOL mac_show_auth_dialog(MRDPView *view, NSString *title, char **username, char **password,
                                 char **domain)
{
	const rdpSettings *settings = view->context ? view->context->settings : NULL;
	WINPR_ASSERT(view);
	WINPR_ASSERT(title);
	WINPR_ASSERT(username);
	WINPR_ASSERT(password);
	WINPR_ASSERT(domain);

	PasswordDialog *dialog = [PasswordDialog new];

	dialog.serverHostname = title;

	dialog.username = mac_dialog_string_from_utf8(*username);
	if (!dialog.username)
		dialog.username = mac_dialog_setting_string(settings, FreeRDP_Username);

	dialog.password = mac_dialog_string_from_utf8(*password);

	dialog.domain = mac_dialog_string_from_utf8(*domain);
	if (!dialog.domain)
		dialog.domain = mac_dialog_setting_string(settings, FreeRDP_Domain);

	NSString *storedPassword = nil;
	if (dialog.username && ([dialog.username length] > 0))
		storedPassword = mac_keychain_copy_password(title, dialog.username, dialog.domain);

	if (storedPassword)
	{
		dialog.rememberPassword = YES;
		if (!dialog.password || ([dialog.password length] == 0))
			dialog.password = storedPassword;
	}

	free(*username);
	free(*password);
	free(*domain);
	*username = nullptr;
	*password = nullptr;
	*domain = nullptr;

	dispatch_sync(dispatch_get_main_queue(), ^{
		[dialog performSelectorOnMainThread:@selector(runModal:)
		                         withObject:[view window]
		                      waitUntilDone:TRUE];
	});
	BOOL ok = dialog.modalCode;

	if (ok)
	{
		if (dialog.rememberPassword)
			(void)mac_keychain_store_password(title, dialog.username, dialog.domain, dialog.password);
		else
			(void)mac_keychain_delete_password(title, dialog.username, dialog.domain);

		const char *submittedUsername = [dialog.username cStringUsingEncoding:NSUTF8StringEncoding];
		const size_t submittedUsernameLen =
		    [dialog.username lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		if (submittedUsername && (submittedUsernameLen > 0))
			*username = strndup(submittedUsername, submittedUsernameLen);

		if (!(*username))
			return FALSE;

		const char *submittedPassword = [dialog.password cStringUsingEncoding:NSUTF8StringEncoding];
		const size_t submittedPasswordLen =
		    [dialog.password lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		if (submittedPassword && (submittedPasswordLen > 0))
			*password = strndup(submittedPassword, submittedPasswordLen);

		if (!(*password))
			return FALSE;

		const char *submittedDomain = [dialog.domain cStringUsingEncoding:NSUTF8StringEncoding];
		const size_t submittedDomainLen =
		    [dialog.domain lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		if (submittedDomain && (submittedDomainLen > 0))
		{
			*domain = strndup(submittedDomain, submittedDomainLen);
			if (!(*domain))
				return FALSE;
		}
	}

	return ok;
}

static BOOL mac_authenticate_raw(freerdp *instance, char **username, char **password, char **domain,
                                 rdp_auth_reason reason)
{
	BOOL pinOnly = FALSE;

	WINPR_ASSERT(instance);
	WINPR_ASSERT(instance->context);
	WINPR_ASSERT(instance->context->settings);

	const rdpSettings *settings = instance->context->settings;
	mfContext *mfc = (mfContext *)instance->context;
	MRDPView *view = (MRDPView *)mfc->view;
	NSString *title = nullptr;

	switch (reason)
	{
		case AUTH_SMARTCARD_PIN:
			pinOnly = TRUE;
			title = [NSString
			    stringWithFormat:@"%@:%u",
			                     [NSString stringWithCString:freerdp_settings_get_string(
			                                                     settings, FreeRDP_ServerHostname)
			                                        encoding:NSUTF8StringEncoding],
			                     freerdp_settings_get_uint32(settings, FreeRDP_ServerPort)];
			break;
		case AUTH_TLS:
		case AUTH_RDP:
		case AUTH_NLA:
			title = [NSString
			    stringWithFormat:@"%@:%u",
			                     [NSString stringWithCString:freerdp_settings_get_string(
			                                                     settings, FreeRDP_ServerHostname)
			                                        encoding:NSUTF8StringEncoding],
			                     freerdp_settings_get_uint32(settings, FreeRDP_ServerPort)];
			break;
		case GW_AUTH_HTTP:
		case GW_AUTH_RDG:
		case GW_AUTH_RPC:
			title = [NSString
			    stringWithFormat:@"%@:%u",
			                     [NSString stringWithCString:freerdp_settings_get_string(
			                                                     settings, FreeRDP_GatewayHostname)
			                                        encoding:NSUTF8StringEncoding],
			                     freerdp_settings_get_uint32(settings, FreeRDP_GatewayPort)];
			break;
		default:
			return FALSE;
	}

	if (!username || !password || !domain)
		return FALSE;

	if (!*username && !pinOnly)
	{
		if (!mac_show_auth_dialog(view, title, username, password, domain))
			goto fail;
	}
	else if (!*domain && !pinOnly)
	{
		if (!mac_show_auth_dialog(view, title, username, password, domain))
			goto fail;
	}
	else if (!*password)
	{
		if (!mac_show_auth_dialog(view, title, username, password, domain))
			goto fail;
	}

	return TRUE;
fail:
	free(*username);
	free(*domain);
	free(*password);
	*username = nullptr;
	*domain = nullptr;
	*password = nullptr;
	return FALSE;
}

BOOL mac_authenticate_ex(freerdp *instance, char **username, char **password, char **domain,
                         rdp_auth_reason reason)
{
	WINPR_ASSERT(instance);
	WINPR_ASSERT(username);
	WINPR_ASSERT(password);
	WINPR_ASSERT(domain);

	NSString *title;
	switch (reason)
	{
		case AUTH_NLA:
			break;

		case AUTH_TLS:
		case AUTH_RDP:
		case AUTH_SMARTCARD_PIN: /* in this case password is pin code */
			if ((*username) && (*password))
				return TRUE;
			break;
		case GW_AUTH_HTTP:
		case GW_AUTH_RDG:
		case GW_AUTH_RPC:
			break;
		default:
			return FALSE;
	}

	return mac_authenticate_raw(instance, username, password, domain, reason);
}

DWORD mac_verify_certificate_ex(freerdp *instance, const char *host, UINT16 port,
                                const char *common_name, const char *subject, const char *issuer,
                                const char *fingerprint, DWORD flags)
{
	mfContext *mfc = (mfContext *)instance->context;
	MRDPView *view = (MRDPView *)mfc->view;
	CertificateDialog *dialog = [CertificateDialog new];
	const char *type = "RDP-Server";
	char hostname[8192] = WINPR_C_ARRAY_INIT;

	if (flags & VERIFY_CERT_FLAG_GATEWAY)
		type = "RDP-Gateway";

	if (flags & VERIFY_CERT_FLAG_REDIRECT)
		type = "RDP-Redirect";

	sprintf_s(hostname, sizeof(hostname), "%s %s:%" PRIu16, type, host, port);
	dialog.serverHostname = [NSString stringWithCString:hostname encoding:NSUTF8StringEncoding];
	dialog.commonName = [NSString stringWithCString:common_name encoding:NSUTF8StringEncoding];
	dialog.subject = [NSString stringWithCString:subject encoding:NSUTF8StringEncoding];
	dialog.issuer = [NSString stringWithCString:issuer encoding:NSUTF8StringEncoding];
	dialog.fingerprint = [NSString stringWithCString:fingerprint encoding:NSUTF8StringEncoding];

	if (flags & VERIFY_CERT_FLAG_MISMATCH)
		dialog.hostMismatch = TRUE;

	if (flags & VERIFY_CERT_FLAG_CHANGED)
		dialog.changed = TRUE;

	[dialog performSelectorOnMainThread:@selector(runModal:)
	                         withObject:[view window]
	                      waitUntilDone:TRUE];
	return dialog.result;
}

DWORD mac_verify_changed_certificate_ex(freerdp *instance, const char *host, UINT16 port,
                                        const char *common_name, const char *subject,
                                        const char *issuer, const char *fingerprint,
                                        const char *old_subject, const char *old_issuer,
                                        const char *old_fingerprint, DWORD flags)
{
	mfContext *mfc = (mfContext *)instance->context;
	MRDPView *view = (MRDPView *)mfc->view;
	CertificateDialog *dialog = [CertificateDialog new];
	const char *type = "RDP-Server";
	char hostname[8192];

	if (flags & VERIFY_CERT_FLAG_GATEWAY)
		type = "RDP-Gateway";

	if (flags & VERIFY_CERT_FLAG_REDIRECT)
		type = "RDP-Redirect";

	sprintf_s(hostname, sizeof(hostname), "%s %s:%" PRIu16, type, host, port);
	dialog.serverHostname = [NSString stringWithCString:hostname encoding:NSUTF8StringEncoding];
	dialog.commonName = [NSString stringWithCString:common_name encoding:NSUTF8StringEncoding];
	dialog.subject = [NSString stringWithCString:subject encoding:NSUTF8StringEncoding];
	dialog.issuer = [NSString stringWithCString:issuer encoding:NSUTF8StringEncoding];
	dialog.fingerprint = [NSString stringWithCString:fingerprint encoding:NSUTF8StringEncoding];

	if (flags & VERIFY_CERT_FLAG_MISMATCH)
		dialog.hostMismatch = TRUE;

	if (flags & VERIFY_CERT_FLAG_CHANGED)
		dialog.changed = TRUE;

	[dialog performSelectorOnMainThread:@selector(runModal:)
	                         withObject:[view window]
	                      waitUntilDone:TRUE];
	return dialog.result;
}

int mac_logon_error_info(freerdp *instance, UINT32 data, UINT32 type)
{
	const char *str_data = freerdp_get_logon_error_info_data(data);
	const char *str_type = freerdp_get_logon_error_info_type(type);
	// TODO: Error message dialog
	WLog_INFO(TAG, "Logon Error Info %s [%s]", str_data, str_type);
	return 1;
}

BOOL mf_Pointer_New(rdpContext *context, rdpPointer *pointer)
{
	rdpGdi *gdi;
	NSRect rect;
	NSImage *image;
	NSPoint hotSpot;
	NSCursor *cursor;
	BYTE *cursor_data;
	NSMutableArray *ma;
	NSBitmapImageRep *bmiRep;
	MRDPCursor *mrdpCursor = [[MRDPCursor alloc] init];
	mfContext *mfc = (mfContext *)context;
	MRDPView *view;
	UINT32 format;

	if (!mfc || !context || !pointer)
		return FALSE;

	view = (MRDPView *)mfc->view;
	gdi = context->gdi;

	if (!gdi || !view)
		return FALSE;

	rect.size.width = pointer->width;
	rect.size.height = pointer->height;
	rect.origin.x = pointer->xPos;
	rect.origin.y = pointer->yPos;
	cursor_data = (BYTE *)malloc(rect.size.width * rect.size.height * 4);

	if (!cursor_data)
		return FALSE;

	mrdpCursor->cursor_data = cursor_data;
	format = PIXEL_FORMAT_RGBA32;

	if (!freerdp_image_copy_from_pointer_data(cursor_data, format, 0, 0, 0, pointer->width,
	                                          pointer->height, pointer->xorMaskData,
	                                          pointer->lengthXorMask, pointer->andMaskData,
	                                          pointer->lengthAndMask, pointer->xorBpp, nullptr))
	{
		free(cursor_data);
		mrdpCursor->cursor_data = nullptr;
		return FALSE;
	}

	/* store cursor bitmap image in representation - required by NSImage */
	bmiRep = [[NSBitmapImageRep alloc]
	    initWithBitmapDataPlanes:(unsigned char **)&cursor_data
	                  pixelsWide:rect.size.width
	                  pixelsHigh:rect.size.height
	               bitsPerSample:8
	             samplesPerPixel:4
	                    hasAlpha:YES
	                    isPlanar:NO
	              colorSpaceName:NSDeviceRGBColorSpace
	                bitmapFormat:0
	                 bytesPerRow:rect.size.width * FreeRDPGetBytesPerPixel(format)
	                bitsPerPixel:0];
	mrdpCursor->bmiRep = bmiRep;
	/* create an image using above representation */
	image = [[NSImage alloc] initWithSize:[bmiRep size]];
	[image addRepresentation:bmiRep];
	mrdpCursor->nsImage = image;
	/* need hotspot to create cursor */
	hotSpot.x = pointer->xPos;
	hotSpot.y = pointer->yPos;
	cursor = [[NSCursor alloc] initWithImage:image hotSpot:hotSpot];
	mrdpCursor->nsCursor = cursor;
	mrdpCursor->pointer = pointer;
	/* save cursor for later use in mf_Pointer_Set() */
	ma = view->cursors;
	[ma addObject:mrdpCursor];
	return TRUE;
}

void mf_Pointer_Free(rdpContext *context, rdpPointer *pointer)
{
	mfContext *mfc = (mfContext *)context;
	MRDPView *view = (MRDPView *)mfc->view;
	NSMutableArray *ma = view->cursors;

	for (MRDPCursor *cursor in ma)
	{
		if (cursor->pointer == pointer)
		{
			cursor->nsImage = nil;
			cursor->nsCursor = nil;
			cursor->bmiRep = nil;
			free(cursor->cursor_data);
			[ma removeObject:cursor];
			return;
		}
	}
}

BOOL mf_Pointer_Set(rdpContext *context, rdpPointer *pointer)
{
	mfContext *mfc = (mfContext *)context;
	MRDPView *view = (MRDPView *)mfc->view;
	NSMutableArray *ma = view->cursors;

	for (MRDPCursor *cursor in ma)
	{
		if (cursor->pointer == pointer)
		{
			[view setCursor:cursor->nsCursor];
			return TRUE;
		}
	}

	NSLog(@"Cursor not found");
	return TRUE;
}

BOOL mf_Pointer_SetNull(rdpContext *context)
{
	return TRUE;
}

BOOL mf_Pointer_SetDefault(rdpContext *context)
{
	mfContext *mfc = (mfContext *)context;
	MRDPView *view = (MRDPView *)mfc->view;
	[view setCursor:[NSCursor arrowCursor]];
	return TRUE;
}

static BOOL mf_Pointer_SetPosition(rdpContext *context, UINT32 x, UINT32 y)
{
	mfContext *mfc = (mfContext *)context;

	if (!mfc)
		return FALSE;

	/* TODO: Set pointer position */
	return TRUE;
}

CGContextRef mac_create_bitmap_context(rdpContext *context)
{
	CGContextRef bitmap_context;
	rdpGdi *gdi = context->gdi;
	UINT32 bpp = FreeRDPGetBytesPerPixel(gdi->dstFormat);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	if (bpp == 2)
	{
		bitmap_context = CGBitmapContextCreate(
		    gdi->primary_buffer, gdi->width, gdi->height, 5, gdi->stride, colorSpace,
		    kCGBitmapByteOrder16Little | kCGImageAlphaNoneSkipFirst);
	}
	else
	{
		bitmap_context = CGBitmapContextCreate(
		    gdi->primary_buffer, gdi->width, gdi->height, 8, gdi->stride, colorSpace,
		    kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
	}

	CGColorSpaceRelease(colorSpace);
	return bitmap_context;
}

BOOL mac_begin_paint(rdpContext *context)
{
	rdpGdi *gdi = context->gdi;

	if (!gdi)
		return FALSE;

	gdi->primary->hdc->hwnd->invalid->null = TRUE;
	return TRUE;
}

BOOL mac_end_paint(rdpContext *context)
{
	NSRect newDrawRect;

	if ((!context) || (!context->gdi))
		return FALSE;

	mfContext *mfc = (mfContext *)context;
	MRDPView *view = (MRDPView *)mfc->view;
	WINPR_ASSERT(view);

	rdpGdi *gdi = context->gdi;

	if (!gdi)
		return FALSE;

	const int dw = freerdp_settings_get_uint32(mfc->common.context.settings, FreeRDP_DesktopWidth);
	const int dh = freerdp_settings_get_uint32(mfc->common.context.settings, FreeRDP_DesktopHeight);

	HGDI_DC hdc = gdi->primary->hdc;
	WINPR_ASSERT(hdc);
	if (!hdc->hwnd)
		return TRUE;

	HGDI_WND hwnd = hdc->hwnd;
	WINPR_ASSERT(hwnd->invalid || (hwnd->ninvalid == 0));

	if (hwnd->invalid->null)
		return TRUE;

	HGDI_RGN invalid = gdi->primary->hdc->hwnd->invalid;
	newDrawRect.origin.x = invalid->x;
	newDrawRect.origin.y = invalid->y;
	newDrawRect.size.width = invalid->w;
	newDrawRect.size.height = invalid->h;

	const BOOL smartSizing = freerdp_settings_get_bool(mfc->common.context.settings,
	                                                   FreeRDP_SmartSizing) &&
	                         (dw > 0) && (dh > 0);

	if (smartSizing)
	{
		__block NSRect displayRect = NSZeroRect;
		dispatch_sync(dispatch_get_main_queue(), ^{
			displayRect = mac_smart_sizing_display_rect(view, &mfc->common.context);
		});

		const CGFloat sx = displayRect.size.width / dw;
		const CGFloat sy = displayRect.size.height / dh;
		newDrawRect.origin.x = displayRect.origin.x + newDrawRect.origin.x * sx - 1;
		newDrawRect.origin.y =
		    displayRect.origin.y + displayRect.size.height -
		    (newDrawRect.origin.y + newDrawRect.size.height) * sy - 1;
		newDrawRect.size.width = newDrawRect.size.width * sx + 2;
		newDrawRect.size.height = newDrawRect.size.height * sy + 2;
	}
	else
	{
		newDrawRect.origin.y = newDrawRect.origin.y - 1;
		newDrawRect.size.height = newDrawRect.size.height + 1;
		newDrawRect.origin.x = newDrawRect.origin.x - 1;
		newDrawRect.size.width = newDrawRect.size.width + 1;
	}

	if (!smartSizing)
		windows_to_apple_cords(mfc->view, &newDrawRect);
	dispatch_sync(dispatch_get_main_queue(), ^{
		[view setNeedsDisplayInRect:newDrawRect];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"MRDPMultimonFramebufferDidUpdate"
		                                                    object:view];
	});
	gdi->primary->hdc->hwnd->ninvalid = 0;
	return TRUE;
}

static NSRect mac_smart_sizing_display_rect(MRDPView *view, rdpContext *context)
{
	NSRect bounds = [view bounds];
	rdpSettings *settings = context ? context->settings : NULL;

	if (!settings || !freerdp_settings_get_bool(settings, FreeRDP_SmartSizing))
		return bounds;

	const UINT32 dw = freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);
	const UINT32 dh = freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);

	if ((dw == 0) || (dh == 0) || (bounds.size.width <= 0) || (bounds.size.height <= 0))
		return bounds;

	const CGFloat sx = bounds.size.width / (CGFloat)dw;
	const CGFloat sy = bounds.size.height / (CGFloat)dh;
	const mfContext *mfc = (const mfContext *)context;
	const CGFloat scale = (mfc && mfc->smart_sizing_overscan) ? MAX(sx, sy) : MIN(sx, sy);
	NSRect displayRect = NSZeroRect;
	displayRect.size.width = dw * scale;
	displayRect.size.height = dh * scale;
	displayRect.origin.x = bounds.origin.x + (bounds.size.width - displayRect.size.width) / 2.0;
	displayRect.origin.y = bounds.origin.y + (bounds.size.height - displayRect.size.height) / 2.0;

	switch (mfc ? mfc->smart_sizing_align : MF_SMART_SIZING_ALIGN_CENTER)
	{
		case MF_SMART_SIZING_ALIGN_TOP:
			displayRect.origin.y = NSMaxY(bounds) - displayRect.size.height;
			break;
		case MF_SMART_SIZING_ALIGN_BOTTOM:
			displayRect.origin.y = NSMinY(bounds);
			break;
		case MF_SMART_SIZING_ALIGN_LEFT:
			displayRect.origin.x = NSMinX(bounds);
			break;
		case MF_SMART_SIZING_ALIGN_RIGHT:
			displayRect.origin.x = NSMaxX(bounds) - displayRect.size.width;
			break;
		default:
			break;
	}

	if (mfc && mfc->smart_sizing_overscan)
	{
		switch (mfc->smart_sizing_overscan_align)
		{
			case MF_SMART_SIZING_ALIGN_TOP:
				displayRect.origin.y = NSMinY(bounds);
				break;
			case MF_SMART_SIZING_ALIGN_BOTTOM:
				displayRect.origin.y = NSMaxY(bounds) - displayRect.size.height;
				break;
			case MF_SMART_SIZING_ALIGN_LEFT:
				displayRect.origin.x = NSMaxX(bounds) - displayRect.size.width;
				break;
			case MF_SMART_SIZING_ALIGN_RIGHT:
				displayRect.origin.x = NSMinX(bounds);
				break;
			default:
				break;
		}
	}
	return displayRect;
}

BOOL mac_desktop_resize(rdpContext *context)
{
	ResizeWindowEventArgs e;
	mfContext *mfc = (mfContext *)context;
	MRDPView *view = (MRDPView *)mfc->view;
	rdpSettings *settings = context->settings;

	if (!context->gdi)
		return TRUE;

	/**
	 * TODO: Fix resizing race condition. We should probably implement a message to be
	 * put on the update message queue to be able to properly flush pending updates,
	 * resize, and then continue with post-resizing graphical updates.
	 */
	CGContextRef old_context = view->bitmap_context;
	view->bitmap_context = nullptr;
	CGContextRelease(old_context);
	mfc->width = freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);
	mfc->height = freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);

	if (!gdi_resize(context->gdi, mfc->width, mfc->height))
		return FALSE;

	view->bitmap_context = mac_create_bitmap_context(context);

	if (!view->bitmap_context)
		return FALSE;

	mfc->client_width = mfc->width;
	mfc->client_height = mfc->height;
	[view setFrameSize:NSMakeSize(mfc->width, mfc->height)];
	EventArgsInit(&e, "mfreerdp");
	e.width = freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);
	e.height = freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);
	if (PubSub_OnResizeWindow(context->pubSub, context, &e) < 0)
		return FALSE;
	return TRUE;
}

static BOOL mac_scroll_flags_from_deltas(CGFloat dx, CGFloat dy, UINT16 *outFlags)
{
	UINT16 flags = 0;
	CGFloat units = 0.0;

	if (fabs(dy) > FLT_EPSILON)
	{
		flags = PTR_FLAGS_WHEEL;
		units = fabs(dy) * 120.0;

		if (dy < 0)
			flags |= PTR_FLAGS_WHEEL_NEGATIVE;
	}
	else if (fabs(dx) > FLT_EPSILON)
	{
		flags = PTR_FLAGS_HWHEEL;
		units = fabs(dx) * 120.0;

		if (dx > 0)
			flags |= PTR_FLAGS_WHEEL_NEGATIVE;
	}
	else
		return FALSE;

	UINT16 step = (UINT16)MIN(units, 0xFF);
	if (step == 0)
		step = 1;

	if (flags & PTR_FLAGS_WHEEL_NEGATIVE)
		step = 0x100 - step;

	if (outFlags)
		*outFlags = flags | step;
	return TRUE;
}

void input_activity_cb(freerdp *instance)
{
	int status;
	wMessage message;
	wMessageQueue *queue;
	status = 1;
	queue = freerdp_get_message_queue(instance, FREERDP_INPUT_MESSAGE_QUEUE);

	if (queue)
	{
		while (MessageQueue_Peek(queue, &message, TRUE))
		{
			status = freerdp_message_queue_process_message(instance, FREERDP_INPUT_MESSAGE_QUEUE,
			                                               &message);

			if (!status)
				break;
		}
	}
	else
	{
		WLog_ERR(TAG, "input_activity_cb: No queue!");
	}
}

/**
 * given a rect with 0,0 at the top left (windows cords)
 * convert it to a rect with 0,0 at the bottom left (apple cords)
 *
 * Note: the formula works for conversions in both directions.
 *
 */

void windows_to_apple_cords(MRDPView *view, NSRect *r)
{
	dispatch_sync(dispatch_get_main_queue(), ^{
		r->origin.y = [view frame].size.height - (r->origin.y + r->size.height);
	});
}

@end
