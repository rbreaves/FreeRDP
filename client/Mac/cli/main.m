#import <Cocoa/Cocoa.h>
#include <freerdp/client/cmdline.h>
#import "AppDelegate.h"
#include <string.h>

static BOOL mac_no_dock_requested(int argc, char *argv[])
{
	for (int i = 1; i < argc; i++)
	{
		if ((strcmp(argv[i], "-no-dock") == 0) || (strcmp(argv[i], "--no-dock") == 0))
			return YES;
	}

	return NO;
}

int main(int argc, char *argv[])
{
	freerdp_client_warn_deprecated(argc, argv);
	const BOOL noDock = mac_no_dock_requested(argc, argv);
	for (int i = 0; i < argc; i++)
	{
		char *ctemp = argv[i];
		if (memcmp(ctemp, "/p:", 3) == 0 || memcmp(ctemp, "-p:", 3) == 0)
		{
			memset(ctemp + 3, '*', strlen(ctemp) - 3);
		}
	}

	NSApplication *app = [NSApplication sharedApplication];
	[app setActivationPolicy:noDock ? NSApplicationActivationPolicyAccessory
	                                : NSApplicationActivationPolicyRegular];
	AppDelegate *delegate = [[AppDelegate alloc] init];
	[app setDelegate:delegate];
	[NSApp activateIgnoringOtherApps:YES];
	[app run];
	return 0;
}
