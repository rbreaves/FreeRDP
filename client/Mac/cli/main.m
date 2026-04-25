#import <Cocoa/Cocoa.h>
#include <freerdp/client/cmdline.h>
#import "AppDelegate.h"

int main(int argc, char *argv[])
{
	freerdp_client_warn_deprecated(argc, argv);
	for (int i = 0; i < argc; i++)
	{
		char *ctemp = argv[i];
		if (memcmp(ctemp, "/p:", 3) == 0 || memcmp(ctemp, "-p:", 3) == 0)
		{
			memset(ctemp + 3, '*', strlen(ctemp) - 3);
		}
	}

	NSApplication *app = [NSApplication sharedApplication];
	[app setActivationPolicy:NSApplicationActivationPolicyRegular];
	AppDelegate *delegate = [[AppDelegate alloc] init];
	[app setDelegate:delegate];
	[NSApp activateIgnoringOtherApps:YES];
	[app run];
	return 0;
}
