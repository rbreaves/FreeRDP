#ifndef FREERDP_CLIENT_MAC_FREERDP_H
#define FREERDP_CLIENT_MAC_FREERDP_H

#include <freerdp/freerdp.h>
#include <freerdp/client/file.h>
#include <freerdp/api.h>
#include <freerdp/freerdp.h>
#include <stddef.h>

#include <freerdp/gdi/gdi.h>
#include <freerdp/gdi/dc.h>
#include <freerdp/gdi/gfx.h>
#include <freerdp/gdi/region.h>
#include <freerdp/channels/channels.h>

#include <freerdp/client/channels.h>
#include <freerdp/client/disp.h>
#include <freerdp/client/rdpei.h>
#include <freerdp/client/rdpgfx.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/client/encomsp.h>

#include <winpr/crt.h>
#include <winpr/synch.h>
#include <winpr/thread.h>
#include <winpr/clipboard.h>

#include "Keyboard.h"
#include <CoreGraphics/CoreGraphics.h>

typedef enum
{
	MF_SMART_SIZING_ALIGN_CENTER = 0,
	MF_SMART_SIZING_ALIGN_TOP,
	MF_SMART_SIZING_ALIGN_BOTTOM,
	MF_SMART_SIZING_ALIGN_LEFT,
	MF_SMART_SIZING_ALIGN_RIGHT
} MF_SMART_SIZING_ALIGN;

typedef enum
{
	MF_MODIFIER_KEYSWAP_NONE = 0,
	MF_MODIFIER_KEYSWAP_APPLE_TO_PC,
	MF_MODIFIER_KEYSWAP_PC_TO_APPLE
} MF_MODIFIER_KEYSWAP_MODE;

typedef struct
{
	UINT32 streamId;
	UINT32 listIndex;
	UINT64 size;
	UINT64 received;
	char* localPath;
	BOOL complete;
} mfClipboardRemoteFile;

typedef struct
{
	rdpClientContext common;

	void* view;
	BOOL view_ownership;

	int width;
	int height;
	int offset_x;
	int offset_y;
	int fs_toggle;
	int fullscreen;
	int percentscreen;
	char window_title[64];
	int client_x;
	int client_y;
	int client_width;
	int client_height;
	int fullscreen_mode;
	MF_SMART_SIZING_ALIGN smart_sizing_align;
	BOOL smart_sizing_overscan;
	MF_SMART_SIZING_ALIGN smart_sizing_overscan_align;

	HANDLE stopEvent;
	HANDLE keyboardThread;
	enum APPLE_KEYBOARD_TYPE appleKeyboardType;

	DWORD mainThreadId;
	DWORD keyboardThreadId;

	BOOL clipboardSync;
	wClipboard* clipboard;
	UINT32 numServerFormats;
	UINT32 requestedFormatId;
	HANDLE clipboardRequestEvent;
	CLIPRDR_FORMAT* serverFormats;
	mfClipboardRemoteFile* remoteFiles;
	UINT32 remoteFileCount;
	UINT32 remoteFileStreamIdNext;
	char* remoteFilePasteDir;
	CliprdrClientContext* cliprdr;
	DispClientContext* disp;
	UINT32 clipboardCapabilities;

	rdpFile* connectionRdpFile;

	// Keep track of window size and position, disable when in fullscreen mode.
	BOOL disablewindowtracking;

	// These variables are required for horizontal scrolling.
	BOOL updating_scrollbars;
	BOOL xScrollVisible;
	int xMinScroll;     // minimum horizontal scroll value
	int xCurrentScroll; // current horizontal scroll value
	int xMaxScroll;     // maximum horizontal scroll value

	// These variables are required for vertical scrolling.
	BOOL yScrollVisible;
	int yMinScroll;     // minimum vertical scroll value
	int yCurrentScroll; // current vertical scroll value
	int yMaxScroll;     // maximum vertical scroll value

	CGEventFlags kbdFlags;

	BOOL chromaKeyEnabled;
	BOOL chromaKeyFeatheringEnabled;
	uint32_t chromaKeyColor;
	uint32_t additionalTransparencyColors[16];
	UINT32 additionalTransparencyLevels[16];
	UINT32 additionalTransparencyTolerances[16];
	BOOL additionalTransparencyBlur[16];
	size_t additionalTransparencyColorCount;
	float chromaKeyTolerance;

	BOOL windowShadowsEnabled;
	UINT32 windowDragTitlebarHeight;
	MF_MODIFIER_KEYSWAP_MODE modifierKeyswapMode;
	char modifierKeyswapFilter[512];

	BOOL spacerEnabled;
	UINT32 spacerPosition; // 0=top, 1=bottom, 2=left, 3=right
	UINT32 spacerSize;     // width for left/right, height for top/bottom (in pixels)
	BOOL taskbarHide;
	UINT32 taskbarHideHeight;
	UINT32 taskbarHidePosition; // 0=top, 1=bottom, 2=left, 3=right (default: 1=bottom)
	int taskbarHideZOrder;
} mfContext;

#endif /* FREERDP_CLIENT_MAC_FREERDP_H */
