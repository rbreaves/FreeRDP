/**
 * FreeRDP: A Remote Desktop Protocol Implementation
 * MacFreeRDP
 *
 * Copyright 2013 Christian Hofstaedtler
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

#import "PasswordDialog.h"
#import <freerdp/client/cmdline.h>

#import <CoreGraphics/CoreGraphics.h>

@interface PasswordDialog ()

@property BOOL modalCode;
- (void)createUI;

@end

@implementation PasswordDialog

@synthesize usernameText;
@synthesize passwordText;
@synthesize domainText;
@synthesize messageLabel;
@synthesize serverHostname;
@synthesize username;
@synthesize password;
@synthesize domain;
@synthesize modalCode;

- (id)init
{
	self = [super init];
	if (self)
	{
		dispatch_sync(dispatch_get_main_queue(), ^{
			[self createUI];
		});
	}
	return self;
}

- (void)createUI
{
	NSRect windowFrame = NSMakeRect(0, 0, 450, 280);
	NSWindow *window = [[NSWindow alloc]
	    initWithContentRect:windowFrame
	               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
	                 backing:NSBackingStoreBuffered
	                 defer:NO];
	self.window = window;
	[window release];
	[self.window setReleasedWhenClosed:NO];
	[self.window setTitle:@"Authentication"];

	NSView *contentView = [self.window contentView];
	[contentView setWantsLayer:YES];

	CGFloat padding = 16;
	CGFloat fieldHeight = 24;
	CGFloat labelHeight = 16;
	CGFloat buttonHeight = 32;
	CGFloat spacing = 8;

	// Message label
	self.messageLabel = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
	[self.messageLabel setStringValue:@"Authenticate to server"];
	[self.messageLabel setEditable:NO];
	[self.messageLabel setBezeled:NO];
	[self.messageLabel setDrawsBackground:NO];
	[self.messageLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[self.messageLabel sizeToFit];
	[self.messageLabel
	    setFrameOrigin:NSMakePoint(padding, windowFrame.size.height - padding - labelHeight)];
	[contentView addSubview:self.messageLabel];

	CGFloat currentY = self.messageLabel.frame.origin.y - spacing * 2 - fieldHeight;

	// Domain label
	NSTextField *domainLabel = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
	[domainLabel setStringValue:@"Domain:"];
	[domainLabel setEditable:NO];
	[domainLabel setBezeled:NO];
	[domainLabel setDrawsBackground:NO];
	[domainLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[domainLabel sizeToFit];
	[domainLabel setFrameOrigin:NSMakePoint(padding, currentY)];
	[contentView addSubview:domainLabel];

	// Domain text field
	self.domainText = [[[NSTextField alloc]
	    initWithFrame:NSMakeRect(padding + 100, currentY - 2, windowFrame.size.width - padding * 2 - 100,
	                             fieldHeight)]
	    autorelease];
	[self.domainText setStringValue:@""];
	[contentView addSubview:self.domainText];

	currentY -= (fieldHeight + spacing);

	// Username label
	NSTextField *usernameLabel = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
	[usernameLabel setStringValue:@"Username:"];
	[usernameLabel setEditable:NO];
	[usernameLabel setBezeled:NO];
	[usernameLabel setDrawsBackground:NO];
	[usernameLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[usernameLabel sizeToFit];
	[usernameLabel setFrameOrigin:NSMakePoint(padding, currentY)];
	[contentView addSubview:usernameLabel];

	// Username text field
	self.usernameText = [[[NSTextField alloc]
	    initWithFrame:NSMakeRect(padding + 100, currentY - 2, windowFrame.size.width - padding * 2 - 100,
	                             fieldHeight)]
	    autorelease];
	[self.usernameText setStringValue:@""];
	[contentView addSubview:self.usernameText];

	currentY -= (fieldHeight + spacing);

	// Password label
	NSTextField *passwordLabel = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
	[passwordLabel setStringValue:@"Password:"];
	[passwordLabel setEditable:NO];
	[passwordLabel setBezeled:NO];
	[passwordLabel setDrawsBackground:NO];
	[passwordLabel setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	[passwordLabel sizeToFit];
	[passwordLabel setFrameOrigin:NSMakePoint(padding, currentY)];
	[contentView addSubview:passwordLabel];

	// Password text field
	self.passwordText = [[[NSSecureTextField alloc]
	    initWithFrame:NSMakeRect(padding + 100, currentY - 2, windowFrame.size.width - padding * 2 - 100,
	                             fieldHeight)]
	    autorelease];
	[self.passwordText setStringValue:@""];
	[contentView addSubview:self.passwordText];

	currentY -= (fieldHeight + spacing * 2);

	// Cancel button
	NSButton *cancelButton = [[[NSButton alloc]
	    initWithFrame:NSMakeRect(windowFrame.size.width - padding - 100, currentY - buttonHeight,
	                             100, buttonHeight)]
	    autorelease];
	[cancelButton setTitle:@"Cancel"];
	[cancelButton setBezelStyle:NSBezelStyleRounded];
	[cancelButton setTarget:self];
	[cancelButton setAction:@selector(onCancel:)];
	[contentView addSubview:cancelButton];

	// OK button
	NSButton *okButton = [[[NSButton alloc]
	    initWithFrame:NSMakeRect(windowFrame.size.width - padding - 210, currentY - buttonHeight,
	                             100, buttonHeight)]
	    autorelease];
	[okButton setTitle:@"OK"];
	[okButton setBezelStyle:NSBezelStyleRounded];
	[okButton setTarget:self];
	[okButton setAction:@selector(onOK:)];
	[okButton setKeyEquivalent:@"\r"];
	[contentView addSubview:okButton];

	[self.window center];
}

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self.window setTitle:self.serverHostname];
	[self.messageLabel
	    setStringValue:[NSString stringWithFormat:@"Authenticate to %@", self.serverHostname]];

	if (self.domain != nil &&
	    [[self.domain stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
	        length] > 0)
	{
		[self.domainText setStringValue:self.domain];
	}

	if (self.username != nil)
	{
		[self.usernameText setStringValue:self.username];
		[self.window makeFirstResponder:self.passwordText];
	}
}

- (void)onOK:(NSObject *)sender
{
	self.username = self.usernameText.stringValue;
	self.password = self.passwordText.stringValue;
	self.domain = self.domainText.stringValue;
	[NSApp stopModalWithCode:TRUE];
}

- (void)onCancel:(NSObject *)sender
{
	[NSApp stopModalWithCode:FALSE];
}

- (BOOL)runModal:(NSWindow *)mainWindow
{
	[self windowDidLoad];
	if ([mainWindow respondsToSelector:@selector(beginSheet:completionHandler:)])
	{
		[mainWindow beginSheet:self.window completionHandler:nil];
		self.modalCode = [NSApp runModalForWindow:self.window];
		[mainWindow endSheet:self.window];
	}
	else
	{
		[NSApp beginSheet:self.window
		    modalForWindow:mainWindow
		     modalDelegate:nil
		    didEndSelector:nil
		       contextInfo:nil];
		self.modalCode = [NSApp runModalForWindow:self.window];
		[NSApp endSheet:self.window];
	}

	[self.window orderOut:nil];
	return self.modalCode;
}

- (void)dealloc
{
	[usernameText release];
	[passwordText release];
	[domainText release];
	[messageLabel release];
	[serverHostname release];
	[username release];
	[password release];
	[domain release];
	[super dealloc];
}

@end
