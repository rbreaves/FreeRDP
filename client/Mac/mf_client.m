/**
 * FreeRDP: A Remote Desktop Protocol Implementation
 * X11 Client Interface
 *
 * Copyright 2013 Marc-Andre Moreau <marcandre.moreau@gmail.com>
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

#include <freerdp/config.h>

#include "mfreerdp.h"

#include <winpr/assert.h>

#include <freerdp/constants.h>
#include <freerdp/utils/signal.h>
#include <freerdp/client/cmdline.h>

#include "MRDPView.h"

/**
 * Client Interface
 */

static BOOL mfreerdp_client_global_init(void)
{
	freerdp_handle_signals();
	return TRUE;
}

static void mfreerdp_client_global_uninit(void)
{
}

static int mfreerdp_client_start(rdpContext *context)
{
	MRDPView *view;
	mfContext *mfc = (mfContext *)context;

	if (mfc->view == nullptr)
	{
		// view not specified beforehand. Create view dynamically
		mfc->view = [[MRDPView alloc]
		    initWithFrame:NSMakeRect(
		                      0, 0,
		                      freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth),
		                      freerdp_settings_get_uint32(context->settings,
		                                                  FreeRDP_DesktopHeight))];
		mfc->view_ownership = TRUE;
	}

	view = (MRDPView *)mfc->view;
	return [view rdpStart:context];
}

static int mfreerdp_client_stop(rdpContext *context)
{
	mfContext *mfc = (mfContext *)context;

	freerdp_client_common_stop(context);

	if (mfc->view_ownership)
	{
		MRDPView *view = (MRDPView *)mfc->view;
		[view releaseResources];
		[view release];
		mfc->view = nil;
	}

	return 0;
}

static BOOL mfreerdp_client_new(freerdp *instance, rdpContext *context)
{
	mfContext *mfc;

	WINPR_ASSERT(instance);

	mfc = (mfContext *)instance->context;
	WINPR_ASSERT(mfc);

	mfc->stopEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);
	if (!mfc->stopEvent)
		return FALSE;

	mfc->chromaKeyEnabled = FALSE;
	mfc->chromaKeyColor = 0xFF00FF;
	mfc->chromaKeyTolerance = 30.0f;
	mfc->windowShadowsEnabled = FALSE;
	mfc->smart_sizing_align = MF_SMART_SIZING_ALIGN_CENTER;
	mfc->smart_sizing_overscan = FALSE;
	mfc->smart_sizing_overscan_align = MF_SMART_SIZING_ALIGN_CENTER;

	context->instance->PreConnect = mac_pre_connect;
	context->instance->PostConnect = mac_post_connect;
	context->instance->PostDisconnect = mac_post_disconnect;
	context->instance->AuthenticateEx = mac_authenticate_ex;
	context->instance->VerifyCertificateEx = mac_verify_certificate_ex;
	context->instance->VerifyChangedCertificateEx = mac_verify_changed_certificate_ex;
	context->instance->LogonErrorInfo = mac_logon_error_info;
	return TRUE;
}

static void mfreerdp_client_free(freerdp *instance, rdpContext *context)
{
	mfContext *mfc;

	if (!instance || !context)
		return;

	mfc = (mfContext *)instance->context;
	(void)CloseHandle(mfc->stopEvent);
}

static void mf_scale_mouse_coordinates(mfContext *mfc, UINT16 *px, UINT16 *py)
{
	CGFloat x = *px;
	CGFloat y = *py;
	UINT32 ww = mfc->client_width;
	UINT32 wh = mfc->client_height;
	UINT32 dw = freerdp_settings_get_uint32(mfc->common.context.settings, FreeRDP_DesktopWidth);
	UINT32 dh = freerdp_settings_get_uint32(mfc->common.context.settings, FreeRDP_DesktopHeight);
	MRDPView *view = (MRDPView *)mfc->view;

	if (freerdp_settings_get_bool(mfc->common.context.settings, FreeRDP_SmartSizing) &&
	    view && (dw > 0) && (dh > 0))
	{
		NSRect bounds = [view bounds];
		const CGFloat sx = bounds.size.width / (CGFloat)dw;
		const CGFloat sy = bounds.size.height / (CGFloat)dh;
		const CGFloat scale = mfc->smart_sizing_overscan ? MAX(sx, sy) : MIN(sx, sy);
		if (scale <= 0)
			return;

		NSRect displayRect = NSZeroRect;
		displayRect.size.width = dw * scale;
		displayRect.size.height = dh * scale;
		displayRect.origin.x = bounds.origin.x + (bounds.size.width - displayRect.size.width) / 2.0;
		displayRect.origin.y = bounds.origin.y + (bounds.size.height - displayRect.size.height) / 2.0;

		switch (mfc->smart_sizing_align)
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

		if (mfc->smart_sizing_overscan)
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

		const CGFloat top = bounds.size.height - NSMaxY(displayRect);
		x = MIN(MAX(x - displayRect.origin.x, 0), displayRect.size.width - 1);
		y = MIN(MAX(y - top, 0), displayRect.size.height - 1);
		x = x * dw / displayRect.size.width + mfc->xCurrentScroll;
		y = y * dh / displayRect.size.height + mfc->yCurrentScroll;
	}
	else
	{
		y = y + mfc->yCurrentScroll;
		x = x + mfc->xCurrentScroll;

		y -= (dh - wh);
		x -= (dw - ww);
	}

	*px = (UINT16)MIN(MAX(x, 0), UINT16_MAX);
	*py = (UINT16)MIN(MAX(y, 0), UINT16_MAX);
}

void mf_scale_mouse_event(void *context, UINT16 flags, UINT16 x, UINT16 y)
{
	mfContext *mfc = (mfContext *)context;
	MRDPView *view = (MRDPView *)mfc->view;
	// Convert to windows coordinates
	NSPoint viewPoint = [view convertPoint:NSMakePoint(x, y) fromView:nil];
	x = (UINT16)MIN(MAX(viewPoint.x, 0), UINT16_MAX);
	y = (UINT16)MIN(MAX([view bounds].size.height - viewPoint.y, 0), UINT16_MAX);

	if ((flags & (PTR_FLAGS_WHEEL | PTR_FLAGS_HWHEEL)) == 0)
		mf_scale_mouse_coordinates(mfc, &x, &y);
	freerdp_client_send_button_event(&mfc->common, FALSE, flags, x, y);
}

void mf_scale_mouse_event_ex(void *context, UINT16 flags, UINT16 x, UINT16 y)
{
	mfContext *mfc = (mfContext *)context;
	MRDPView *view = (MRDPView *)mfc->view;
	// Convert to windows coordinates
	NSPoint viewPoint = [view convertPoint:NSMakePoint(x, y) fromView:nil];
	x = (UINT16)MIN(MAX(viewPoint.x, 0), UINT16_MAX);
	y = (UINT16)MIN(MAX([view bounds].size.height - viewPoint.y, 0), UINT16_MAX);

	mf_scale_mouse_coordinates(mfc, &x, &y);
	freerdp_client_send_extended_button_event(&mfc->common, FALSE, flags, x, y);
}

void mf_press_mouse_button(void *context, int button, int x, int y, BOOL down)
{
	UINT16 flags = 0;
	UINT16 xflags = 0;

	if (down)
	{
		flags |= PTR_FLAGS_DOWN;
		xflags |= PTR_XFLAGS_DOWN;
	}

	switch (button)
	{
		case 0:
			mf_scale_mouse_event(context, flags | PTR_FLAGS_BUTTON1, x, y);
			break;

		case 1:
			mf_scale_mouse_event(context, flags | PTR_FLAGS_BUTTON2, x, y);
			break;

		case 2:
			mf_scale_mouse_event(context, flags | PTR_FLAGS_BUTTON3, x, y);
			break;

		case 3:
			mf_scale_mouse_event_ex(context, xflags | PTR_XFLAGS_BUTTON1, x, y);
			break;

		case 4:
			mf_scale_mouse_event_ex(context, xflags | PTR_XFLAGS_BUTTON2, x, y);
			break;

		default:
			break;
	}
}

int RdpClientEntry(RDP_CLIENT_ENTRY_POINTS *pEntryPoints)
{
	WINPR_ASSERT(pEntryPoints);

	pEntryPoints->Version = 1;
	pEntryPoints->Size = sizeof(RDP_CLIENT_ENTRY_POINTS_V1);
	pEntryPoints->GlobalInit = mfreerdp_client_global_init;
	pEntryPoints->GlobalUninit = mfreerdp_client_global_uninit;
	pEntryPoints->ContextSize = sizeof(mfContext);
	pEntryPoints->ClientNew = mfreerdp_client_new;
	pEntryPoints->ClientFree = mfreerdp_client_free;
	pEntryPoints->ClientStart = mfreerdp_client_start;
	pEntryPoints->ClientStop = mfreerdp_client_stop;
	return 0;
}
