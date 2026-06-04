//
//  AppDelegate.m
//  MacClient2
//
//  Created by Benoît et Kathy on 2013-05-08.
//
//

#import "AppDelegate.h"
#import <ApplicationServices/ApplicationServices.h>
#import <mfreerdp.h>
#import <mf_client.h>
#import <MRDPView.h>

#import <winpr/assert.h>
#import <winpr/string.h>
#import <freerdp/client/cmdline.h>
#import <freerdp/client/disp.h>
#import <freerdp/version.h>

#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <unistd.h>

static AppDelegate *_singleDelegate = nil;
void AppDelegate_ConnectionResultEventHandler(void *context, const ConnectionResultEventArgs *e);
void AppDelegate_ErrorInfoEventHandler(void *ctx, const ErrorInfoEventArgs *e);
void AppDelegate_EmbedWindowEventHandler(void *context, const EmbedWindowEventArgs *e);
void AppDelegate_ResizeWindowEventHandler(void *context, const ResizeWindowEventArgs *e);
void mac_set_view_size(rdpContext *context, MRDPView *view);
static void mac_position_window_top_left(NSWindow *window);
static BOOL mac_screen_is_selected_for_settings(rdpSettings *settings, UINT32 screenIndex);
static BOOL mac_multimon_content_rect(rdpSettings *settings, NSRect *rect);
static BOOL mac_multimon_enabled(rdpSettings *settings);
static NSArray *mac_multimon_slices(rdpSettings *settings, mfContext *mfc);
static NSArray *mac_taskbar_single_monitor_slices(rdpSettings *settings, mfContext *mfc,
                                                  NSWindow *window);
static BOOL mac_taskbar_hide_enabled(mfContext *mfc);
static BOOL mac_taskbar_uses_extended_canvas(mfContext *mfc);
static CGFloat mac_taskbar_hide_size(mfContext *mfc, NSRect source);
static NSRect mac_remote_frame_with_taskbar(NSRect frame, mfContext *mfc);
static NSRect mac_taskbar_visible_frame(NSRect frame, UINT32 position, CGFloat size);
static NSRect mac_taskbar_visible_source(NSRect source, UINT32 position, CGFloat size);
static NSRect mac_taskbar_full_frame(NSRect frame, UINT32 position, CGFloat size);
static BOOL mac_taskbar_mouse_should_reveal(NSPoint mouse, NSRect taskbarFrame);
static NSRect mac_safe_multimon_window_frame(NSScreen *screen, BOOL decorated);
static NSRect mac_constrain_window_frame_to_screen(NSRect frame, NSScreen *screen, BOOL decorated);
static void mac_maximize_window_minus_menubar(rdpContext *context, NSWindow *window, MRDPView *view);
static void mac_fit_view_to_window_content(rdpContext *context, MRDPView *view);
static BOOL mac_is_point_on_left_screen_edge(NSPoint point);
static NSURL *mac_find_resource_url(NSString *resourceName, NSString *extension);
static NSImage *mac_load_svg_image(NSString *resourceName, CGFloat pointSize, BOOL templateImage);
static NSImage *mac_render_image_for_size(NSImage *source, CGFloat pointSize, BOOL templateImage);
static NSImage *mac_create_freerdp_vector_icon(CGFloat pointSize, BOOL monochrome, BOOL templateImage);
static BOOL mac_parse_smart_sizing_alignment(const char *value, MF_SMART_SIZING_ALIGN *alignment);
static BOOL mac_parse_smart_sizing_options(const char *value, mfContext *mfc);
static BOOL mac_parse_taskbar_hide_options(const char *value, mfContext *mfc);
static NSInteger mac_screen_index_for_screen(NSScreen *screen);
static NSScreen *mac_screen_for_index(NSInteger screenIndex);
static NSString *mac_screen_identifier(NSScreen *screen);
static NSScreen *mac_screen_for_identifier(NSString *identifier);
static NSScreen *mac_preferred_screen(NSWindow *window);
static NSString *mac_display_title(NSScreen *screen, NSInteger screenIndex);
static DISPLAY_CONTROL_MONITOR_LAYOUT mac_display_layout_for_screen(NSScreen *screen,
	                                                               BOOL useVisibleFrame,
	                                                               mfContext *mfc);
static CGRect mac_ax_rect_for_screen_rect(NSScreen *screen, NSRect rect);
static CGRect mac_spacer_rect_for_screen(NSScreen *screen, UINT32 position, UINT32 size);
static CGRect mac_available_rect_for_spacer(NSScreen *screen, UINT32 position, UINT32 size);
static BOOL mac_ax_get_window_frame(AXUIElementRef windowElement, CGRect *frame);
static void mac_ax_set_window_frame(AXUIElementRef windowElement, CGRect frame);

static NSString *const MRDPPreferredScreenIdentifierKey = @"MRDPPreferredScreenIdentifier";
static NSString *const MRDPChromaKeyEnabledKey = @"MRDPChromaKeyEnabled";
static NSString *const MRDPChromaKeyFeatheringEnabledKey = @"MRDPChromaKeyFeatheringEnabled";
static NSString *const MRDPChromaKeyColorKey = @"MRDPChromaKeyColor";
static NSString *const MRDPChromaKeyToleranceKey = @"MRDPChromaKeyTolerance";
static NSString *const MRDPAdditionalTransparencyColorsKey = @"MRDPAdditionalTransparencyColors";
static NSString *const MRDPAdditionalTransparencyLevelsKey = @"MRDPAdditionalTransparencyLevels";
static NSString *const MRDPAdditionalTransparencyTolerancesKey = @"MRDPAdditionalTransparencyTolerances";
static NSString *const MRDPAdditionalTransparencyBlurKey = @"MRDPAdditionalTransparencyBlur";
static NSString *const MRDPWindowShadowsEnabledKey = @"MRDPWindowShadowsEnabled";
static NSString *const MRDPWindowDragTitlebarHeightKey = @"MRDPWindowDragTitlebarHeight";
static NSString *const MRDPModifierKeyswapModeKey = @"MRDPModifierKeyswapMode";
static NSString *const MRDPModifierKeyswapFilterKey = @"MRDPModifierKeyswapFilter";
static NSString *const MRDPStatusSessionDidUpdateNotification = @"org.freerdp.mac.statusSessionDidUpdate";
static NSString *const MRDPStatusSessionWillTerminateNotification = @"org.freerdp.mac.statusSessionWillTerminate";
static NSString *const MRDPStatusCommandNotification = @"org.freerdp.mac.statusCommand";

static BOOL mac_parse_hex_color_text(NSString *text, uint32_t *color);
static BOOL mac_parse_chroma_key_text(NSString *text, uint32_t *color, float *tolerance);
static BOOL mac_parse_hex_alpha_list(NSString *text, uint32_t *colors, UINT32 *transparencies,
                                     UINT32 *tolerances, BOOL *blur, size_t capacity,
                                     size_t *count);
static NSString *mac_hex_alpha_list_string(const mfContext *mfc);
static NSArray *mac_hex_color_number_array(const mfContext *mfc);
static NSArray *mac_transparency_number_array(const mfContext *mfc);
static NSArray *mac_tolerance_number_array(const mfContext *mfc);
static NSArray *mac_blur_number_array(const mfContext *mfc);
static void mac_set_additional_transparency_colors_from_arrays(mfContext *mfc, NSArray *colors,
                                                               NSArray *transparencies,
                                                               NSArray *tolerances, NSArray *blur);
static NSString *mac_modifier_keyswap_filter_string(const mfContext *mfc);
static void mac_set_modifier_keyswap_filter(mfContext *mfc, NSString *filter);

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

@interface MRDPMonitorSliceView : NSView
{
	MRDPView *primaryView;
	NSRect sourceRect;
	id mousePassThroughMonitor;
	BOOL mousePassThroughArmed;
}

- (id)initWithPrimaryView:(MRDPView *)view sourceRect:(NSRect)rect;
- (void)setSourceRect:(NSRect)rect;
- (NSPoint)remotePointForScreenPoint:(NSPoint)screenPoint valid:(BOOL *)valid;
- (BOOL)isRemotePointTransparent:(NSPoint)remotePoint;

@end

@implementation MRDPMonitorSliceView

- (id)initWithPrimaryView:(MRDPView *)view sourceRect:(NSRect)rect
{
	self = [super initWithFrame:NSMakeRect(0, 0, rect.size.width, rect.size.height)];
	if (!self)
		return nil;

	primaryView = view;
	sourceRect = rect;
	[self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)setSourceRect:(NSRect)rect
{
	sourceRect = rect;
	[self setFrameSize:rect.size];
	[self setNeedsDisplay:YES];
}

- (void)dealloc
{
	if (mousePassThroughMonitor)
		[NSEvent removeMonitor:mousePassThroughMonitor];
	[super dealloc];
}

- (NSPoint)remotePointForEvent:(NSEvent *)event
{
	NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	NSRect bounds = [self bounds];
	const CGFloat sx = (NSWidth(bounds) > 0) ? sourceRect.size.width / NSWidth(bounds) : 1.0;
	const CGFloat sy = (NSHeight(bounds) > 0) ? sourceRect.size.height / NSHeight(bounds) : 1.0;
	point.x = sourceRect.origin.x + point.x * sx;
	point.y = sourceRect.origin.y + point.y * sy;
	point.x = MIN(MAX(point.x, 0), UINT16_MAX);
	point.y = MIN(MAX(point.y, 0), UINT16_MAX);
	return point;
}

- (NSPoint)remotePointForScreenPoint:(NSPoint)screenPoint valid:(BOOL *)valid
{
	NSWindow *window = [self window];
	if (!window || !NSPointInRect(screenPoint, [window frame]))
	{
		if (valid)
			*valid = NO;
		return NSZeroPoint;
	}

	NSPoint windowPoint = [window convertPointFromScreen:screenPoint];
	NSPoint point = [self convertPoint:windowPoint fromView:nil];
	NSRect bounds = [self bounds];
	if (!NSPointInRect(point, bounds))
	{
		if (valid)
			*valid = NO;
		return NSZeroPoint;
	}

	const CGFloat sx = (NSWidth(bounds) > 0) ? sourceRect.size.width / NSWidth(bounds) : 1.0;
	const CGFloat sy = (NSHeight(bounds) > 0) ? sourceRect.size.height / NSHeight(bounds) : 1.0;
	if (valid)
		*valid = YES;
	return NSMakePoint(sourceRect.origin.x + point.x * sx, sourceRect.origin.y + point.y * sy);
}

- (BOOL)isRemotePointTransparent:(NSPoint)remotePoint
{
	return primaryView &&
	       [primaryView isRemotePixelTransparentAtX:(int)floor(remotePoint.x)
	                                              y:(int)floor(remotePoint.y)];
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

	CGEventSetIntegerValueField(forwardedEvent, kCGEventSourceUserData, 0x4D52445050544852LL);
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
	BOOL valid = NO;
	NSPoint remotePoint = [self remotePointForScreenPoint:screenPoint valid:&valid];
	BOOL shouldIgnore = valid && [self isRemotePointTransparent:remotePoint];

	if (mousePassThroughArmed == shouldIgnore)
		return;

	mousePassThroughArmed = shouldIgnore;
	[window setIgnoresMouseEvents:shouldIgnore];
}

- (BOOL)shouldPassMouseEventThrough:(NSEvent *)event
{
	CGEventRef cgEvent = [event CGEvent];
	if (cgEvent &&
	    (CGEventGetIntegerValueField(cgEvent, kCGEventSourceUserData) == 0x4D52445050544852LL))
		return NO;

	NSPoint remotePoint = [self remotePointForEvent:event];
	BOOL transparent = [self isRemotePointTransparent:remotePoint];
	[self syncMousePassThroughStateForScreenPoint:[NSEvent mouseLocation]];
	return transparent;
}

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];

	if (mousePassThroughMonitor)
	{
		[NSEvent removeMonitor:mousePassThroughMonitor];
		mousePassThroughMonitor = nil;
	}

	if (![self window])
		return;

	mousePassThroughMonitor =
	    [NSEvent addGlobalMonitorForEventsMatchingMask:(NSEventMaskMouseMoved |
	                                                    NSEventMaskLeftMouseDragged |
	                                                    NSEventMaskRightMouseDragged |
	                                                    NSEventMaskOtherMouseDragged |
	                                                    NSEventMaskLeftMouseDown |
	                                                    NSEventMaskRightMouseDown |
	                                                    NSEventMaskOtherMouseDown)
	                                          handler:^(NSEvent *event) {
		                                          (void)event;
		                                          dispatch_async(dispatch_get_main_queue(), ^{
			                                          [self syncMousePassThroughStateForScreenPoint:
			                                                    [NSEvent mouseLocation]];
		                                          });
	                                          }];
}

- (void)sendMoveForEvent:(NSEvent *)event
{
	if (!primaryView || ![primaryView is_connected])
		return;

	NSPoint point = [self remotePointForEvent:event];
	[primaryView sendRemoteMouseEventWithFlags:PTR_FLAGS_MOVE
	                                         x:(UINT16)point.x
	                                         y:(UINT16)point.y];
}

- (void)sendButton:(int)button event:(NSEvent *)event down:(BOOL)down
{
	if (!primaryView || ![primaryView is_connected])
		return;

	NSPoint point = [self remotePointForEvent:event];
	[primaryView sendRemoteMouseButton:button x:(UINT16)point.x y:(UINT16)point.y down:down];
}

- (void)drawRect:(NSRect)dirtyRect
{
	(void)dirtyRect;

	CGImageRef image = primaryView ? [primaryView newFramebufferImage] : NULL;
	if (!image)
	{
		[[NSColor clearColor] set];
		NSRectFill([self bounds]);
		return;
	}

	CGImageRef slice = CGImageCreateWithImageInRect(image, CGRectMake(sourceRect.origin.x,
	                                                                  sourceRect.origin.y,
	                                                                  sourceRect.size.width,
	                                                                  sourceRect.size.height));
	CGImageRelease(image);
	if (!slice)
		return;

	CGContextRef cgContext = [[NSGraphicsContext currentContext] CGContext];
	NSRect bounds = [self bounds];
	CGContextSaveGState(cgContext);
	CGContextClearRect(cgContext, bounds);
	CGContextTranslateCTM(cgContext, 0, NSHeight(bounds));
	CGContextScaleCTM(cgContext, 1.0, -1.0);
	CGContextDrawImage(cgContext, CGRectMake(0, 0, NSWidth(bounds), NSHeight(bounds)), slice);
	CGContextRestoreGState(cgContext);
	CGImageRelease(slice);
}

- (void)mouseMoved:(NSEvent *)event
{
	[self syncMousePassThroughStateForScreenPoint:[NSEvent mouseLocation]];
	[self sendMoveForEvent:event];
}

- (void)mouseDragged:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendMoveForEvent:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendMoveForEvent:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendMoveForEvent:event];
}

- (void)mouseDown:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendButton:0 event:event down:YES];
}

- (void)mouseUp:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendButton:0 event:event down:NO];
}

- (void)rightMouseDown:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendButton:1 event:event down:YES];
}

- (void)rightMouseUp:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendButton:1 event:event down:NO];
}

- (void)otherMouseDown:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendButton:(int)[event buttonNumber] event:event down:YES];
}

- (void)otherMouseUp:(NSEvent *)event
{
	if ([self shouldPassMouseEventThrough:event])
	{
		[self passMouseEventThrough:event];
		return;
	}
	[self sendButton:(int)[event buttonNumber] event:event down:NO];
}

- (void)scrollWheel:(NSEvent *)event
{
	NSPoint point = [self remotePointForEvent:event];
	const CGFloat dx = [event hasPreciseScrollingDeltas] ? [event scrollingDeltaX] : [event deltaX];
	const CGFloat dy = [event hasPreciseScrollingDeltas] ? [event scrollingDeltaY] : [event deltaY];
	[primaryView sendRemoteScrollWithDeltaX:dx
	                                 deltaY:dy
	                                      x:(UINT16)point.x
	                                      y:(UINT16)point.y];
}

- (void)keyDown:(NSEvent *)event
{
	[primaryView keyDown:event];
}

- (void)keyUp:(NSEvent *)event
{
	[primaryView keyUp:event];
}

- (void)flagsChanged:(NSEvent *)event
{
	[primaryView flagsChanged:event];
}

@end

static BOOL mac_parse_hex_color_text(NSString *text, uint32_t *color)
{
	NSString *colorText = [text
	    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([colorText hasPrefix:@"#"])
		colorText = [colorText substringFromIndex:1];
	if ([colorText hasPrefix:@"0x"] || [colorText hasPrefix:@"0X"])
		colorText = [colorText substringFromIndex:2];

	unsigned long long colorVal = 0;
	NSScanner *scanner = [NSScanner scannerWithString:colorText];
	BOOL valid = ([colorText length] == 6) && [scanner scanHexLongLong:&colorVal] &&
	             [scanner isAtEnd] && (colorVal <= 0xFFFFFF);
	if (valid && color)
		*color = (uint32_t)(colorVal & 0xFFFFFF);

	return valid;
}

static BOOL mac_parse_chroma_key_text(NSString *text, uint32_t *color, float *tolerance)
{
	NSString *trimmed =
	    [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSArray *parts = [trimmed componentsSeparatedByString:@":"];
	if ([parts count] < 1 || [parts count] > 2)
		return FALSE;

	NSString *colorText = [[parts objectAtIndex:0]
	    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!mac_parse_hex_color_text(colorText, color))
		return FALSE;

	if ([parts count] == 1)
		return TRUE;

	NSString *toleranceText = [[parts objectAtIndex:1]
	    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	float parsedTolerance = 0;
	NSScanner *scanner = [NSScanner scannerWithString:toleranceText];
	if (![scanner scanFloat:&parsedTolerance] || ![scanner isAtEnd] || parsedTolerance < 0 ||
	    parsedTolerance > 255)
	{
		return FALSE;
	}

	if (tolerance)
		*tolerance = parsedTolerance;

	return TRUE;
}

static BOOL mac_parse_hex_alpha_list(NSString *text, uint32_t *colors, UINT32 *transparencies,
                                     UINT32 *tolerances, BOOL *blur, size_t capacity,
                                     size_t *count)
{
	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",;\r\n"];
	NSArray *parts = [text componentsSeparatedByCharactersInSet:separators];
	size_t parsedCount = 0;

	for (NSString *part in parts)
	{
		NSString *trimmed =
		    [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([trimmed length] == 0)
			continue;
		if (parsedCount >= capacity)
			return FALSE;

		NSRange equalsRange = [trimmed rangeOfString:@"="];
		if (equalsRange.location == NSNotFound)
			return FALSE;

		NSString *colorText = [trimmed substringToIndex:equalsRange.location];
		NSString *valuesText = [trimmed substringFromIndex:equalsRange.location + 1];
		NSArray *valueParts = [valuesText componentsSeparatedByString:@":"];
		if ([valueParts count] < 1 || [valueParts count] > 3)
			return FALSE;

		NSString *transparencyText = [valueParts objectAtIndex:0];
		NSString *toleranceText = @"0";
		BOOL blurEnabled = FALSE;

		for (NSUInteger i = 1; i < [valueParts count]; i++)
		{
			NSString *valueText = [[valueParts objectAtIndex:i]
			    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([valueText caseInsensitiveCompare:@"blur"] == NSOrderedSame)
				blurEnabled = TRUE;
			else
				toleranceText = valueText;
		}

		colorText = [colorText
		    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		transparencyText = [transparencyText
		    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		toleranceText = [toleranceText
		    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

		NSScanner *transparencyScanner = [NSScanner scannerWithString:transparencyText];
		NSScanner *toleranceScanner = [NSScanner scannerWithString:toleranceText];
		int scannedTransparency = 0;
		int scannedTolerance = 0;
		if (!mac_parse_hex_color_text(colorText, &colors[parsedCount]) ||
		    ![transparencyScanner scanInt:&scannedTransparency] ||
		    ![transparencyScanner isAtEnd] || scannedTransparency < 0 ||
		    scannedTransparency > 100 || ![toleranceScanner scanInt:&scannedTolerance] ||
		    ![toleranceScanner isAtEnd] || scannedTolerance < 0 || scannedTolerance > 255)
		{
			return FALSE;
		}
		transparencies[parsedCount] = (UINT32)scannedTransparency;
		tolerances[parsedCount] = (UINT32)scannedTolerance;
		blur[parsedCount] = blurEnabled;
		parsedCount++;
	}

	if (count)
		*count = parsedCount;

	return TRUE;
}

static NSString *mac_hex_alpha_list_string(const mfContext *mfc)
{
	NSMutableArray *parts = [NSMutableArray array];
	size_t count = mfc ? MIN(mfc->additionalTransparencyColorCount,
	                         sizeof(mfc->additionalTransparencyColors) /
	                             sizeof(mfc->additionalTransparencyColors[0]))
	                   : 0;

	for (size_t i = 0; i < count; i++)
	{
		NSString *entry = [NSString
		    stringWithFormat:@"#%06X=%u:%u",
		                     (unsigned int)(mfc->additionalTransparencyColors[i] & 0xFFFFFF),
		                     (unsigned int)MIN(mfc->additionalTransparencyLevels[i], 100),
		                     (unsigned int)MIN(mfc->additionalTransparencyTolerances[i], 255)];
		if (mfc->additionalTransparencyBlur[i])
			entry = [entry stringByAppendingString:@":blur"];
		[parts addObject:entry];
	}

	return [parts componentsJoinedByString:@", "];
}

static NSArray *mac_hex_color_number_array(const mfContext *mfc)
{
	NSMutableArray *numbers = [NSMutableArray array];
	size_t count = mfc ? MIN(mfc->additionalTransparencyColorCount,
	                         sizeof(mfc->additionalTransparencyColors) /
	                             sizeof(mfc->additionalTransparencyColors[0]))
	                   : 0;

	for (size_t i = 0; i < count; i++)
		[numbers addObject:@((NSInteger)(mfc->additionalTransparencyColors[i] & 0xFFFFFF))];

	return numbers;
}

static NSArray *mac_transparency_number_array(const mfContext *mfc)
{
	NSMutableArray *numbers = [NSMutableArray array];
	size_t count = mfc ? MIN(mfc->additionalTransparencyColorCount,
	                         sizeof(mfc->additionalTransparencyColors) /
	                             sizeof(mfc->additionalTransparencyColors[0]))
	                   : 0;

	for (size_t i = 0; i < count; i++)
		[numbers addObject:@((NSInteger)MIN(mfc->additionalTransparencyLevels[i], 100))];

	return numbers;
}

static NSArray *mac_tolerance_number_array(const mfContext *mfc)
{
	NSMutableArray *numbers = [NSMutableArray array];
	size_t count = mfc ? MIN(mfc->additionalTransparencyColorCount,
	                         sizeof(mfc->additionalTransparencyColors) /
	                             sizeof(mfc->additionalTransparencyColors[0]))
	                   : 0;

	for (size_t i = 0; i < count; i++)
		[numbers addObject:@((NSInteger)MIN(mfc->additionalTransparencyTolerances[i], 255))];

	return numbers;
}

static NSArray *mac_blur_number_array(const mfContext *mfc)
{
	NSMutableArray *numbers = [NSMutableArray array];
	size_t count = mfc ? MIN(mfc->additionalTransparencyColorCount,
	                         sizeof(mfc->additionalTransparencyColors) /
	                             sizeof(mfc->additionalTransparencyColors[0]))
	                   : 0;

	for (size_t i = 0; i < count; i++)
		[numbers addObject:@(mfc->additionalTransparencyBlur[i])];

	return numbers;
}

static void mac_set_additional_transparency_colors_from_arrays(mfContext *mfc, NSArray *colors,
                                                               NSArray *transparencies,
                                                               NSArray *tolerances, NSArray *blur)
{
	if (!mfc)
		return;

	size_t count = 0;
	NSUInteger colorCount = [colors count];
	for (NSUInteger i = 0; i < colorCount; i++)
	{
		id color = [colors objectAtIndex:i];
		id transparency = (i < [transparencies count]) ? [transparencies objectAtIndex:i] : nil;
		id tolerance = (i < [tolerances count]) ? [tolerances objectAtIndex:i] : nil;
		id blurEnabled = (i < [blur count]) ? [blur objectAtIndex:i] : nil;
		if (![color respondsToSelector:@selector(integerValue)])
			continue;
		if (![transparency respondsToSelector:@selector(integerValue)])
			continue;
		if (count >= sizeof(mfc->additionalTransparencyColors) /
		                 sizeof(mfc->additionalTransparencyColors[0]))
			break;

		mfc->additionalTransparencyColors[count++] =
		    (uint32_t)([color integerValue] & 0xFFFFFF);
		mfc->additionalTransparencyLevels[count - 1] =
		    (UINT32)MIN(MAX([transparency integerValue], 0), 100);
		mfc->additionalTransparencyTolerances[count - 1] =
		    [tolerance respondsToSelector:@selector(integerValue)]
		        ? (UINT32)MIN(MAX([tolerance integerValue], 0), 255)
		        : 0;
		mfc->additionalTransparencyBlur[count - 1] =
		    [blurEnabled respondsToSelector:@selector(boolValue)] ? [blurEnabled boolValue] : FALSE;
	}

	mfc->additionalTransparencyColorCount = count;
}

static NSString *mac_modifier_keyswap_filter_string(const mfContext *mfc)
{
	if (!mfc || mfc->modifierKeyswapFilter[0] == '\0')
		return @"";

	return [NSString stringWithUTF8String:mfc->modifierKeyswapFilter];
}

static void mac_set_modifier_keyswap_filter(mfContext *mfc, NSString *filter)
{
	if (!mfc)
		return;

	NSString *trimmed =
	    [filter stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed)
		trimmed = @"";

	const char *utf8 = [trimmed UTF8String];
	if (!utf8)
		utf8 = "";

	strncpy(mfc->modifierKeyswapFilter, utf8, sizeof(mfc->modifierKeyswapFilter) - 1);
	mfc->modifierKeyswapFilter[sizeof(mfc->modifierKeyswapFilter) - 1] = '\0';
}

@interface AppDelegate ()
{
	id leftEdgeMouseMonitor;
	NSTimer *leftEdgeFocusTimer;
	NSStatusItem *statusItem;
	NSMenu *statusMenu;
	MRDPMonitorSliceView *primaryMonitorSliceView;
	NSMutableArray *monitorWindows;
	NSMutableArray *monitorSliceViews;
	NSMutableArray *taskbarWindows;
	NSMutableArray *taskbarSliceViews;
	NSMutableDictionary *statusSessions;
	NSTimer *statusCoordinationTimer;
	NSTimer *spacerEnforcementTimer;
	NSTimer *taskbarHideTimer;
	NSInteger preferredScreenIndex;
	NSSlider *windowDragTitlebarHeightSlider;
	NSTextField *windowDragTitlebarHeightValueLabel;
	NSTextField *modifierKeyswapFilterField;
}
- (void)ensureClientWindow;
- (void)startLeftEdgeFocusMonitor;
- (void)stopLeftEdgeFocusMonitor;
- (void)handleGlobalMouseEvent:(NSEvent *)event;
- (void)cancelLeftEdgeFocusTimer;
- (void)scheduleLeftEdgeFocusTimer;
- (void)leftEdgeFocusTimerFired:(NSTimer *)timer;
- (void)focusClientWindow;
- (void)syncMultimonWindows;
- (void)closeMultimonWindows;
- (void)syncTaskbarHideWindows;
- (void)closeTaskbarHideWindows;
- (void)startTaskbarHideMonitor;
- (void)stopTaskbarHideMonitor;
- (void)taskbarHideTimerFired:(NSTimer *)timer;
- (void)multimonFramebufferDidUpdate:(NSNotification *)notification;
- (void)applyWindowDecorationsFromSettings;
- (void)configureMainMenu;
- (void)configureApplicationIcon;
- (void)configureStatusCoordination;
- (void)stopStatusCoordination;
- (void)statusCoordinationTimerFired:(NSTimer *)timer;
- (void)reevaluateStatusItemOwnership;
- (void)broadcastStatusSessionUpdate;
- (void)broadcastStatusSessionWillTerminate;
- (void)handleStatusSessionDidUpdate:(NSNotification *)notification;
- (void)handleStatusSessionWillTerminate:(NSNotification *)notification;
- (void)handleStatusCommand:(NSNotification *)notification;
- (NSDictionary *)statusSessionInfo;
- (NSNumber *)localStatusSessionPID;
- (BOOL)isStatusItemOwner;
- (BOOL)isLocalStatusSession:(NSDictionary *)session;
- (void)postStatusCommand:(NSString *)command forSession:(NSDictionary *)session value:(NSNumber *)value;
- (void)installStatusItem;
- (void)removeStatusItem;
- (void)statusItemClicked:(id)sender;
- (void)rebuildStatusMenu;
- (void)appendSessionMenuItemsToMenu:(NSMenu *)menu
                          forSession:(NSDictionary *)session
                         includeQuit:(BOOL)includeQuit;
- (void)remoteStatusCommandFromMenuItem:(NSMenuItem *)menuItem;
- (void)focusSessionFromMenuItem:(id)sender;
- (void)refreshBitmapFromMenuItem:(id)sender;
- (void)quitSessionFromMenuItem:(id)sender;
- (void)quitAllFromMenuItem:(id)sender;
- (void)setSpacerPositionFromMenuItem:(NSMenuItem *)menuItem;
- (void)showGeneralSettingsFromMenuItem:(id)sender;
- (void)showModifierKeyswapFilterFromButton:(NSButton *)sender;
- (void)updateWindowDragTitlebarHeightPreviewFromSlider:(id)sender;
- (void)showSpacerSettingsFromMenuItem:(id)sender;
- (void)setTaskbarPositionFromMenuItem:(NSMenuItem *)menuItem;
- (void)showTaskbarSettingsFromMenuItem:(id)sender;
- (void)updateSpacerWindow;
- (void)showSpacerWindow;
- (void)hideSpacerWindow;
- (void)startSpacerEnforcement;
- (void)stopSpacerEnforcement;
- (void)spacerEnforcementTimerFired:(NSTimer *)timer;
- (void)enforceSpacerForWindows;
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
- (void)loadChromaKeySettingsFromDefaults;
- (void)loadTaskbarSettingsFromDefaults;
- (NSString *)sessionMenuTitle;
- (NSArray *)runningMacFreeRDPApplications;
@end

@implementation AppDelegate

- (void)dealloc
{
	[self stopLeftEdgeFocusMonitor];
	[self cancelLeftEdgeFocusTimer];
	[self stopStatusCoordination];
	[self removeStatusItem];
	[self stopTaskbarHideMonitor];
	[self closeTaskbarHideWindows];
	[self closeMultimonWindows];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self hideSpacerWindow];
	[self stopSpacerEnforcement];
	[statusSessions release];
	[statusMenu release];
	[monitorWindows release];
	[monitorSliceViews release];
	[taskbarWindows release];
	[taskbarSliceViews release];
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
	[newWindow setHasShadow:NO];

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
	[window setHasShadow:mfc->windowShadowsEnabled];

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
	[self loadChromaKeySettingsFromDefaults];
	[self loadSpacerSettingsFromDefaults];
	[self loadTaskbarSettingsFromDefaults];
	[self ensureClientWindow];
	[self configureMainMenu];
	[self configureApplicationIcon];
	[self configureStatusCoordination];

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
		[window setHasShadow:NO];
	}

	status = [self ParseCommandLineArguments];
	mfc = (mfContext *)context;
	WINPR_ASSERT(mfc);
	[self applyWindowDecorationsFromSettings];
	if (mac_taskbar_hide_enabled(mfc))
		[self startTaskbarHideMonitor];
	[self startLeftEdgeFocusMonitor];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(multimonFramebufferDidUpdate:)
	                                             name:@"MRDPMultimonFramebufferDidUpdate"
	                                           object:nil];

	mfc->view = (void *)mrdpView;

	if (status == 0)
	{
		NSScreen *screen = [self preferredScreen];
		NSRect screenFrame = [screen frame];
		rdpSettings *settings = context->settings;

		WINPR_ASSERT(settings);

		if (!mac_apply_display_properties(mfc, mfc->fullscreen_mode == 2))
		{
			[NSApp terminate:self];
			return;
		}

		if (!freerdp_settings_get_bool(settings, FreeRDP_UseMultimon) &&
		    freerdp_settings_get_bool(settings, FreeRDP_Fullscreen) &&
		    mfc->fullscreen_mode != 2 &&
		    !freerdp_settings_get_bool(settings, FreeRDP_SmartSizing))
		{
			(void)freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth,
			                                  screenFrame.size.width);
			(void)freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight,
			                                  screenFrame.size.height);
		}

		PubSub_SubscribeConnectionResult(context->pubSub,
		                                 AppDelegate_ConnectionResultEventHandler);
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
		[self broadcastStatusSessionUpdate];
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
	[self broadcastStatusSessionWillTerminate];
	[self stopStatusCoordination];
	[self stopTaskbarHideMonitor];
	[self stopSpacerEnforcement];
	[self removeStatusItem];
	[self closeTaskbarHideWindows];
	[self closeMultimonWindows];
	[[NSNotificationCenter defaultCenter] removeObserver:self
	                                                name:@"MRDPMultimonFramebufferDidUpdate"
	                                              object:nil];
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
	NSWindow *keyWindow = [notification object];
	if (keyWindow == window)
	{
		[self focusClientWindow];
		return;
	}

	NSView *contentView = [keyWindow contentView];
	if ([contentView isKindOfClass:[MRDPMonitorSliceView class]])
		[keyWindow makeFirstResponder:contentView];
}

- (void)windowDidMove:(NSNotification *)notification
{
	(void)notification;
	[self savePreferredScreenToDefaults];
	[self broadcastStatusSessionUpdate];
}

- (void)windowDidResize:(NSNotification *)notification
{
	(void)notification;

	if (context && mrdpView)
		mac_fit_view_to_window_content(context, mrdpView);

	[self broadcastStatusSessionUpdate];
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

- (void)closeMultimonWindows
{
	if (primaryMonitorSliceView)
	{
		[primaryMonitorSliceView removeFromSuperview];
		[primaryMonitorSliceView release];
		primaryMonitorSliceView = nil;
	}

	if (mrdpView)
		[mrdpView setHidden:NO];

	if (monitorWindows)
	{
		for (NSWindow *monitorWindow in monitorWindows)
		{
			[monitorWindow orderOut:self];
			[monitorWindow setDelegate:nil];
		}
		[monitorWindows removeAllObjects];
	}

	if (monitorSliceViews)
		[monitorSliceViews removeAllObjects];
}

- (void)multimonFramebufferDidUpdate:(NSNotification *)notification
{
	if ([notification object] != mrdpView)
		return;

	[primaryMonitorSliceView setNeedsDisplay:YES];
	for (NSView *sliceView in monitorSliceViews)
		[sliceView setNeedsDisplay:YES];
	for (NSView *sliceView in taskbarSliceViews)
		[sliceView setNeedsDisplay:YES];
}

- (void)syncMultimonWindows
{
	if (!context)
	{
		[self closeMultimonWindows];
		[self closeTaskbarHideWindows];
		return;
	}

	mfContext *mfc = (mfContext *)context;
	const BOOL taskbarHide = mac_taskbar_hide_enabled(mfc);

	if (!context || !context->settings || !mrdpView ||
	    (!mac_multimon_enabled(context->settings) && !taskbarHide))
	{
		[self closeMultimonWindows];
		[self closeTaskbarHideWindows];
		return;
	}

	NSArray *slices = mac_multimon_enabled(context->settings)
	                      ? mac_multimon_slices(context->settings, mfc)
	                      : mac_taskbar_single_monitor_slices(context->settings, mfc, window);
	if ([slices count] == 0)
	{
		const UINT32 desktopWidth =
		    freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth);
		const UINT32 desktopHeight =
		    freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopHeight);
		NSRect frame = [window frame];
		if (taskbarHide && primaryMonitorSliceView)
		{
			NSRect source = NSMakeRect(0, 0, desktopWidth, desktopHeight);
			const CGFloat taskbarSize = mac_taskbar_hide_size(mfc, source);
			frame = mac_taskbar_full_frame(frame, mfc->taskbarHidePosition, taskbarSize);
		}
		NSScreen *screen = mac_preferred_screen(window);
		if (!screen)
			screen = [NSScreen mainScreen];
		NSDictionary *slice = @{
			@"screen" : screen,
			@"frame" : [NSValue valueWithRect:frame],
			@"source" : [NSValue valueWithRect:NSMakeRect(0, 0, desktopWidth, desktopHeight)]
		};
		slices = [NSArray arrayWithObject:slice];
	}

	if ([slices count] <= 1 && !taskbarHide)
	{
		[self closeMultimonWindows];
		[self closeTaskbarHideWindows];
		return;
	}

	if (!monitorWindows)
		monitorWindows = [[NSMutableArray alloc] init];
	if (!monitorSliceViews)
		monitorSliceViews = [[NSMutableArray alloc] init];
	if (!taskbarWindows)
		taskbarWindows = [[NSMutableArray alloc] init];
	if (!taskbarSliceViews)
		taskbarSliceViews = [[NSMutableArray alloc] init];

	NSDictionary *primarySlice = [slices objectAtIndex:0];
	NSRect primarySource = [[primarySlice objectForKey:@"source"] rectValue];
	NSRect primaryFrame = [[primarySlice objectForKey:@"frame"] rectValue];
	const UINT32 taskbarPosition = taskbarHide ? mfc->taskbarHidePosition : UINT32_MAX;
	const CGFloat taskbarSize = taskbarHide ? mac_taskbar_hide_size(mfc, primarySource) : 0.0;
	const BOOL extendedCanvas = mac_taskbar_uses_extended_canvas(mfc);
	if (taskbarSize > 0.0)
	{
		primarySource = mac_taskbar_visible_source(primarySource, taskbarPosition, taskbarSize);
		if (!extendedCanvas)
			primaryFrame = mac_taskbar_visible_frame(primaryFrame, taskbarPosition, taskbarSize);
		[window setFrame:primaryFrame display:YES];
	}

	if (!primaryMonitorSliceView)
	{
		primaryMonitorSliceView = [[MRDPMonitorSliceView alloc] initWithPrimaryView:mrdpView
		                                                                sourceRect:primarySource];
		primaryMonitorSliceView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[[window contentView] addSubview:primaryMonitorSliceView positioned:NSWindowAbove
		                  relativeTo:mrdpView];
	}
	else
	{
		[primaryMonitorSliceView setSourceRect:primarySource];
	}
	primaryMonitorSliceView.frame = [[window contentView] bounds];
	[window setInitialFirstResponder:primaryMonitorSliceView];
	[window makeFirstResponder:primaryMonitorSliceView];
	[mrdpView setHidden:YES];
	[self syncTaskbarHideWindows];

	while ([monitorWindows count] > [slices count] - 1)
	{
		NSWindow *oldWindow = [monitorWindows lastObject];
		[oldWindow orderOut:self];
		[oldWindow setDelegate:nil];
		[monitorWindows removeLastObject];
		[monitorSliceViews removeLastObject];
	}

	NSString *baseTitle = [window title] ?: @"MacFreeRDP";
	const BOOL decorated = freerdp_settings_get_bool(context->settings, FreeRDP_Decorations);
	const NSWindowStyleMask styleMask =
	    decorated ? (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	                 NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
	              : NSWindowStyleMaskBorderless;
	const CGFloat taskbarSizeSecondary = taskbarSize;
	const UINT32 taskbarPositionSecondary = taskbarPosition;
	const BOOL extendedCanvasSecondary = extendedCanvas;
	for (NSUInteger i = 1; i < [slices count]; i++)
	{
		NSDictionary *slice = [slices objectAtIndex:i];
		NSRect frame = [[slice objectForKey:@"frame"] rectValue];
		NSRect source = [[slice objectForKey:@"source"] rectValue];
		if (taskbarSizeSecondary > 0.0)
		{
			source = mac_taskbar_visible_source(source, taskbarPositionSecondary,
			                                    taskbarSizeSecondary);
			if (!extendedCanvasSecondary)
				frame = mac_taskbar_visible_frame(frame, taskbarPositionSecondary,
				                                  taskbarSizeSecondary);
		}
		NSUInteger sliceIndex = i - 1;
		NSWindow *monitorWindow = nil;
		MRDPMonitorSliceView *sliceView = nil;

		if (sliceIndex < [monitorWindows count])
		{
			monitorWindow = [monitorWindows objectAtIndex:sliceIndex];
			sliceView = [monitorSliceViews objectAtIndex:sliceIndex];
			[sliceView setSourceRect:source];
		}
		else
		{
			sliceView = [[[MRDPMonitorSliceView alloc] initWithPrimaryView:mrdpView
			                                                    sourceRect:source] autorelease];
			monitorWindow = [[[MRDPClientWindow alloc] initWithContentRect:frame
			                                                     styleMask:styleMask
			                                                       backing:NSBackingStoreBuffered
			                                                         defer:NO] autorelease];
			[monitorWindow setAcceptsMouseMovedEvents:YES];
			[monitorWindow setDelegate:self];
			[monitorWindow setContentView:sliceView];
			[monitorWindow setInitialFirstResponder:sliceView];
			[monitorWindow setReleasedWhenClosed:NO];
			[monitorWindow setOpaque:NO];
			[monitorWindow setBackgroundColor:[NSColor clearColor]];
			[monitorWindows addObject:monitorWindow];
			[monitorSliceViews addObject:sliceView];
		}

		[monitorWindow setStyleMask:styleMask];
		[monitorWindow setMovable:decorated];
		[monitorWindow setTitleVisibility:decorated ? NSWindowTitleVisible : NSWindowTitleHidden];
		[monitorWindow setTitlebarAppearsTransparent:decorated ? NO : YES];
		[monitorWindow setTitle:[NSString stringWithFormat:@"%@ [%lu]", baseTitle,
		                                                   (unsigned long)(i + 1)]];
		[monitorWindow setFrame:frame display:YES];
		[monitorWindow setFrame:mac_constrain_window_frame_to_screen([monitorWindow frame],
		                                                             [slice objectForKey:@"screen"],
		                                                             decorated)
		                display:YES];
		[monitorWindow orderFront:self];
	}
}

- (void)syncTaskbarHideWindows
{
	if (!context || !context->settings || !mrdpView)
	{
		[self closeTaskbarHideWindows];
		return;
	}

	mfContext *mfc = (mfContext *)context;
	if (!mac_taskbar_hide_enabled(mfc))
	{
		[self closeTaskbarHideWindows];
		return;
	}

	NSArray *slices = mac_multimon_enabled(context->settings)
	                      ? mac_multimon_slices(context->settings, mfc)
	                      : mac_taskbar_single_monitor_slices(context->settings, mfc, window);
	if ([slices count] == 0)
	{
		const UINT32 desktopWidth =
		    freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth);
		const UINT32 desktopHeight =
		    freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopHeight);
		NSRect mainFrame = [window frame];
		NSRect source = NSMakeRect(0, 0, desktopWidth, desktopHeight);
		const CGFloat taskbarSize = mac_taskbar_hide_size(mfc, source);
		NSRect originalFrame =
		    mac_taskbar_full_frame(mainFrame, mfc->taskbarHidePosition, taskbarSize);
		NSScreen *screen = mac_preferred_screen(window);
		if (!screen)
			screen = [NSScreen mainScreen];
		NSDictionary *slice = @{
			@"screen" : screen,
			@"frame" : [NSValue valueWithRect:originalFrame],
			@"source" : [NSValue valueWithRect:source]
		};
		slices = [NSArray arrayWithObject:slice];
	}

	if (!taskbarWindows)
		taskbarWindows = [[NSMutableArray alloc] init];
	if (!taskbarSliceViews)
		taskbarSliceViews = [[NSMutableArray alloc] init];

	while ([taskbarWindows count] > [slices count])
	{
		NSWindow *oldWindow = [taskbarWindows lastObject];
		[oldWindow orderOut:self];
		[oldWindow setDelegate:nil];
		[taskbarWindows removeLastObject];
		[taskbarSliceViews removeLastObject];
	}

	NSString *baseTitle = [window title] ?: @"MacFreeRDP";
	NSPoint mouse = [NSEvent mouseLocation];
	const UINT32 taskbarPosition = mfc->taskbarHidePosition;
	for (NSUInteger i = 0; i < [slices count]; i++)
	{
		NSDictionary *slice = [slices objectAtIndex:i];
		NSRect frame = [[slice objectForKey:@"frame"] rectValue];
		NSRect source = [[slice objectForKey:@"source"] rectValue];
		const CGFloat taskbarSize = mac_taskbar_hide_size(mfc, source);

		if (taskbarSize <= 0.0)
			continue;

		NSRect taskbarFrame, taskbarSource;
		if (taskbarPosition == 0) // top
		{
			taskbarFrame = NSMakeRect(NSMinX(frame), NSMaxY(frame) - taskbarSize, NSWidth(frame), taskbarSize);
			taskbarSource = NSMakeRect(NSMinX(source), NSMinY(source), NSWidth(source), taskbarSize);
		}
		else if (taskbarPosition == 1) // bottom
		{
			taskbarFrame = NSMakeRect(NSMinX(frame), NSMinY(frame), NSWidth(frame), taskbarSize);
			taskbarSource = NSMakeRect(NSMinX(source), NSMaxY(source) - taskbarSize, NSWidth(source), taskbarSize);
		}
		else if (taskbarPosition == 2) // left
		{
			taskbarFrame = NSMakeRect(NSMinX(frame), NSMinY(frame), taskbarSize, NSHeight(frame));
			taskbarSource = NSMakeRect(NSMinX(source), NSMinY(source), taskbarSize, NSHeight(source));
		}
		else // right (taskbarPosition == 3)
		{
			taskbarFrame = NSMakeRect(NSMaxX(frame) - taskbarSize, NSMinY(frame), taskbarSize, NSHeight(frame));
			taskbarSource = NSMakeRect(NSMaxX(source) - taskbarSize, NSMinY(source), taskbarSize, NSHeight(source));
		}
		NSWindow *taskbarWindow = nil;
		MRDPMonitorSliceView *sliceView = nil;

		if (i < [taskbarWindows count])
		{
			taskbarWindow = [taskbarWindows objectAtIndex:i];
			sliceView = [taskbarSliceViews objectAtIndex:i];
			[sliceView setSourceRect:taskbarSource];
		}
		else
		{
			sliceView = [[[MRDPMonitorSliceView alloc] initWithPrimaryView:mrdpView
			                                                    sourceRect:taskbarSource] autorelease];
			taskbarWindow = [[[MRDPClientWindow alloc] initWithContentRect:taskbarFrame
			                                                     styleMask:NSWindowStyleMaskBorderless
			                                                       backing:NSBackingStoreBuffered
			                                                         defer:NO] autorelease];
			[taskbarWindow setAcceptsMouseMovedEvents:YES];
			[taskbarWindow setDelegate:self];
			[taskbarWindow setContentView:sliceView];
			[taskbarWindow setInitialFirstResponder:sliceView];
			[taskbarWindow setReleasedWhenClosed:NO];
			[taskbarWindow setOpaque:NO];
			[taskbarWindow setBackgroundColor:[NSColor clearColor]];
			[taskbarWindow setHasShadow:NO];
			[taskbarWindow setLevel:(NSWindowLevel)(CGWindowLevelForKey(kCGDockWindowLevelKey) - 1)];
			[taskbarWindows addObject:taskbarWindow];
			[taskbarSliceViews addObject:sliceView];
		}

		[taskbarWindow setStyleMask:NSWindowStyleMaskBorderless];
		[taskbarWindow setLevel:(NSWindowLevel)(CGWindowLevelForKey(kCGDockWindowLevelKey) - 1)];
		[taskbarWindow setMovable:NO];
		[taskbarWindow setTitleVisibility:NSWindowTitleHidden];
		[taskbarWindow setTitlebarAppearsTransparent:YES];
		[taskbarWindow setTitle:[NSString stringWithFormat:@"%@ Taskbar [%lu]", baseTitle,
		                                                    (unsigned long)(i + 1)]];
		[taskbarWindow setFrame:taskbarFrame display:YES];

		const BOOL mouseInsideTaskbar = NSPointInRect(mouse, taskbarFrame);
		const BOOL shouldReveal =
		    mouseInsideTaskbar || (![taskbarWindow isVisible] &&
		                           mac_taskbar_mouse_should_reveal(mouse, taskbarFrame));
		if (shouldReveal)
		{
			[taskbarWindow orderFront:self];
			if (mouseInsideTaskbar)
			{
				BOOL valid = NO;
				NSPoint remotePoint = [sliceView remotePointForScreenPoint:mouse valid:&valid];
				if (valid && ![sliceView isRemotePointTransparent:remotePoint])
				{
					[NSApp activateIgnoringOtherApps:YES];
					[taskbarWindow makeKeyAndOrderFront:self];
					[taskbarWindow makeFirstResponder:sliceView];
				}
			}
		}
		else
		{
			[taskbarWindow orderOut:self];
		}
	}
}

- (void)closeTaskbarHideWindows
{
	if (taskbarWindows)
	{
		for (NSWindow *taskbarWindow in taskbarWindows)
		{
			[taskbarWindow orderOut:self];
			[taskbarWindow setDelegate:nil];
		}
		[taskbarWindows removeAllObjects];
	}

	if (taskbarSliceViews)
		[taskbarSliceViews removeAllObjects];
}

- (void)startTaskbarHideMonitor
{
	if (taskbarHideTimer)
		return;

	taskbarHideTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
	                                                    target:self
	                                                  selector:@selector(taskbarHideTimerFired:)
	                                                  userInfo:nil
	                                                   repeats:YES];
	[taskbarHideTimer setTolerance:0.03];
}

- (void)stopTaskbarHideMonitor
{
	if (!taskbarHideTimer)
		return;

	[taskbarHideTimer invalidate];
	taskbarHideTimer = nil;
}

- (void)taskbarHideTimerFired:(NSTimer *)timer
{
	if (timer != taskbarHideTimer)
		return;

	[self syncTaskbarHideWindows];
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

- (void)configureStatusCoordination
{
	if (!statusSessions)
		statusSessions = [[NSMutableDictionary alloc] init];

	[statusSessions setObject:[self statusSessionInfo] forKey:[self localStatusSessionPID]];

	NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
	[center addObserver:self
	           selector:@selector(handleStatusSessionDidUpdate:)
	               name:MRDPStatusSessionDidUpdateNotification
	             object:nil];
	[center addObserver:self
	           selector:@selector(handleStatusSessionWillTerminate:)
	               name:MRDPStatusSessionWillTerminateNotification
	             object:nil];
	[center addObserver:self
	           selector:@selector(handleStatusCommand:)
	               name:MRDPStatusCommandNotification
	             object:nil];

	statusCoordinationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
	                                                           target:self
	                                                         selector:@selector(statusCoordinationTimerFired:)
	                                                         userInfo:nil
	                                                          repeats:YES];

	[self reevaluateStatusItemOwnership];
	[self broadcastStatusSessionUpdate];
}

- (void)stopStatusCoordination
{
	if (statusCoordinationTimer)
	{
		[statusCoordinationTimer invalidate];
		statusCoordinationTimer = nil;
	}

	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}

- (void)statusCoordinationTimerFired:(NSTimer *)timer
{
	(void)timer;
	[self reevaluateStatusItemOwnership];
	[self broadcastStatusSessionUpdate];
}

- (void)reevaluateStatusItemOwnership
{
	NSMutableSet *runningPIDs = [NSMutableSet set];
	for (NSRunningApplication *application in [self runningMacFreeRDPApplications])
		[runningPIDs addObject:[NSNumber numberWithInt:[application processIdentifier]]];
	[runningPIDs addObject:[self localStatusSessionPID]];

	NSArray *sessionPIDs = [[statusSessions allKeys] copy];
	for (NSNumber *pid in sessionPIDs)
	{
		if (![runningPIDs containsObject:pid])
			[statusSessions removeObjectForKey:pid];
	}
	[sessionPIDs release];

	if ([self isStatusItemOwner])
		[self installStatusItem];
	else
		[self removeStatusItem];
}

- (void)broadcastStatusSessionUpdate
{
	NSDictionary *info = [self statusSessionInfo];
	[statusSessions setObject:info forKey:[self localStatusSessionPID]];

	[[NSDistributedNotificationCenter defaultCenter]
	    postNotificationName:MRDPStatusSessionDidUpdateNotification
	                  object:nil
	                userInfo:info
	      deliverImmediately:YES];
}

- (void)broadcastStatusSessionWillTerminate
{
	NSDictionary *info = [NSDictionary dictionaryWithObject:[self localStatusSessionPID] forKey:@"pid"];
	[[NSDistributedNotificationCenter defaultCenter]
	    postNotificationName:MRDPStatusSessionWillTerminateNotification
	                  object:nil
	                userInfo:info
	      deliverImmediately:YES];
}

- (void)handleStatusSessionDidUpdate:(NSNotification *)notification
{
	NSDictionary *info = [notification userInfo];
	NSNumber *pid = [info objectForKey:@"pid"];
	if (!pid)
		return;

	[statusSessions setObject:info forKey:pid];
	[self reevaluateStatusItemOwnership];
}

- (void)handleStatusSessionWillTerminate:(NSNotification *)notification
{
	NSNumber *pid = [[notification userInfo] objectForKey:@"pid"];
	if (pid)
		[statusSessions removeObjectForKey:pid];

	[self reevaluateStatusItemOwnership];
}

- (void)handleStatusCommand:(NSNotification *)notification
{
	NSDictionary *info = [notification userInfo];
	NSNumber *pid = [info objectForKey:@"pid"];
	NSString *command = [info objectForKey:@"command"];

	if (!pid || !command || ![pid isEqualToNumber:[self localStatusSessionPID]])
		return;

	if ([command isEqualToString:@"focus"])
		[self focusClientWindow];
	else if ([command isEqualToString:@"refresh"])
		[self refreshBitmapFromMenuItem:nil];
	else if ([command isEqualToString:@"screen"])
	{
		NSNumber *screenIndex = [info objectForKey:@"value"];
		NSScreen *screen = mac_screen_for_index([screenIndex integerValue]);
		[self moveSessionToScreen:screen screenIndex:[screenIndex integerValue]];
	}
	else if ([command isEqualToString:@"spacerPosition"])
	{
		NSNumber *position = [info objectForKey:@"value"];
		mfContext *mfc = (mfContext *)context;
		mfc->spacerPosition = (UINT32)[position integerValue];

		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults setInteger:(NSInteger)mfc->spacerPosition forKey:@"MRDPSpacerPosition"];
		[defaults synchronize];

		[self updateSpacerWindow];
		[self broadcastStatusSessionUpdate];
	}
	else if ([command isEqualToString:@"spacerSettings"])
	{
		[self showSpacerSettingsFromMenuItem:nil];
	}
	else if ([command isEqualToString:@"chroma"])
	{
		NSNumber *enabled = [info objectForKey:@"enabled"];
		NSNumber *featheringEnabled = [info objectForKey:@"featheringEnabled"];
		NSNumber *color = [info objectForKey:@"color"];
		NSNumber *tolerance = [info objectForKey:@"tolerance"];
		NSArray *additionalColors = [info objectForKey:@"additionalColors"];
		NSArray *additionalTransparencies = [info objectForKey:@"additionalTransparencies"];
		NSArray *additionalTolerances = [info objectForKey:@"additionalTolerances"];
		NSArray *additionalBlur = [info objectForKey:@"additionalBlur"];
		mfContext *mfc = (mfContext *)context;

		if (enabled)
			mfc->chromaKeyEnabled = [enabled boolValue];
		if (featheringEnabled)
			mfc->chromaKeyFeatheringEnabled = [featheringEnabled boolValue];
		if (color)
			mfc->chromaKeyColor = (uint32_t)([color integerValue] & 0xFFFFFF);
		if (tolerance)
			mfc->chromaKeyTolerance = [tolerance floatValue];
		if (additionalColors && additionalTransparencies)
		{
			if (!additionalTolerances)
				additionalTolerances = [NSArray array];
			if (!additionalBlur)
				additionalBlur = [NSArray array];
			mac_set_additional_transparency_colors_from_arrays(mfc, additionalColors,
			                                                   additionalTransparencies,
			                                                   additionalTolerances,
			                                                   additionalBlur);
		}

		if (mrdpView)
			[mrdpView refreshBitmap];
	}
	else if ([command isEqualToString:@"windowShadows"])
	{
		NSNumber *enabled = [info objectForKey:@"enabled"];
		mfContext *mfc = (mfContext *)context;

		if (enabled)
		{
			mfc->windowShadowsEnabled = [enabled boolValue];
			[self applyWindowDecorationsFromSettings];
		}
	}
	else if ([command isEqualToString:@"windowDragTitlebarHeight"])
	{
		NSNumber *height = [info objectForKey:@"height"];
		mfContext *mfc = (mfContext *)context;

		if (height)
		{
			mfc->windowDragTitlebarHeight = (UINT32)MIN(MAX([height integerValue], 1), 200);
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			[defaults setInteger:(NSInteger)mfc->windowDragTitlebarHeight
			               forKey:MRDPWindowDragTitlebarHeightKey];
			[defaults synchronize];
			if (mrdpView)
				[mrdpView setNeedsDisplay:YES];
		}
	}
	else if ([command isEqualToString:@"modifierKeyswap"])
	{
		NSNumber *mode = [info objectForKey:@"mode"];
		NSString *filter = [info objectForKey:@"filter"];
		mfContext *mfc = (mfContext *)context;

		if (mode)
			mfc->modifierKeyswapMode =
			    (MF_MODIFIER_KEYSWAP_MODE)MIN(MAX([mode integerValue], 0), 2);
		if (filter)
			mac_set_modifier_keyswap_filter(mfc, filter);

		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults setInteger:(NSInteger)mfc->modifierKeyswapMode
		               forKey:MRDPModifierKeyswapModeKey];
		[defaults setObject:mac_modifier_keyswap_filter_string(mfc)
		         forKey:MRDPModifierKeyswapFilterKey];
		[defaults synchronize];
	}
	else if ([command isEqualToString:@"quit"])
	{
		[NSApp terminate:self];
	}
}

- (NSDictionary *)statusSessionInfo
{
	mfContext *mfc = (mfContext *)context;

	return [NSDictionary dictionaryWithObjectsAndKeys:
	                         [self localStatusSessionPID], @"pid",
	                         [self sessionMenuTitle], @"title",
	                         @([self currentScreenIndex]), @"currentScreen",
	                         @(mfc ? mfc->spacerPosition : 0), @"spacerPosition",
	                         @(mfc ? mfc->spacerEnabled : NO), @"spacerEnabled",
	                         @(mfc ? mfc->taskbarHidePosition : 1), @"taskbarHidePosition",
	                         @(mfc ? mfc->taskbarHide : NO), @"taskbarHide",
	                         nil];
}

- (NSNumber *)localStatusSessionPID
{
	return [NSNumber numberWithInt:getpid()];
}

- (BOOL)isStatusItemOwner
{
	pid_t localPID = getpid();
	pid_t ownerPID = localPID;

	for (NSRunningApplication *application in [self runningMacFreeRDPApplications])
	{
		pid_t pid = [application processIdentifier];
		if (pid > 0 && pid < ownerPID)
			ownerPID = pid;
	}

	return ownerPID == localPID;
}

- (BOOL)isLocalStatusSession:(NSDictionary *)session
{
	return [[session objectForKey:@"pid"] isEqualToNumber:[self localStatusSessionPID]];
}

- (void)postStatusCommand:(NSString *)command forSession:(NSDictionary *)session value:(NSNumber *)value
{
	NSNumber *pid = [session objectForKey:@"pid"];
	if (!pid || !command)
		return;

	NSMutableDictionary *info =
	    [NSMutableDictionary dictionaryWithObjectsAndKeys:pid, @"pid", command, @"command", nil];
	if (value)
		[info setObject:value forKey:@"value"];

	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:MRDPStatusCommandNotification
	                                                               object:nil
	                                                             userInfo:info
	                                                   deliverImmediately:YES];
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
	[statusMenu release];
	statusMenu = nil;
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

	NSArray *sessions = [[statusSessions allValues]
	    sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
		    NSNumber *leftPID = [left objectForKey:@"pid"];
		    NSNumber *rightPID = [right objectForKey:@"pid"];
		    return [leftPID compare:rightPID];
	    }];

	for (NSDictionary *session in sessions)
	{
		NSString *sessionTitle = [session objectForKey:@"title"] ?: @"Current Session";
		NSMenuItem *sessionItem = [[[NSMenuItem alloc] initWithTitle:sessionTitle
		                                                      action:nil
		                                               keyEquivalent:@""] autorelease];
		NSMenu *sessionMenu = [[[NSMenu alloc] initWithTitle:sessionTitle] autorelease];
		[self appendSessionMenuItemsToMenu:sessionMenu forSession:session includeQuit:YES];
		[sessionItem setSubmenu:sessionMenu];
		[statusMenu addItem:sessionItem];
	}

	if ([sessions count] == 0)
	{
		NSDictionary *session = [self statusSessionInfo];
		NSString *sessionTitle = [session objectForKey:@"title"] ?: @"Current Session";
		NSMenuItem *sessionItem = [[[NSMenuItem alloc] initWithTitle:sessionTitle
		                                                      action:nil
		                                               keyEquivalent:@""] autorelease];
		NSMenu *sessionMenu = [[[NSMenu alloc] initWithTitle:sessionTitle] autorelease];
		[self appendSessionMenuItemsToMenu:sessionMenu forSession:session includeQuit:NO];
		[sessionItem setSubmenu:sessionMenu];
		[statusMenu addItem:sessionItem];
	}

	[statusMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *generalSettingsItem =
	    [[[NSMenuItem alloc] initWithTitle:@"Settings"
	                                 action:@selector(showGeneralSettingsFromMenuItem:)
	                          keyEquivalent:@""] autorelease];
	[generalSettingsItem setTarget:self];
	[statusMenu addItem:generalSettingsItem];

	NSMenuItem *quitItem =
	    [[[NSMenuItem alloc] initWithTitle:([sessions count] > 1 ? @"Quit All" : @"Quit MacFreeRDP")
	                                 action:@selector(quitAllFromMenuItem:)
	                          keyEquivalent:@""] autorelease];
	[quitItem setTarget:self];
	[statusMenu addItem:quitItem];
}

- (void)appendSessionMenuItemsToMenu:(NSMenu *)menu
                          forSession:(NSDictionary *)session
                         includeQuit:(BOOL)includeQuit
{
	NSArray *screens = [NSScreen screens];
	BOOL localSession = [self isLocalStatusSession:session];
	NSInteger currentScreen = localSession ? [self currentScreenIndex]
	                                      : [[session objectForKey:@"currentScreen"] integerValue];

	for (NSUInteger index = 0; index < [screens count]; index++)
	{
		NSScreen *screen = [screens objectAtIndex:index];
		NSMenuItem *menuItem =
		    [[[NSMenuItem alloc] initWithTitle:mac_display_title(screen, (NSInteger)index)
		                                 action:(localSession ? @selector(switchMonitorFromMenuItem:)
		                                                       : @selector(remoteStatusCommandFromMenuItem:))
		                          keyEquivalent:@""] autorelease];
		[menuItem setTarget:self];
		[menuItem setTag:(NSInteger)index];
		if (!localSession)
			[menuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
			                                             session, @"session", @"screen", @"command",
			                                             @((NSInteger)index), @"value", nil]];
		[menuItem setState:((NSInteger)index == currentScreen) ? NSControlStateValueOn
		                                                      : NSControlStateValueOff];
		[menu addItem:menuItem];
	}

	if ([screens count] > 0)
		[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *refreshItem =
	    [[[NSMenuItem alloc] initWithTitle:@"Refresh Bitmap"
	                                 action:(localSession ? @selector(refreshBitmapFromMenuItem:)
	                                                       : @selector(remoteStatusCommandFromMenuItem:))
	                          keyEquivalent:@""] autorelease];
	[refreshItem setTarget:self];
	if (!localSession)
		[refreshItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
		                                                session, @"session", @"refresh", @"command", nil]];
	[menu addItem:refreshItem];

	mfContext *mfc = (mfContext *)context;
	NSInteger spacerPosition = localSession ? (mfc ? (NSInteger)mfc->spacerPosition : 0)
	                                       : [[session objectForKey:@"spacerPosition"] integerValue];
	BOOL spacerEnabled = localSession ? (mfc && mfc->spacerEnabled)
	                                 : [[session objectForKey:@"spacerEnabled"] boolValue];
	NSMenuItem *spacerPositionItem = [[[NSMenuItem alloc] initWithTitle:@"Spacer Position"
	                                                               action:nil
	                                                        keyEquivalent:@""] autorelease];
	NSMenu *spacerPositionMenu = [[[NSMenu alloc] initWithTitle:@"Spacer Position"] autorelease];
	NSArray *positionEntries = [NSArray arrayWithObjects:
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Top", @"title", @(0), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Bottom", @"title", @(1), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Left", @"title", @(2), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Right", @"title", @(3), @"tag", nil],
	    nil];

	for (id entry in positionEntries)
	{
		NSDictionary *definition = (NSDictionary *)entry;
		NSString *title = [definition objectForKey:@"title"];
		NSInteger tag = [[definition objectForKey:@"tag"] integerValue];
		NSMenuItem *posItem = [[[NSMenuItem alloc] initWithTitle:title
		                                                    action:(localSession ? @selector(setSpacerPositionFromMenuItem:)
		                                                                          : @selector(remoteStatusCommandFromMenuItem:))
		                                             keyEquivalent:@""] autorelease];
		[posItem setTarget:self];
		[posItem setTag:tag];
		if (!localSession)
			[posItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
			                                           session, @"session", @"spacerPosition", @"command",
			                                           @(tag), @"value", nil]];
		[posItem setState:(tag == spacerPosition && spacerEnabled)
		                      ? NSControlStateValueOn
		                      : NSControlStateValueOff];
		[spacerPositionMenu addItem:posItem];
	}

	[spacerPositionMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *spacerSettingsItem =
	    [[[NSMenuItem alloc] initWithTitle:@"Settings"
	                                 action:(localSession ? @selector(showSpacerSettingsFromMenuItem:)
	                                                       : @selector(remoteStatusCommandFromMenuItem:))
	                          keyEquivalent:@""] autorelease];
	[spacerSettingsItem setTarget:self];
	if (!localSession)
		[spacerSettingsItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
		                                                       session, @"session", @"spacerSettings",
		                                                       @"command", nil]];
	[spacerPositionMenu addItem:spacerSettingsItem];

	[spacerPositionItem setSubmenu:spacerPositionMenu];
	[menu addItem:spacerPositionItem];

	NSInteger taskbarPosition = localSession ? (mfc ? (NSInteger)mfc->taskbarHidePosition : 1)
	                                        : [[session objectForKey:@"taskbarHidePosition"] integerValue];
	BOOL taskbarHide = localSession ? (mfc && mfc->taskbarHide)
	                              : [[session objectForKey:@"taskbarHide"] boolValue];
	NSMenuItem *taskbarHideItem = [[[NSMenuItem alloc] initWithTitle:@"Taskbar Position"
	                                                           action:nil
	                                                    keyEquivalent:@""] autorelease];
	NSMenu *taskbarHideMenu = [[[NSMenu alloc] initWithTitle:@"Taskbar Position"] autorelease];
	NSArray *taskbarPositionEntries = [NSArray arrayWithObjects:
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Top", @"title", @(0), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Bottom", @"title", @(1), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Left", @"title", @(2), @"tag", nil],
	    [NSDictionary dictionaryWithObjectsAndKeys:@"Right", @"title", @(3), @"tag", nil],
	    nil];

	for (id entry in taskbarPositionEntries)
	{
		NSDictionary *definition = (NSDictionary *)entry;
		NSString *title = [definition objectForKey:@"title"];
		NSInteger tag = [[definition objectForKey:@"tag"] integerValue];
		NSMenuItem *posItem = [[[NSMenuItem alloc] initWithTitle:title
		                                                   action:(localSession ? @selector(setTaskbarPositionFromMenuItem:)
		                                                                        : @selector(remoteStatusCommandFromMenuItem:))
		                                            keyEquivalent:@""] autorelease];
		[posItem setTarget:self];
		[posItem setTag:tag];
		if (!localSession)
			[posItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
			                                          session, @"session", @"taskbarHidePosition", @"command",
			                                          @(tag), @"value", nil]];
		[posItem setState:(tag == taskbarPosition && taskbarHide)
		                     ? NSControlStateValueOn
		                     : NSControlStateValueOff];
		[taskbarHideMenu addItem:posItem];
	}

	[taskbarHideMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *taskbarSettingsItem =
	    [[[NSMenuItem alloc] initWithTitle:@"Settings"
	                                action:(localSession ? @selector(showTaskbarSettingsFromMenuItem:)
	                                                      : @selector(remoteStatusCommandFromMenuItem:))
	                         keyEquivalent:@""] autorelease];
	[taskbarSettingsItem setTarget:self];
	if (!localSession)
		[taskbarSettingsItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
		                                                   session, @"session", @"taskbarSettings",
		                                                   @"command", nil]];
	[taskbarHideMenu addItem:taskbarSettingsItem];

	[taskbarHideItem setSubmenu:taskbarHideMenu];
	[menu addItem:taskbarHideItem];

	NSMenuItem *focusItem =
	    [[[NSMenuItem alloc] initWithTitle:@"Focus Session"
	                                 action:(localSession ? @selector(focusSessionFromMenuItem:)
	                                                       : @selector(remoteStatusCommandFromMenuItem:))
	                          keyEquivalent:@""] autorelease];
	[focusItem setTarget:self];
	if (!localSession)
		[focusItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
		                                              session, @"session", @"focus", @"command", nil]];
	[menu addItem:focusItem];

	if (includeQuit)
	{
		[menu addItem:[NSMenuItem separatorItem]];

		NSMenuItem *quitItem =
		    [[[NSMenuItem alloc] initWithTitle:@"Quit Session"
		                                 action:(localSession ? @selector(quitSessionFromMenuItem:)
		                                                       : @selector(remoteStatusCommandFromMenuItem:))
		                          keyEquivalent:@""] autorelease];
		[quitItem setTarget:self];
		if (!localSession)
			[quitItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
			                                             session, @"session", @"quit", @"command", nil]];
		[menu addItem:quitItem];
	}
}

- (void)remoteStatusCommandFromMenuItem:(NSMenuItem *)menuItem
{
	NSDictionary *info = [menuItem representedObject];
	NSDictionary *session = [info objectForKey:@"session"];
	NSString *command = [info objectForKey:@"command"];
	NSNumber *value = [info objectForKey:@"value"];

	[self postStatusCommand:command forSession:session value:value];
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

- (void)quitSessionFromMenuItem:(id)sender
{
	(void)sender;
	[NSApp terminate:self];
}

- (void)quitAllFromMenuItem:(id)sender
{
	(void)sender;
	NSNumber *localPID = [self localStatusSessionPID];

	for (NSDictionary *session in [statusSessions allValues])
	{
		if ([[session objectForKey:@"pid"] isEqualToNumber:localPID])
			continue;

		[self postStatusCommand:@"quit" forSession:session value:nil];
	}

	[NSApp terminate:self];
}

- (void)updateWindowDragTitlebarHeightPreviewFromSlider:(id)sender
{
	(void)sender;
	if (!context || !windowDragTitlebarHeightSlider)
		return;

	mfContext *mfc = (mfContext *)context;
	const NSInteger height = MIN(MAX((NSInteger)lround([windowDragTitlebarHeightSlider doubleValue]),
	                                 1),
	                             200);
	mfc->windowDragTitlebarHeight = (UINT32)height;
	[windowDragTitlebarHeightSlider setIntegerValue:height];
	if (windowDragTitlebarHeightValueLabel)
		[windowDragTitlebarHeightValueLabel
		    setStringValue:[NSString stringWithFormat:@"%ld px", (long)height]];
	if (mrdpView)
	{
		[mrdpView setWindowDragTitlebarPreviewVisible:YES];
		[mrdpView setNeedsDisplay:YES];
	}
}

- (void)showModifierKeyswapFilterFromButton:(NSButton *)sender
{
	(void)sender;
	if (!modifierKeyswapFilterField)
		return;

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Modifier Keyswap Filter"];
	[alert setInformativeText:@"Comma or newline-separated IP addresses. Leave empty to apply to all hosts."];
	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];

	NSTextField *filterInput = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
	[filterInput setStringValue:[modifierKeyswapFilterField stringValue]];
	[alert setAccessoryView:filterInput];

	if ([alert runModal] == NSAlertFirstButtonReturn)
		[modifierKeyswapFilterField setStringValue:[filterInput stringValue]];

	[filterInput release];
	[alert release];
}

- (void)showGeneralSettingsFromMenuItem:(id)sender
{
	(void)sender;
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Settings"];
	[alert setInformativeText:@"Choose modifier keyswap, window display behavior, drag titlebar height, chroma key color, and extra per-color transparency."];
	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];

	NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 286)];

	NSTextField *modifierKeyswapLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 256, 120, 20)];
	[modifierKeyswapLabel setStringValue:@"Modifier keyswap:"];
	[modifierKeyswapLabel setEditable:NO];
	[modifierKeyswapLabel setBezeled:NO];
	[modifierKeyswapLabel setDrawsBackground:NO];
	[accessoryView addSubview:modifierKeyswapLabel];

	NSPopUpButton *modifierKeyswapPopup =
	    [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 254, 170, 26) pullsDown:NO];
	[modifierKeyswapPopup addItemWithTitle:@"None"];
	[modifierKeyswapPopup addItemWithTitle:@"Apple to PC/Linux"];
	[modifierKeyswapPopup addItemWithTitle:@"PC/Linux to Apple"];
	[modifierKeyswapPopup selectItemAtIndex:MIN(MAX((NSInteger)mfc->modifierKeyswapMode, 0), 2)];
	[accessoryView addSubview:modifierKeyswapPopup];

	NSTextField *modifierKeyswapFilterInput =
	    [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
	[modifierKeyswapFilterInput setHidden:YES];
	[modifierKeyswapFilterInput setStringValue:mac_modifier_keyswap_filter_string(mfc)];
	[accessoryView addSubview:modifierKeyswapFilterInput];

	NSButton *modifierKeyswapFilterButton =
	    [[NSButton alloc] initWithFrame:NSMakeRect(304, 254, 56, 26)];
	[modifierKeyswapFilterButton setTitle:@"Filter"];
	[modifierKeyswapFilterButton setTarget:self];
	[modifierKeyswapFilterButton setAction:@selector(showModifierKeyswapFilterFromButton:)];
	[accessoryView addSubview:modifierKeyswapFilterButton];

	NSButton *shadowCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 222, 360, 20)];
	[shadowCheckbox setButtonType:NSButtonTypeSwitch];
	[shadowCheckbox setTitle:@"Enable Window Drop Shadows (Experimental)"];
	[shadowCheckbox setState:mfc->windowShadowsEnabled ? NSControlStateValueOn : NSControlStateValueOff];
	[accessoryView addSubview:shadowCheckbox];

	NSTextField *dragHeightLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 188, 120, 20)];
	[dragHeightLabel setStringValue:@"Drag Titlebar:"];
	[dragHeightLabel setEditable:NO];
	[dragHeightLabel setBezeled:NO];
	[dragHeightLabel setDrawsBackground:NO];
	[accessoryView addSubview:dragHeightLabel];

	NSSlider *dragHeightSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(130, 186, 160, 24)];
	[dragHeightSlider setMinValue:1.0];
	[dragHeightSlider setMaxValue:200.0];
	[dragHeightSlider setContinuous:YES];
	[dragHeightSlider setIntegerValue:(NSInteger)MIN(MAX(mfc->windowDragTitlebarHeight, 1), 200)];
	[dragHeightSlider setTarget:self];
	[dragHeightSlider setAction:@selector(updateWindowDragTitlebarHeightPreviewFromSlider:)];
	[accessoryView addSubview:dragHeightSlider];

	NSTextField *dragHeightValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(300, 188, 60, 20)];
	[dragHeightValueLabel
	    setStringValue:[NSString stringWithFormat:@"%u px", (unsigned int)MIN(MAX(mfc->windowDragTitlebarHeight, 1), 200)]];
	[dragHeightValueLabel setAlignment:NSTextAlignmentRight];
	[dragHeightValueLabel setEditable:NO];
	[dragHeightValueLabel setBezeled:NO];
	[dragHeightValueLabel setDrawsBackground:NO];
	[accessoryView addSubview:dragHeightValueLabel];

	NSButton *enableCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 152, 360, 20)];
	[enableCheckbox setButtonType:NSButtonTypeSwitch];
	[enableCheckbox setTitle:@"Enable Chroma Key Transparency"];
	[enableCheckbox setState:mfc->chromaKeyEnabled ? NSControlStateValueOn : NSControlStateValueOff];
	[accessoryView addSubview:enableCheckbox];

	NSButton *featherCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(18, 124, 342, 20)];
	[featherCheckbox setButtonType:NSButtonTypeSwitch];
	[featherCheckbox setTitle:@"Feather Chroma Key Window Corners"];
	[featherCheckbox setState:mfc->chromaKeyFeatheringEnabled ? NSControlStateValueOn
	                                                          : NSControlStateValueOff];
	[accessoryView addSubview:featherCheckbox];

	NSTextField *colorLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 92, 120, 20)];
	[colorLabel setStringValue:@"Chroma Key:"];
	[colorLabel setEditable:NO];
	[colorLabel setBezeled:NO];
	[colorLabel setDrawsBackground:NO];
	[accessoryView addSubview:colorLabel];

	NSTextField *colorInput = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 90, 100, 24)];
	[colorInput setStringValue:[NSString stringWithFormat:@"#%06X:%.0f",
	                                                       (unsigned int)(mfc->chromaKeyColor &
	                                                                      0xFFFFFF),
	                                                       mfc->chromaKeyTolerance]];
	[accessoryView addSubview:colorInput];

	NSTextField *additionalLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 58, 120, 20)];
	[additionalLabel setStringValue:@"Extra Colors:"];
	[additionalLabel setEditable:NO];
	[additionalLabel setBezeled:NO];
	[additionalLabel setDrawsBackground:NO];
	[accessoryView addSubview:additionalLabel];

	NSTextField *additionalInput = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 56, 230, 24)];
	[additionalInput setStringValue:mac_hex_alpha_list_string(mfc)];
	[accessoryView addSubview:additionalInput];

	NSTextField *hintLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 30, 230, 18)];
	[hintLabel setStringValue:@"Use #RRGGBB=alpha:tolerance:blur"];
	[hintLabel setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[hintLabel setTextColor:[NSColor secondaryLabelColor]];
	[hintLabel setEditable:NO];
	[hintLabel setBezeled:NO];
	[hintLabel setDrawsBackground:NO];
	[accessoryView addSubview:hintLabel];

	[alert setAccessoryView:accessoryView];

	const UINT32 originalDragTitlebarHeight = mfc->windowDragTitlebarHeight;
	windowDragTitlebarHeightSlider = dragHeightSlider;
	windowDragTitlebarHeightValueLabel = dragHeightValueLabel;
	modifierKeyswapFilterField = modifierKeyswapFilterInput;
	if (mrdpView)
		[mrdpView setWindowDragTitlebarPreviewVisible:YES];

	NSInteger result = [alert runModal];

	if (mrdpView)
		[mrdpView setWindowDragTitlebarPreviewVisible:NO];
	windowDragTitlebarHeightSlider = nil;
	windowDragTitlebarHeightValueLabel = nil;
	modifierKeyswapFilterField = nil;

	if (result == NSAlertFirstButtonReturn)
	{
		uint32_t colorVal = 0;
		float chromaTolerance = mfc->chromaKeyTolerance;
		uint32_t additionalColors[16] = { 0 };
		UINT32 additionalTransparencies[16] = { 0 };
		UINT32 additionalTolerances[16] = { 0 };
		BOOL additionalBlur[16] = { 0 };
		size_t additionalColorCount = 0;
		BOOL validColor = mac_parse_chroma_key_text([colorInput stringValue], &colorVal,
		                                            &chromaTolerance);
		BOOL validAdditionalColors =
		    mac_parse_hex_alpha_list([additionalInput stringValue], additionalColors,
		                             additionalTransparencies, additionalTolerances,
		                             additionalBlur,
		                             sizeof(additionalColors) / sizeof(additionalColors[0]),
		                             &additionalColorCount);

		if (validColor && validAdditionalColors)
		{
			mfc->windowShadowsEnabled = [shadowCheckbox state] == NSControlStateValueOn;
			mfc->windowDragTitlebarHeight =
			    (UINT32)MIN(MAX([dragHeightSlider integerValue], 1), 200);
			mfc->modifierKeyswapMode =
			    (MF_MODIFIER_KEYSWAP_MODE)MIN(MAX([modifierKeyswapPopup indexOfSelectedItem], 0), 2);
			mac_set_modifier_keyswap_filter(mfc, [modifierKeyswapFilterInput stringValue]);
			mfc->chromaKeyEnabled = [enableCheckbox state] == NSControlStateValueOn;
			mfc->chromaKeyFeatheringEnabled =
			    [featherCheckbox state] == NSControlStateValueOn;
			mfc->chromaKeyColor = colorVal & 0xFFFFFF;
			mfc->chromaKeyTolerance = chromaTolerance;
			mfc->additionalTransparencyColorCount = additionalColorCount;
			memcpy(mfc->additionalTransparencyColors, additionalColors,
			       additionalColorCount * sizeof(uint32_t));
			memcpy(mfc->additionalTransparencyLevels, additionalTransparencies,
			       additionalColorCount * sizeof(UINT32));
			memcpy(mfc->additionalTransparencyTolerances, additionalTolerances,
			       additionalColorCount * sizeof(UINT32));
			memcpy(mfc->additionalTransparencyBlur, additionalBlur,
			       additionalColorCount * sizeof(BOOL));

			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
			[defaults setBool:mfc->windowShadowsEnabled forKey:MRDPWindowShadowsEnabledKey];
			[defaults setInteger:(NSInteger)mfc->windowDragTitlebarHeight
			               forKey:MRDPWindowDragTitlebarHeightKey];
			[defaults setInteger:(NSInteger)mfc->modifierKeyswapMode
			               forKey:MRDPModifierKeyswapModeKey];
			[defaults setObject:mac_modifier_keyswap_filter_string(mfc)
			             forKey:MRDPModifierKeyswapFilterKey];
			[defaults setBool:mfc->chromaKeyEnabled forKey:MRDPChromaKeyEnabledKey];
			[defaults setBool:mfc->chromaKeyFeatheringEnabled
			           forKey:MRDPChromaKeyFeatheringEnabledKey];
			[defaults setInteger:(NSInteger)mfc->chromaKeyColor forKey:MRDPChromaKeyColorKey];
			[defaults setFloat:mfc->chromaKeyTolerance forKey:MRDPChromaKeyToleranceKey];
			[defaults setObject:mac_hex_color_number_array(mfc)
			             forKey:MRDPAdditionalTransparencyColorsKey];
			[defaults setObject:mac_transparency_number_array(mfc)
			             forKey:MRDPAdditionalTransparencyLevelsKey];
			[defaults setObject:mac_tolerance_number_array(mfc)
			             forKey:MRDPAdditionalTransparencyTolerancesKey];
			[defaults setObject:mac_blur_number_array(mfc)
			             forKey:MRDPAdditionalTransparencyBlurKey];
			[defaults synchronize];

			[self applyWindowDecorationsFromSettings];

			if (mrdpView)
				[mrdpView refreshBitmap];

			for (NSDictionary *session in [statusSessions allValues])
			{
				NSNumber *pid = [session objectForKey:@"pid"];
				if (!pid)
					continue;

				NSDictionary *info = [NSDictionary
				    dictionaryWithObjectsAndKeys:pid, @"pid", @"chroma", @"command",
				                                 @(mfc->chromaKeyEnabled), @"enabled",
				                                 @(mfc->chromaKeyFeatheringEnabled),
				                                 @"featheringEnabled",
				                                 @((NSInteger)mfc->chromaKeyColor), @"color",
				                                 @(mfc->chromaKeyTolerance), @"tolerance",
				                                 mac_hex_color_number_array(mfc),
				                                 @"additionalColors",
				                                 mac_transparency_number_array(mfc),
				                                 @"additionalTransparencies",
				                                 mac_tolerance_number_array(mfc),
				                                 @"additionalTolerances",
				                                 mac_blur_number_array(mfc),
				                                 @"additionalBlur", nil];
				[[NSDistributedNotificationCenter defaultCenter]
				    postNotificationName:MRDPStatusCommandNotification
				                  object:nil
				                userInfo:info
				      deliverImmediately:YES];

				info = [NSDictionary dictionaryWithObjectsAndKeys:pid, @"pid", @"windowShadows",
				                                                  @"command",
				                                                  @(mfc->windowShadowsEnabled),
				                                                  @"enabled", nil];
				[[NSDistributedNotificationCenter defaultCenter]
				    postNotificationName:MRDPStatusCommandNotification
				                  object:nil
				                userInfo:info
				      deliverImmediately:YES];

				info = [NSDictionary dictionaryWithObjectsAndKeys:
				                          pid, @"pid", @"windowDragTitlebarHeight", @"command",
				                          @(mfc->windowDragTitlebarHeight), @"height", nil];
				[[NSDistributedNotificationCenter defaultCenter]
				    postNotificationName:MRDPStatusCommandNotification
				                  object:nil
				                userInfo:info
				      deliverImmediately:YES];

				info = [NSDictionary dictionaryWithObjectsAndKeys:
				                          pid, @"pid", @"modifierKeyswap", @"command",
				                          @(mfc->modifierKeyswapMode), @"mode",
				                          mac_modifier_keyswap_filter_string(mfc), @"filter", nil];
				[[NSDistributedNotificationCenter defaultCenter]
				    postNotificationName:MRDPStatusCommandNotification
				                  object:nil
				                userInfo:info
				      deliverImmediately:YES];
			}
		}
		else
		{
			mfc->windowDragTitlebarHeight = originalDragTitlebarHeight;
			if (mrdpView)
				[mrdpView setNeedsDisplay:YES];
			NSBeep();
		}
	}
	else
	{
		mfc->windowDragTitlebarHeight = originalDragTitlebarHeight;
		if (mrdpView)
			[mrdpView setNeedsDisplay:YES];
	}

	[shadowCheckbox release];
	[modifierKeyswapLabel release];
	[modifierKeyswapPopup release];
	[modifierKeyswapFilterInput release];
	[modifierKeyswapFilterButton release];
	[dragHeightLabel release];
	[dragHeightSlider release];
	[dragHeightValueLabel release];
	[enableCheckbox release];
	[featherCheckbox release];
	[colorLabel release];
	[colorInput release];
	[additionalLabel release];
	[additionalInput release];
	[hintLabel release];
	[accessoryView release];
	[alert release];
}

- (void)setSpacerPositionFromMenuItem:(NSMenuItem *)menuItem
{
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;
	mfc->spacerPosition = (UINT32)[menuItem tag];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:(NSInteger)mfc->spacerPosition forKey:@"MRDPSpacerPosition"];
	[defaults synchronize];

	[self updateSpacerWindow];
	[self broadcastStatusSessionUpdate];
}

- (void)showSpacerSettingsFromMenuItem:(id)sender
{
	(void)sender;
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Spacer Settings"];
	[alert setInformativeText:@"Configure the spacer area that reserves screen space like the macOS Dock."];
	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];

	NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 80)];

	NSButton *enableCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 50, 300, 20)];
	[enableCheckbox setButtonType:NSButtonTypeSwitch];
	[enableCheckbox setTitle:@"Enable Spacer"];
	[enableCheckbox setState:mfc->spacerEnabled ? NSControlStateValueOn : NSControlStateValueOff];
	[accessoryView addSubview:enableCheckbox];

	NSTextField *sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 25, 80, 20)];
	[sizeLabel setStringValue:@"Size (px):"];
	[sizeLabel setEditable:NO];
	[sizeLabel setBezeled:NO];
	[sizeLabel setDrawsBackground:NO];
	[accessoryView addSubview:sizeLabel];

	NSTextField *sizeInput = [[NSTextField alloc] initWithFrame:NSMakeRect(85, 25, 60, 20)];
	[sizeInput setStringValue:[NSString stringWithFormat:@"%u", mfc->spacerSize]];
	[accessoryView addSubview:sizeInput];

	[alert setAccessoryView:accessoryView];

	NSInteger result = [alert runModal];

	if (result == NSAlertFirstButtonReturn)
	{
		mfc->spacerEnabled = [enableCheckbox state] == NSControlStateValueOn;
		NSInteger sizeVal = [sizeInput integerValue];
		mfc->spacerSize = (sizeVal > 0) ? (UINT32)sizeVal : 50;

		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults setBool:mfc->spacerEnabled forKey:@"MRDPSpacerEnabled"];
		[defaults setInteger:(NSInteger)mfc->spacerSize forKey:@"MRDPSpacerSize"];
		[defaults synchronize];

		[self updateSpacerWindow];
		[self broadcastStatusSessionUpdate];
	}

	[enableCheckbox release];
	[sizeLabel release];
	[sizeInput release];
	[accessoryView release];
	[alert release];
}

- (void)setTaskbarPositionFromMenuItem:(NSMenuItem *)menuItem
{
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;
	mfc->taskbarHidePosition = (UINT32)[menuItem tag];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:(NSInteger)mfc->taskbarHidePosition forKey:@"MRDPTaskbarHidePosition"];
	[defaults synchronize];

	[self syncTaskbarHideWindows];
	[self broadcastStatusSessionUpdate];
}

- (void)showTaskbarSettingsFromMenuItem:(id)sender
{
	(void)sender;
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;

	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Taskbar Settings"];
	[alert setInformativeText:@"Configure the taskbar area that is hidden when not interacting with it."];
	[alert addButtonWithTitle:@"OK"];
	[alert addButtonWithTitle:@"Cancel"];

	NSView *accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 80)];

	NSTextField *sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 50, 120, 20)];
	[sizeLabel setStringValue:@"Height/Width (px):"];
	[sizeLabel setEditable:NO];
	[sizeLabel setBezeled:NO];
	[sizeLabel setDrawsBackground:NO];
	[accessoryView addSubview:sizeLabel];

	NSTextField *sizeInput = [[NSTextField alloc] initWithFrame:NSMakeRect(125, 50, 60, 20)];
	[sizeInput setStringValue:[NSString stringWithFormat:@"%u", mfc->taskbarHideHeight]];
	[accessoryView addSubview:sizeInput];

	NSTextField *posLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 25, 120, 20)];
	[posLabel setStringValue:@"Position:"];
	[posLabel setEditable:NO];
	[posLabel setBezeled:NO];
	[posLabel setDrawsBackground:NO];
	[accessoryView addSubview:posLabel];

	NSPopUpButton *posDropdown = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(125, 20, 100, 25)];
	[posDropdown addItemsWithTitles:@[@"Top", @"Bottom", @"Left", @"Right"]];
	[posDropdown selectItemAtIndex:mfc->taskbarHidePosition];
	[accessoryView addSubview:posDropdown];

	[alert setAccessoryView:accessoryView];

	NSInteger result = [alert runModal];

	if (result == NSAlertFirstButtonReturn)
	{
		NSInteger sizeVal = [sizeInput integerValue];
		mfc->taskbarHideHeight = (sizeVal > 0 && sizeVal < 2048) ? (UINT32)sizeVal : 48;
		mfc->taskbarHidePosition = (UINT32)[posDropdown indexOfSelectedItem];

		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults setInteger:(NSInteger)mfc->taskbarHideHeight forKey:@"MRDPTaskbarHideHeight"];
		[defaults setInteger:(NSInteger)mfc->taskbarHidePosition forKey:@"MRDPTaskbarHidePosition"];
		[defaults synchronize];

		[self syncTaskbarHideWindows];
		[self broadcastStatusSessionUpdate];
	}

	[posDropdown release];
	[posLabel release];
	[sizeInput release];
	[sizeLabel release];
	[accessoryView release];
	[alert release];
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
	const BOOL multimon = settings && freerdp_settings_get_bool(settings, FreeRDP_UseMultimon);
	const BOOL useVisibleFrame = pseudoFullscreen;
	NSRect targetRect = useVisibleFrame ? [screen visibleFrame] : [screen frame];

	if (multimon)
		return;

	if (fullscreen && mrdpView && [mrdpView isInFullScreenMode])
		[mrdpView exitFullScreenModeWithOptions:nil];

	if (!fullscreen && !pseudoFullscreen)
	{
		NSRect frame = [window frame];
		NSRect visibleFrame = [screen visibleFrame];

		frame.origin.x = NSMinX(visibleFrame);
		frame.origin.y = NSMaxY(visibleFrame) - NSHeight(frame);
		[window setFrame:frame display:YES];
		[self syncMultimonWindows];
		[self focusClientWindow];
		[self broadcastStatusSessionUpdate];
		return;
	}

	[window setFrame:targetRect display:YES];

	if (settings)
	{
		const BOOL resizeRequested = [self requestRemoteResizeForScreen:screen];

		if (!resizeRequested && pseudoFullscreen)
			mac_maximize_window_minus_menubar(context, window, mrdpView);
	}

	if (fullscreen && mrdpView)
		[mrdpView enterFullScreenMode:screen withOptions:nil];

	[self syncMultimonWindows];
	[self focusClientWindow];
	[self broadcastStatusSessionUpdate];
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
	const BOOL multimon = freerdp_settings_get_bool(settings, FreeRDP_UseMultimon);

	if (freerdp_settings_get_bool(settings, FreeRDP_SmartSizing))
		return NO;

	if (multimon)
		return NO;

	if (!fullscreen && !pseudoFullscreen)
		return NO;

	if (!mfc->disp || !mfc->disp->SendMonitorLayout)
		return NO;

	DISPLAY_CONTROL_MONITOR_LAYOUT layout =
	    mac_display_layout_for_screen(screen, pseudoFullscreen, mfc);

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

- (NSString *)sessionMenuTitle
{
	NSString *target = [self credentialTarget];

	if ([target length] > 0)
		return target;

	if ([window title] && [[window title] length] > 0)
		return [window title];

	return @"Current Session";
}

- (NSArray *)runningMacFreeRDPApplications
{
	NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
	NSString *executablePath = [[[NSBundle mainBundle] executablePath] lastPathComponent];
	NSMutableArray *applications = [NSMutableArray array];

	for (NSRunningApplication *application in [[NSWorkspace sharedWorkspace] runningApplications])
	{
		BOOL matchesBundle = bundleIdentifier && [[application bundleIdentifier] isEqualToString:bundleIdentifier];
		BOOL matchesExecutable = executablePath &&
		                         [[[[application executableURL] path] lastPathComponent]
		                             isEqualToString:executablePath];

		if (matchesBundle || matchesExecutable)
			[applications addObject:application];
	}

	return applications;
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

- (void)loadChromaKeySettingsFromDefaults
{
	if (!context)
		return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	mfContext *mfc = (mfContext *)context;

	mfc->windowShadowsEnabled = [defaults boolForKey:MRDPWindowShadowsEnabledKey];
	if ([defaults objectForKey:MRDPWindowDragTitlebarHeightKey])
	{
		NSInteger height = [defaults integerForKey:MRDPWindowDragTitlebarHeightKey];
		mfc->windowDragTitlebarHeight = (UINT32)MIN(MAX(height, 1), 200);
	}
	if ([defaults objectForKey:MRDPModifierKeyswapModeKey])
	{
		NSInteger mode = [defaults integerForKey:MRDPModifierKeyswapModeKey];
		mfc->modifierKeyswapMode = (MF_MODIFIER_KEYSWAP_MODE)MIN(MAX(mode, 0), 2);
	}
	if ([defaults objectForKey:MRDPModifierKeyswapFilterKey])
		mac_set_modifier_keyswap_filter(mfc,
		                                [defaults stringForKey:MRDPModifierKeyswapFilterKey]);
	mfc->chromaKeyEnabled = [defaults boolForKey:MRDPChromaKeyEnabledKey];
	mfc->chromaKeyFeatheringEnabled =
	    [defaults boolForKey:MRDPChromaKeyFeatheringEnabledKey];
	if ([defaults objectForKey:MRDPChromaKeyColorKey])
		mfc->chromaKeyColor = (uint32_t)([defaults integerForKey:MRDPChromaKeyColorKey] & 0xFFFFFF);
	if ([defaults objectForKey:MRDPChromaKeyToleranceKey])
		mfc->chromaKeyTolerance = [defaults floatForKey:MRDPChromaKeyToleranceKey];
	if ([defaults objectForKey:MRDPAdditionalTransparencyColorsKey] &&
	    [defaults objectForKey:MRDPAdditionalTransparencyLevelsKey])
	{
		NSArray *tolerances = [defaults arrayForKey:MRDPAdditionalTransparencyTolerancesKey];
		NSArray *blur = [defaults arrayForKey:MRDPAdditionalTransparencyBlurKey];
		if (!tolerances)
			tolerances = [NSArray array];
		if (!blur)
			blur = [NSArray array];
		mac_set_additional_transparency_colors_from_arrays(
		    mfc, [defaults arrayForKey:MRDPAdditionalTransparencyColorsKey],
		    [defaults arrayForKey:MRDPAdditionalTransparencyLevelsKey], tolerances, blur);
	}
}

- (void)loadSpacerSettingsFromDefaults
{
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	mfc->spacerEnabled = [defaults boolForKey:@"MRDPSpacerEnabled"];
	NSInteger spacerPos = [defaults integerForKey:@"MRDPSpacerPosition"];
	mfc->spacerPosition = (spacerPos >= 0 && spacerPos <= 3) ? (UINT32)spacerPos : 2;
	NSInteger spacerSizeVal = [defaults integerForKey:@"MRDPSpacerSize"];
	mfc->spacerSize = (spacerSizeVal > 0) ? (UINT32)spacerSizeVal : 50;

	[self updateSpacerWindow];
}

- (void)loadTaskbarSettingsFromDefaults
{
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSInteger taskbarHeightVal = [defaults integerForKey:@"MRDPTaskbarHideHeight"];
	mfc->taskbarHideHeight = (taskbarHeightVal > 0 && taskbarHeightVal < 2048) ? (UINT32)taskbarHeightVal : 48;
	NSInteger taskbarPos = [defaults integerForKey:@"MRDPTaskbarHidePosition"];
	mfc->taskbarHidePosition = (taskbarPos >= 0 && taskbarPos <= 3) ? (UINT32)taskbarPos : 1;
}

- (void)updateSpacerWindow
{
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;

	if (mfc->spacerEnabled && mfc->spacerSize > 0)
	{
		[self showSpacerWindow];
		[self startSpacerEnforcement];
		[self enforceSpacerForWindows];
	}
	else
	{
		[self hideSpacerWindow];
		[self stopSpacerEnforcement];
	}
}

- (void)showSpacerWindow
{
	if (!context)
		return;

	mfContext *mfc = (mfContext *)context;
	NSScreen *screen = [self preferredScreen];
	if (!screen)
		screen = [NSScreen mainScreen];
	if (!screen)
		return;

	if (spacerWindow && [spacerWindow isVisible])
		[self hideSpacerWindow];

	NSRect screenFrame = [screen frame];
	NSRect spacerFrame;

	switch (mfc->spacerPosition)
	{
		case 0: // Top
			spacerFrame = NSMakeRect(NSMinX(screenFrame), NSMaxY(screenFrame) - mfc->spacerSize,
			                        NSWidth(screenFrame), mfc->spacerSize);
			break;
		case 1: // Bottom
			spacerFrame = NSMakeRect(NSMinX(screenFrame), NSMinY(screenFrame),
			                        NSWidth(screenFrame), mfc->spacerSize);
			break;
		case 2: // Left
			spacerFrame = NSMakeRect(NSMinX(screenFrame), NSMinY(screenFrame),
			                        mfc->spacerSize, NSHeight(screenFrame));
			break;
		case 3: // Right
		default:
			spacerFrame = NSMakeRect(NSMaxX(screenFrame) - mfc->spacerSize, NSMinY(screenFrame),
			                        mfc->spacerSize, NSHeight(screenFrame));
			break;
	}

	spacerWindow = [[NSWindow alloc] initWithContentRect:spacerFrame
	                                             styleMask:NSWindowStyleMaskBorderless
	                                               backing:NSBackingStoreBuffered
	                                                 defer:NO];
	[spacerWindow setLevel:NSFloatingWindowLevel];
	[spacerWindow setOpaque:NO];
	[spacerWindow setBackgroundColor:[NSColor clearColor]];
	[spacerWindow setIgnoresMouseEvents:YES];
	[spacerWindow setCanHide:NO];
	[spacerWindow setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces |
	                                     NSWindowCollectionBehaviorStationary |
	                                     NSWindowCollectionBehaviorFullScreenAuxiliary |
	                                     NSWindowCollectionBehaviorIgnoresCycle)];
	[spacerWindow orderFront:self];
}

- (void)hideSpacerWindow
{
	if (spacerWindow)
	{
		[spacerWindow orderOut:self];
		[spacerWindow release];
		spacerWindow = nil;
	}
}

- (void)startSpacerEnforcement
{
	if (spacerEnforcementTimer)
		return;

	if (!AXIsProcessTrusted())
	{
		const void *keys[] = { kAXTrustedCheckOptionPrompt };
		const void *values[] = { kCFBooleanTrue };
		CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
		                                             &kCFTypeDictionaryKeyCallBacks,
		                                             &kCFTypeDictionaryValueCallBacks);
		const Boolean trusted = AXIsProcessTrustedWithOptions(options);
		if (options)
			CFRelease(options);

		if (!trusted)
		{
			NSLog(@"Spacer window enforcement needs Accessibility permission.");
			return;
		}
	}

	spacerEnforcementTimer = [NSTimer scheduledTimerWithTimeInterval:0.35
	                                                          target:self
	                                                        selector:@selector(spacerEnforcementTimerFired:)
	                                                        userInfo:nil
	                                                         repeats:YES];
	[spacerEnforcementTimer setTolerance:0.1];
}

- (void)stopSpacerEnforcement
{
	if (!spacerEnforcementTimer)
		return;

	[spacerEnforcementTimer invalidate];
	spacerEnforcementTimer = nil;
}

- (void)spacerEnforcementTimerFired:(NSTimer *)timer
{
	if (timer != spacerEnforcementTimer)
		return;

	[self enforceSpacerForWindows];
}

- (void)enforceSpacerForWindows
{
	if (!context || !AXIsProcessTrusted())
		return;

	mfContext *mfc = (mfContext *)context;
	if (!mfc->spacerEnabled || mfc->spacerSize == 0)
		return;

	NSScreen *screen = [self preferredScreen];
	if (!screen)
		screen = [NSScreen mainScreen];
	if (!screen)
		return;

	CGRect spacerRect = mac_spacer_rect_for_screen(screen, mfc->spacerPosition, mfc->spacerSize);
	CGRect availableRect =
	    mac_available_rect_for_spacer(screen, mfc->spacerPosition, mfc->spacerSize);
	CFArrayRef windowInfo = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly,
	                                                  kCGNullWindowID);
	if (!windowInfo)
		return;

	const pid_t ownPid = [[NSProcessInfo processInfo] processIdentifier];
	NSMutableSet *macFreeRDPPids = [NSMutableSet set];
	for (NSRunningApplication *application in [self runningMacFreeRDPApplications])
		[macFreeRDPPids addObject:[NSNumber numberWithInt:[application processIdentifier]]];
	[macFreeRDPPids addObject:[NSNumber numberWithInt:ownPid]];

	NSMutableSet *processedPids = [NSMutableSet set];
	NSArray *windows = (NSArray *)windowInfo;

	for (NSDictionary *info in windows)
	{
		NSNumber *pidNumber = [info objectForKey:(NSString *)kCGWindowOwnerPID];
		NSNumber *layerNumber = [info objectForKey:(NSString *)kCGWindowLayer];
		NSDictionary *boundsDictionary = [info objectForKey:(NSString *)kCGWindowBounds];
		CGRect cgFrame = CGRectZero;

		if (!pidNumber || !layerNumber || [layerNumber integerValue] != 0 ||
		    !CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)boundsDictionary, &cgFrame))
			continue;
		if ([macFreeRDPPids containsObject:pidNumber] ||
		    !CGRectIntersectsRect(cgFrame, spacerRect))
			continue;
		if ([processedPids containsObject:pidNumber])
			continue;

		[processedPids addObject:pidNumber];

		AXUIElementRef appElement = AXUIElementCreateApplication([pidNumber intValue]);
		if (!appElement)
			continue;

		CFArrayRef axWindows = NULL;
		if (AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute,
		                                  (CFTypeRef *)&axWindows) == kAXErrorSuccess &&
		    axWindows)
		{
			const CFIndex count = CFArrayGetCount(axWindows);
			for (CFIndex index = 0; index < count; index++)
			{
				AXUIElementRef axWindow =
				    (AXUIElementRef)CFArrayGetValueAtIndex(axWindows, index);
				CGRect axFrame = CGRectZero;

				if (!mac_ax_get_window_frame(axWindow, &axFrame) ||
				    !CGRectIntersectsRect(axFrame, spacerRect))
					continue;

				CGRect target = axFrame;
				target.size.width = MIN(target.size.width, availableRect.size.width);
				target.size.height = MIN(target.size.height, availableRect.size.height);
				target.origin.x = MIN(MAX(target.origin.x, CGRectGetMinX(availableRect)),
				                      CGRectGetMaxX(availableRect) - target.size.width);
				target.origin.y = MIN(MAX(target.origin.y, CGRectGetMinY(availableRect)),
				                      CGRectGetMaxY(availableRect) - target.size.height);

				mac_ax_set_window_frame(axWindow, target);
			}

			CFRelease(axWindows);
		}

		CFRelease(appElement);
	}

	CFRelease(windowInfo);
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
		else if (strcmp(context->argv[j], "/taskbar-hide") == 0 ||
		         strcmp(context->argv[j], "-taskbar-hide") == 0 ||
		         strcmp(context->argv[j], "--taskbar-hide") == 0)
		{
			mfc->taskbarHide = TRUE;
			mfc->taskbarHidePosition = 1; // default: bottom
		}
		else
		{
			char *value = NULL;

			if (strncmp(context->argv[j], "/taskbar-hide:", 14) == 0)
				value = context->argv[j] + 14;
			else if (strncmp(context->argv[j], "-taskbar-hide:", 14) == 0)
				value = context->argv[j] + 14;
			else if (strncmp(context->argv[j], "--taskbar-hide:", 15) == 0)
				value = context->argv[j] + 15;

			if (value && mac_parse_taskbar_hide_options(value, mfc))
			{
				*(value - 1) = '\0';
			}
			else
			{
				if (strncmp(context->argv[j], "/smart-sizing:", 14) == 0)
					value = context->argv[j] + 14;
				else if (strncmp(context->argv[j], "-smart-sizing:", 14) == 0)
					value = context->argv[j] + 14;
				else if (strncmp(context->argv[j], "--smart-sizing:", 15) == 0)
					value = context->argv[j] + 15;
				else
					value = NULL;

				if (value && mac_parse_smart_sizing_options(value, mfc))
					*(value - 1) = '\0';

				context->argv[filtered_argc++] = context->argv[j];
			}
		}
	}

	context->argc = filtered_argc;
	status = freerdp_client_settings_parse_command_line(context->settings, context->argc,
	                                                    context->argv, FALSE);
	freerdp_client_settings_command_line_status_print(context->settings, status, context->argc,
	                                                  context->argv);

	return status;
}

static BOOL mac_parse_smart_sizing_alignment(const char *value, MF_SMART_SIZING_ALIGN *alignment)
{
	if (!value || !alignment)
		return FALSE;

	if (_stricmp(value, "top") == 0)
		*alignment = MF_SMART_SIZING_ALIGN_TOP;
	else if (_stricmp(value, "bottom") == 0)
		*alignment = MF_SMART_SIZING_ALIGN_BOTTOM;
	else if (_stricmp(value, "left") == 0)
		*alignment = MF_SMART_SIZING_ALIGN_LEFT;
	else if (_stricmp(value, "right") == 0)
		*alignment = MF_SMART_SIZING_ALIGN_RIGHT;
	else
		return FALSE;

	return TRUE;
}

static BOOL mac_parse_smart_sizing_options(const char *value, mfContext *mfc)
{
	if (!value || !mfc)
		return FALSE;

	char *copy = _strdup(value);
	if (!copy)
		return FALSE;

	BOOL parsed = FALSE;
	BOOL expectOverscanAlignment = FALSE;

	for (char *token = strtok(copy, ":"); token; token = strtok(NULL, ":"))
	{
		MF_SMART_SIZING_ALIGN alignment = MF_SMART_SIZING_ALIGN_CENTER;

		if (_stricmp(token, "overscan") == 0)
		{
			mfc->smart_sizing_overscan = TRUE;
			expectOverscanAlignment = TRUE;
			parsed = TRUE;
			continue;
		}

		if (!mac_parse_smart_sizing_alignment(token, &alignment))
		{
			free(copy);
			return FALSE;
		}

		if (expectOverscanAlignment)
		{
			mfc->smart_sizing_overscan_align = alignment;
			expectOverscanAlignment = FALSE;
		}
		else
		{
			mfc->smart_sizing_align = alignment;
		}

		parsed = TRUE;
	}

	free(copy);
	return parsed;
}

static BOOL mac_parse_taskbar_hide_options(const char *value, mfContext *mfc)
{
	if (!value || !mfc)
		return FALSE;

	char *copy = _strdup(value);
	if (!copy)
		return FALSE;

	BOOL parsed = FALSE;
	BOOL hasHeight = FALSE;
	BOOL hasPosition = FALSE;
	UINT32 height = 48;
	UINT32 position = 1; // default: bottom

	for (char *token = strtok(copy, ":"); token; token = strtok(NULL, ":"))
	{
		NSString *tokenStr = [NSString stringWithUTF8String:token];
		NSString *lowerToken = [tokenStr lowercaseString];

		if ([lowerToken isEqualToString:@"top"])
		{
			position = 0;
			hasPosition = TRUE;
			parsed = TRUE;
		}
		else if ([lowerToken isEqualToString:@"bottom"])
		{
			position = 1;
			hasPosition = TRUE;
			parsed = TRUE;
		}
		else if ([lowerToken isEqualToString:@"left"])
		{
			position = 2;
			hasPosition = TRUE;
			parsed = TRUE;
		}
		else if ([lowerToken isEqualToString:@"right"])
		{
			position = 3;
			hasPosition = TRUE;
			parsed = TRUE;
		}
		else if (!hasHeight && !hasPosition)
		{
			int val = atoi(token);
			if (val > 0 && val < 2048)
			{
				height = (UINT32)val;
				hasHeight = TRUE;
				parsed = TRUE;
			}
			else
			{
				free(copy);
				return FALSE;
			}
		}
		else
		{
			free(copy);
			return FALSE;
		}
	}

	mfc->taskbarHide = TRUE;
	mfc->taskbarHideHeight = height;
	mfc->taskbarHidePosition = position;

	free(copy);
	return parsed;
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
					if (!mac_multimon_enabled(context->settings))
						[_singleDelegate moveSessionToScreen:screen screenIndex:screenIndex];
					[_singleDelegate syncMultimonWindows];
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
	const BOOL smartSizing = freerdp_settings_get_bool(context->settings, FreeRDP_SmartSizing);
	const BOOL multimon = mac_multimon_enabled(context->settings);
	// set client area to specified dimensions
	NSRect innerRect;
	innerRect.origin.x = 0;
	innerRect.origin.y = 0;
	innerRect.size.width = smartSizing ?
	    freerdp_settings_get_uint32(context->settings, FreeRDP_SmartSizingWidth) :
	    0;
	innerRect.size.height = smartSizing ?
	    freerdp_settings_get_uint32(context->settings, FreeRDP_SmartSizingHeight) :
	    0;

	if ((innerRect.size.width <= 0) || (innerRect.size.height <= 0))
	{
		innerRect.size.width = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth);
		innerRect.size.height = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopHeight);
	}

	NSRect viewRect = innerRect;
	NSArray *slices = multimon ? mac_multimon_slices(context->settings, mfc) : nil;
	NSDictionary *primarySlice = ([slices count] > 0) ? [slices objectAtIndex:0] : nil;
	if (primarySlice && !smartSizing)
	{
		NSValue *sourceValue = [primarySlice objectForKey:@"source"];
		if (sourceValue)
		{
			NSRect sourceRect = [sourceValue rectValue];
			viewRect.origin.x = -NSMinX(sourceRect);
			viewRect.origin.y = -(freerdp_settings_get_uint32(context->settings,
			                                                  FreeRDP_DesktopHeight) -
			                      NSMaxY(sourceRect));
		}
	}

	[view setFrame:viewRect];
	[view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	// calculate window of same size, but keep position
	NSRect outerRect = [window frame];
	if (primarySlice && !smartSizing)
	{
		NSValue *frameValue = [primarySlice objectForKey:@"frame"];
		NSRect contentRect = frameValue ? [frameValue rectValue] : NSZeroRect;
		outerRect = !NSIsEmptyRect(contentRect) ? contentRect
		                                        : [window frameRectForContentRect:innerRect];
		[window setCollectionBehavior:NSWindowCollectionBehaviorDefault];
	}
	else
	{
		outerRect.size = [window frameRectForContentRect:innerRect].size;
	}
	// we are not in RemoteApp mode, disable larger than resolution
	[window setContentMaxSize:(smartSizing || multimon) ? NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)
	                                                     : innerRect.size];
	// set window to given area
	[window setFrame:outerRect display:YES];
	if (primarySlice && !smartSizing)
	{
		[window setFrame:mac_constrain_window_frame_to_screen(
		                     [window frame], [primarySlice objectForKey:@"screen"],
		                     freerdp_settings_get_bool(context->settings, FreeRDP_Decorations))
		          display:YES];
	}

	if ((mfc->fullscreen_mode == 2) && [view is_connected])
	{
		mac_maximize_window_minus_menubar(context, window, view);
	}
	else if (!freerdp_settings_get_bool(context->settings, FreeRDP_Decorations) &&
	    !freerdp_settings_get_bool(context->settings, FreeRDP_Fullscreen) && !multimon)
	{
		mac_position_window_top_left(window);
	}

	if (_singleDelegate)
		[_singleDelegate syncMultimonWindows];

	// set window to front
	[NSApp activateIgnoringOtherApps:YES];

	if ([view is_connected] && !multimon &&
	    freerdp_settings_get_bool(context->settings, FreeRDP_Fullscreen) &&
	    mfc->fullscreen_mode != 2 &&
	    view && screen && ![view isInFullScreenMode])
	{
		[view enterFullScreenMode:screen withOptions:nil];
		mac_fit_view_to_window_content(context, view);
	}
}

static BOOL mac_screen_is_selected_for_settings(rdpSettings *settings, UINT32 screenIndex)
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

static BOOL mac_multimon_enabled(rdpSettings *settings)
{
	return settings && freerdp_settings_get_bool(settings, FreeRDP_UseMultimon);
}

static NSArray *mac_taskbar_single_monitor_slices(rdpSettings *settings, mfContext *mfc,
                                                  NSWindow *window)
{
	if (!settings || !mfc || !mac_taskbar_hide_enabled(mfc))
		return nil;

	const UINT32 desktopWidth = freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);
	const UINT32 desktopHeight = freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);
	if ((desktopWidth == 0) || (desktopHeight == 0))
		return nil;

	NSScreen *screen = mac_preferred_screen(window);
	if (!screen)
		screen = [NSScreen mainScreen];
	if (!screen)
		return nil;

	NSRect frame = [window frame];
	if (mfc->fullscreen_mode == 2)
		frame = mac_safe_multimon_window_frame(
		    screen, freerdp_settings_get_bool(settings, FreeRDP_Decorations));

	return [NSArray arrayWithObject:@{
		@"screen" : screen,
		@"frame" : [NSValue valueWithRect:frame],
		@"source" : [NSValue valueWithRect:NSMakeRect(0, 0, desktopWidth, desktopHeight)]
	}];
}

static BOOL mac_taskbar_hide_enabled(mfContext *mfc)
{
	if (!mfc || !mfc->common.context.settings || !mfc->taskbarHide)
		return FALSE;

	rdpSettings *settings = mfc->common.context.settings;
	const BOOL multimon = freerdp_settings_get_bool(settings, FreeRDP_UseMultimon);
	const BOOL fullscreen = freerdp_settings_get_bool(settings, FreeRDP_Fullscreen);
	const BOOL pseudoFullscreen = (mfc->fullscreen_mode == 2);
	return !freerdp_settings_get_bool(settings, FreeRDP_Decorations) &&
	       (multimon || !fullscreen || pseudoFullscreen) &&
	       (mfc->taskbarHideHeight > 0);
}

static BOOL mac_taskbar_uses_extended_canvas(mfContext *mfc)
{
	return mfc && mfc->taskbarHide && (mfc->fullscreen_mode == 2);
}

static CGFloat mac_taskbar_hide_size(mfContext *mfc, NSRect source)
{
	if (!mfc)
		return 0.0;

	const UINT32 position = mfc->taskbarHidePosition;
	const CGFloat limit = (position == 0 || position == 1) ? NSHeight(source) : NSWidth(source);
	return MIN((CGFloat)mfc->taskbarHideHeight, MAX(0.0, limit - 1.0));
}

static NSRect mac_remote_frame_with_taskbar(NSRect frame, mfContext *mfc)
{
	if (!mfc || !mfc->taskbarHide || (mfc->fullscreen_mode != 2))
		return frame;

	const CGFloat size = mac_taskbar_hide_size(mfc, frame);
	if (size <= 0.0)
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

static NSRect mac_taskbar_visible_frame(NSRect frame, UINT32 position, CGFloat size)
{
	if (size <= 0.0)
		return frame;

	if (position == 0)
		frame.size.height = MAX(1.0, frame.size.height - size);
	else if (position == 1)
	{
		frame.origin.y += size;
		frame.size.height = MAX(1.0, frame.size.height - size);
	}
	else if (position == 2)
	{
		frame.origin.x += size;
		frame.size.width = MAX(1.0, frame.size.width - size);
	}
	else if (position == 3)
		frame.size.width = MAX(1.0, frame.size.width - size);

	return frame;
}

static NSRect mac_taskbar_visible_source(NSRect source, UINT32 position, CGFloat size)
{
	if (size <= 0.0)
		return source;

	if (position == 0)
	{
		source.origin.y += size;
		source.size.height = MAX(1.0, source.size.height - size);
	}
	else if (position == 1)
		source.size.height = MAX(1.0, source.size.height - size);
	else if (position == 2)
	{
		source.origin.x += size;
		source.size.width = MAX(1.0, source.size.width - size);
	}
	else if (position == 3)
		source.size.width = MAX(1.0, source.size.width - size);

	return source;
}

static NSRect mac_taskbar_full_frame(NSRect frame, UINT32 position, CGFloat size)
{
	if (size <= 0.0)
		return frame;

	if (position == 0)
		frame.size.height += size;
	else if (position == 1)
	{
		frame.origin.y -= size;
		frame.size.height += size;
	}
	else if (position == 2)
	{
		frame.origin.x -= size;
		frame.size.width += size;
	}
	else if (position == 3)
		frame.size.width += size;

	return frame;
}

static BOOL mac_taskbar_mouse_should_reveal(NSPoint mouse, NSRect taskbarFrame)
{
	if (NSIsEmptyRect(taskbarFrame))
		return FALSE;

	const CGFloat edgeTolerance = 2.0;
	const CGFloat horizontalPadding = 8.0;
	const CGFloat verticalPadding = 8.0;
	const BOOL onHorizontalEdge =
	    ((mouse.y >= NSMinY(taskbarFrame)) && (mouse.y <= NSMinY(taskbarFrame) + edgeTolerance)) ||
	    ((mouse.y <= NSMaxY(taskbarFrame)) && (mouse.y >= NSMaxY(taskbarFrame) - edgeTolerance));
	const BOOL onVerticalEdge =
	    ((mouse.x >= NSMinX(taskbarFrame)) && (mouse.x <= NSMinX(taskbarFrame) + edgeTolerance)) ||
	    ((mouse.x <= NSMaxX(taskbarFrame)) && (mouse.x >= NSMaxX(taskbarFrame) - edgeTolerance));
	const BOOL withinSessionWidth = (mouse.x >= NSMinX(taskbarFrame) - horizontalPadding) &&
	                                (mouse.x <= NSMaxX(taskbarFrame) + horizontalPadding);
	const BOOL withinSessionHeight = (mouse.y >= NSMinY(taskbarFrame) - verticalPadding) &&
	                                 (mouse.y <= NSMaxY(taskbarFrame) + verticalPadding);

	return (onHorizontalEdge && withinSessionWidth) || (onVerticalEdge && withinSessionHeight);
}

static NSRect mac_safe_multimon_window_frame(NSScreen *screen, BOOL decorated)
{
	(void)decorated;

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
	{
		const CGFloat delta = NSMaxY(safeFrame) - safeMaxY;
		safeFrame.size.height = MAX(1.0, safeFrame.size.height - delta);
	}

	if (NSHeight(safeFrame) > (safeMaxY - NSMinY(safeFrame)))
		safeFrame.size.height = MAX(1.0, safeMaxY - NSMinY(safeFrame));

	return safeFrame;
}

static NSRect mac_constrain_window_frame_to_screen(NSRect frame, NSScreen *screen, BOOL decorated)
{
	NSRect safeFrame = mac_safe_multimon_window_frame(screen, decorated);
	if (!screen || NSIsEmptyRect(safeFrame))
		return frame;

	if (NSWidth(frame) > NSWidth(safeFrame))
		frame.size.width = NSWidth(safeFrame);
	if (NSHeight(frame) > NSHeight(safeFrame))
		frame.size.height = NSHeight(safeFrame);

	if (NSMaxX(frame) > NSMaxX(safeFrame))
		frame.origin.x -= NSMaxX(frame) - NSMaxX(safeFrame);
	if (NSMinX(frame) < NSMinX(safeFrame))
		frame.origin.x = NSMinX(safeFrame);

	if (NSMaxY(frame) > NSMaxY(safeFrame))
		frame.origin.y -= NSMaxY(frame) - NSMaxY(safeFrame);
	if (NSMinY(frame) < NSMinY(safeFrame))
		frame.origin.y = NSMinY(safeFrame);

	return frame;
}

static NSArray *mac_multimon_slices(rdpSettings *settings, mfContext *mfc)
{
	if (!mac_multimon_enabled(settings))
		return nil;

	NSArray *screens = [NSScreen screens];
	const NSUInteger screenCount = [screens count];
	NSMutableArray *rawSlices = [NSMutableArray array];
	const BOOL decorated = freerdp_settings_get_bool(settings, FreeRDP_Decorations);
	CGFloat minX = 0;
	CGFloat minY = 0;
	CGFloat maxX = 0;
	CGFloat maxY = 0;
	BOOL found = FALSE;

	for (NSUInteger i = 0; i < screenCount; i++)
	{
		if (!mac_screen_is_selected_for_settings(settings, (UINT32)i))
			continue;

		NSScreen *screen = [screens objectAtIndex:i];
		NSRect visibleFrame = mac_safe_multimon_window_frame(screen, decorated);
		NSRect remoteFrame = mac_remote_frame_with_taskbar(visibleFrame, mfc);
		NSRect remoteRect = NSMakeRect(NSMinX(remoteFrame), -NSMaxY(remoteFrame),
		                               NSWidth(remoteFrame), NSHeight(remoteFrame));
		if (!found)
		{
			minX = NSMinX(remoteRect);
			minY = NSMinY(remoteRect);
			maxX = NSMaxX(remoteRect);
			maxY = NSMaxY(remoteRect);
			found = TRUE;
		}
		else
		{
			minX = MIN(minX, NSMinX(remoteRect));
			minY = MIN(minY, NSMinY(remoteRect));
			maxX = MAX(maxX, NSMaxX(remoteRect));
			maxY = MAX(maxY, NSMaxY(remoteRect));
		}

		[rawSlices addObject:@{
			@"screen" : screen,
			@"frame" : [NSValue valueWithRect:visibleFrame],
			@"remote" : [NSValue valueWithRect:remoteRect]
		}];
	}

	if ([rawSlices count] == 0)
		return nil;

	NSMutableArray *slices = [NSMutableArray arrayWithCapacity:[rawSlices count]];
	for (NSDictionary *slice in rawSlices)
	{
		NSRect remoteRect = [[slice objectForKey:@"remote"] rectValue];
		NSRect sourceRect = NSMakeRect(NSMinX(remoteRect) - minX,
		                               NSMinY(remoteRect) - minY,
		                               NSWidth(remoteRect), NSHeight(remoteRect));
		[slices addObject:@{
			@"screen" : [slice objectForKey:@"screen"],
			@"frame" : [slice objectForKey:@"frame"],
			@"source" : [NSValue valueWithRect:sourceRect]
		}];
	}

	return slices;
}

static BOOL mac_multimon_content_rect(rdpSettings *settings, NSRect *rect)
{
	if (!settings || !rect)
		return FALSE;

	NSArray *screens = [NSScreen screens];
	const NSUInteger screenCount = [screens count];
	BOOL found = FALSE;
	NSRect unionRect = NSZeroRect;

	for (NSUInteger i = 0; i < screenCount; i++)
	{
		if (!mac_screen_is_selected_for_settings(settings, (UINT32)i))
			continue;

		NSRect frame = [[screens objectAtIndex:i] frame];
		unionRect = found ? NSUnionRect(unionRect, frame) : frame;
		found = TRUE;
	}

	if (!found)
		return FALSE;

	*rect = unionRect;
	return TRUE;
}

static void mac_fit_view_to_window_content(rdpContext *context, MRDPView *view)
{
	if (!context || !context->settings || !view ||
	    !freerdp_settings_get_bool(context->settings, FreeRDP_SmartSizing))
		return;

	NSView *contentView = [[view window] contentView];
	if (!contentView)
		return;

	NSRect bounds = [contentView bounds];
	if ((NSWidth(bounds) <= 0) || (NSHeight(bounds) <= 0))
		return;

	mfContext *mfc = (mfContext *)context;
	[view setFrame:bounds];
	[view setNeedsDisplay:YES];
	mfc->client_width = (int)NSWidth(bounds);
	mfc->client_height = (int)NSHeight(bounds);
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

static void mac_maximize_window_minus_menubar(rdpContext *context, NSWindow *window, MRDPView *view)
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
	mac_fit_view_to_window_content(context, view);
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

static CGRect mac_ax_rect_for_screen_rect(NSScreen *screen, NSRect rect)
{
	if (!screen)
		return CGRectZero;

	NSNumber *screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
	const CGDirectDisplayID displayId = screenNumber ? [screenNumber unsignedIntValue] : 0;
	const CGRect displayBounds = displayId ? CGDisplayBounds(displayId) : CGRectZero;
	const NSRect screenFrame = [screen frame];

	if (CGRectIsEmpty(displayBounds) || NSIsEmptyRect(screenFrame))
		return CGRectZero;

	return CGRectMake(CGRectGetMinX(displayBounds) + (NSMinX(rect) - NSMinX(screenFrame)),
	                  CGRectGetMinY(displayBounds) + (NSMaxY(screenFrame) - NSMaxY(rect)),
	                  NSWidth(rect), NSHeight(rect));
}

static CGRect mac_spacer_rect_for_screen(NSScreen *screen, UINT32 position, UINT32 size)
{
	if (!screen || size == 0)
		return CGRectZero;

	CGRect screenRect = mac_ax_rect_for_screen_rect(screen, [screen frame]);
	const CGFloat spacerSize = (CGFloat)size;

	switch (position)
	{
		case 0: // Top
			return CGRectMake(CGRectGetMinX(screenRect), CGRectGetMinY(screenRect),
			                  CGRectGetWidth(screenRect), spacerSize);
		case 1: // Bottom
			return CGRectMake(CGRectGetMinX(screenRect),
			                  CGRectGetMaxY(screenRect) - spacerSize,
			                  CGRectGetWidth(screenRect), spacerSize);
		case 2: // Left
			return CGRectMake(CGRectGetMinX(screenRect), CGRectGetMinY(screenRect), spacerSize,
			                  CGRectGetHeight(screenRect));
		case 3: // Right
		default:
			return CGRectMake(CGRectGetMaxX(screenRect) - spacerSize, CGRectGetMinY(screenRect),
			                  spacerSize, CGRectGetHeight(screenRect));
	}
}

static CGRect mac_available_rect_for_spacer(NSScreen *screen, UINT32 position, UINT32 size)
{
	if (!screen)
		return CGRectZero;

	CGRect available = mac_ax_rect_for_screen_rect(screen, [screen visibleFrame]);
	const CGFloat spacerSize = (CGFloat)size;

	switch (position)
	{
		case 0: // Top
			available.origin.y += spacerSize;
			available.size.height -= spacerSize;
			break;
		case 1: // Bottom
			available.size.height -= spacerSize;
			break;
		case 2: // Left
			available.origin.x += spacerSize;
			available.size.width -= spacerSize;
			break;
		case 3: // Right
		default:
			available.size.width -= spacerSize;
			break;
	}

	if (available.size.width < 1.0)
		available.size.width = 1.0;
	if (available.size.height < 1.0)
		available.size.height = 1.0;

	return available;
}

static BOOL mac_ax_get_window_frame(AXUIElementRef windowElement, CGRect *frame)
{
	if (!windowElement || !frame)
		return NO;

	CFTypeRef positionValue = NULL;
	CFTypeRef sizeValue = NULL;
	CGPoint position = CGPointZero;
	CGSize size = CGSizeZero;

	if (AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute, &positionValue) !=
	        kAXErrorSuccess ||
	    !positionValue)
		return NO;

	if (AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute, &sizeValue) !=
	        kAXErrorSuccess ||
	    !sizeValue)
	{
		CFRelease(positionValue);
		return NO;
	}

	const BOOL ok = AXValueGetValue((AXValueRef)positionValue, kAXValueCGPointType, &position) &&
	                AXValueGetValue((AXValueRef)sizeValue, kAXValueCGSizeType, &size);

	CFRelease(positionValue);
	CFRelease(sizeValue);

	if (!ok || size.width <= 0.0 || size.height <= 0.0)
		return NO;

	*frame = CGRectMake(position.x, position.y, size.width, size.height);
	return YES;
}

static void mac_ax_set_window_frame(AXUIElementRef windowElement, CGRect frame)
{
	if (!windowElement)
		return;

	Boolean canSetPosition = false;
	Boolean canSetSize = false;
	CGPoint position = frame.origin;
	CGSize size = frame.size;
	AXValueRef positionValue = AXValueCreate(kAXValueCGPointType, &position);
	AXValueRef sizeValue = AXValueCreate(kAXValueCGSizeType, &size);

	if (!positionValue || !sizeValue)
	{
		if (positionValue)
			CFRelease(positionValue);
		if (sizeValue)
			CFRelease(sizeValue);
		return;
	}

	if (AXUIElementIsAttributeSettable(windowElement, kAXSizeAttribute, &canSetSize) ==
	        kAXErrorSuccess &&
	    canSetSize)
		(void)AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute, sizeValue);

	if (AXUIElementIsAttributeSettable(windowElement, kAXPositionAttribute, &canSetPosition) ==
	        kAXErrorSuccess &&
	    canSetPosition)
		(void)AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute, positionValue);

	CFRelease(positionValue);
	CFRelease(sizeValue);
}

static DISPLAY_CONTROL_MONITOR_LAYOUT mac_display_layout_for_screen(NSScreen *screen,
	                                                               BOOL useVisibleFrame,
	                                                               mfContext *mfc)
{
	DISPLAY_CONTROL_MONITOR_LAYOUT layout = { 0 };
	NSRect frame = useVisibleFrame ? [screen visibleFrame] : [screen frame];
	frame = mac_remote_frame_with_taskbar(frame, mfc);
	NSNumber *screenNumber = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
	const CGDirectDisplayID displayId = screenNumber ? [screenNumber unsignedIntValue] : 0;
	CGSize physicalSize = displayId ? CGDisplayScreenSize(displayId) : CGSizeZero;
	rdpSettings *settings = mfc ? mfc->common.context.settings : NULL;

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
	    settings ? freerdp_settings_get_uint32(settings, FreeRDP_DesktopScaleFactor) : 100;
	layout.DeviceScaleFactor = settings ? freerdp_settings_get_uint32(settings, FreeRDP_DeviceScaleFactor) : 100;

	if (layout.DesktopScaleFactor == 0)
		layout.DesktopScaleFactor = 100;
	if (layout.DeviceScaleFactor == 0)
		layout.DeviceScaleFactor = 100;

	return layout;
}
