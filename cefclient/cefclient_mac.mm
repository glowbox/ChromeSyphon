// Copyright (c) 2013 The Chromium Embedded Framework Authors.
// Portions copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Cocoa/Cocoa.h>
#include <sstream>
#include "cefclient/cefclient.h"
#include "include/cef_app.h"
#import "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_frame.h"
#include "include/cef_runnable.h"
#include "cefclient/cefclient_osr_widget_mac.h"
#include "cefclient/client_handler.h"
#include "cefclient/client_switches.h"
#include "cefclient/resource_util.h"
#include "cefclient/string_util.h"

// The global ClientHandler reference.
extern CefRefPtr<ClientHandler> g_handler;

class MainBrowserProvider : public OSRBrowserProvider {
    virtual CefRefPtr<CefBrowser> GetBrowser() {
        if (g_handler.get())
            return g_handler->GetBrowser();
        
        return NULL;
    }
} g_main_browser_provider;

char szWorkingDir[512];   // The current working directory

// Sizes for URL bar layout
#define BUTTON_HEIGHT 22
#define BUTTON_WIDTH 72
#define BUTTON_MARGIN 8
#define URLBAR_HEIGHT  32

// Content area size for newly created windows.
int WindowWidth = 800;
int WindowHeight = 600;

bool bStartMinimized = false;
int WindowPositionX = 0;
int WindowPositionY = 0;

bool bAllowResize = true;

NSString *StartupURL = @"http://www.google.com";
NSString *SyphonName = @"Chrome Syphon";


// Provide the CefAppProtocol implementation required by CEF.
@interface ClientApplication : NSApplication<CefAppProtocol> {
@private
    BOOL handlingSendEvent_;
}
@end

@implementation ClientApplication
- (BOOL)isHandlingSendEvent {
    return handlingSendEvent_;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    handlingSendEvent_ = handlingSendEvent;
}

- (void)sendEvent:(NSEvent*)event {
    CefScopedSendingEvent sendingEventScoper;
    [super sendEvent:event];
}
@end


// Receives notifications from controls and the browser window. Will delete
// itself when done.
@interface ClientWindowDelegate : NSObject <NSWindowDelegate>
- (IBAction)goBack:(id)sender;
- (IBAction)goForward:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)stopLoading:(id)sender;
- (IBAction)takeURLStringValueFrom:(NSTextField *)sender;
- (void)alert:(NSString*)title withMessage:(NSString*)message;
- (void)notifyConsoleMessage:(id)object;
- (void)notifyDownloadComplete:(id)object;
- (void)notifyDownloadError:(id)object;
@end

@implementation ClientWindowDelegate

- (IBAction)goBack:(id)sender {
    if (g_handler.get() && g_handler->GetBrowserId())
        g_handler->GetBrowser()->GoBack();
}

- (IBAction)goForward:(id)sender {
    if (g_handler.get() && g_handler->GetBrowserId())
        g_handler->GetBrowser()->GoForward();
}

- (IBAction)reload:(id)sender {
    if (g_handler.get() && g_handler->GetBrowserId())
        g_handler->GetBrowser()->Reload();
}

- (IBAction)stopLoading:(id)sender {
    if (g_handler.get() && g_handler->GetBrowserId())
        g_handler->GetBrowser()->StopLoad();
}

- (IBAction)takeURLStringValueFrom:(NSTextField *)sender {
    if (!g_handler.get() || !g_handler->GetBrowserId())
        return;
    
    NSString *url = [sender stringValue];
    
    // if it doesn't already have a prefix, add http. If we can't parse it,
    // just don't bother rather than making things worse.
    NSURL* tempUrl = [NSURL URLWithString:url];
    if (tempUrl && ![tempUrl scheme])
        url = [@"http://" stringByAppendingString:url];
    
    std::string urlStr = [url UTF8String];
    g_handler->GetBrowser()->GetMainFrame()->LoadURL(urlStr);
}

- (void)alert:(NSString*)title withMessage:(NSString*)message {
    NSAlert *alert = [NSAlert alertWithMessageText:title
                                     defaultButton:@"OK"
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:@"%@", message];
    [alert runModal];
}

- (void)notifyConsoleMessage:(id)object {
    std::stringstream ss;
    ss << "Console messages will be written to " << g_handler->GetLogFile();
    NSString* str = [NSString stringWithUTF8String:(ss.str().c_str())];
    [self alert:@"Console Messages" withMessage:str];
}

- (void)notifyDownloadComplete:(id)object {
    std::stringstream ss;
    ss << "File \"" << g_handler->GetLastDownloadFile() <<
    "\" downloaded successfully.";
    NSString* str = [NSString stringWithUTF8String:(ss.str().c_str())];
    [self alert:@"File Download" withMessage:str];
}

- (void)notifyDownloadError:(id)object {
    std::stringstream ss;
    ss << "File \"" << g_handler->GetLastDownloadFile() <<
    "\" failed to download.";
    NSString* str = [NSString stringWithUTF8String:(ss.str().c_str())];
    [self alert:@"File Download" withMessage:str];
}

- (void)windowDidBecomeKey:(NSNotification*)notification {
    if (g_handler.get() && g_handler->GetBrowserId()) {
        // Give focus to the browser window.
        g_handler->GetBrowser()->GetHost()->SetFocus(true);
    }
}

// Called when the window is about to close. Perform the self-destruction
// sequence by getting rid of the window. By returning YES, we allow the window
// to be removed from the screen.
- (BOOL)windowShouldClose:(id)window {
    if (g_handler.get() && !g_handler->IsClosing()) {
        CefRefPtr<CefBrowser> browser = g_handler->GetBrowser();
        if (browser.get()) {
            // Notify the browser window that we would like to close it. This
            // will result in a call to ClientHandler::DoClose() if the
            // JavaScript 'onbeforeunload' event handler allows it.
            browser->GetHost()->CloseBrowser(false);
            
            // Cancel the close.
            return NO;
        }
    }
    
    // Try to make the window go away.
    [window autorelease];
    
    // Clean ourselves up after clearing the stack of anything that might have the
    // window on it.
    [self performSelectorOnMainThread:@selector(cleanup:)
                           withObject:window
                        waitUntilDone:NO];
    
    // Allow the close.
    return YES;
}

// Deletes itself.
- (void)cleanup:(id)window {
    [self release];
}

@end


NSButton* MakeButton(NSRect* rect, NSString* title, NSView* parent) {
    NSButton* button = [[[NSButton alloc] initWithFrame:*rect] autorelease];
    [button setTitle:title];
    [button setBezelStyle:NSSmallSquareBezelStyle];
    [button setAutoresizingMask:(NSViewMaxXMargin | NSViewMinYMargin)];
    [parent addSubview:button];
    rect->origin.x += BUTTON_WIDTH;
    return button;
}

// Receives notifications from the application. Will delete itself when done.
@interface ClientAppDelegate : NSObject<NSFileManagerDelegate>
- (void)createApp:(id)object;
- (void)loadJSONConfig;
@end

@implementation ClientAppDelegate

- (void) loadJSONConfig {

    
    CefRefPtr<CefCommandLine> cmd_line = AppGetCommandLine();
    

    NSString *jsonFileName;
    
    if(cmd_line->HasSwitch(cefclient::kConfigFile)) {
        CefString configFile = cmd_line->GetSwitchValue(cefclient::kConfigFile);
        std::string str(configFile);
        jsonFileName = [NSString stringWithUTF8String:str.c_str()];
    } else {
        jsonFileName = @"config.json";
    }
    
    NSString *jsonPath = [NSString stringWithFormat:@"%@/../%@", [[NSBundle mainBundle] bundlePath], jsonFileName];
    NSData *data = [NSData dataWithContentsOfFile:jsonPath];
    
    if(data != nil) {
        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                             options:kNilOptions
                                                               error:&error];
        
        int contentWidth = [[json valueForKey:@"content-width"] integerValue];
        int contentHeight = [[json valueForKey:@"content-height"] integerValue];
        
        if((contentWidth > 0) && (contentHeight > 0)) {
            WindowWidth = contentWidth;
            WindowHeight = contentHeight;
        }
        
        if(([json valueForKey:@"window-x"] != nil) && ([json valueForKey:@"window-y"] != nil)){
            WindowPositionX = [[json valueForKey:@"window-x"] integerValue];
            WindowPositionY = [[json valueForKey:@"window-y"] integerValue];
        }
        
        if([json valueForKey:@"allow-window-resize"] != nil) {
            bAllowResize = [[json valueForKey:@"allow-window-resize"] boolValue];
        }
        
        if([json valueForKey:@"start-minimized"] != nil) {
            bStartMinimized = [[json valueForKey:@"start-minimized"] boolValue];
        }
        
        if([json valueForKey:@"url"] != nil) {
            StartupURL = [NSString stringWithString:[json valueForKey:@"url"]];
        }
        
        if([json valueForKey:@"syphon-name"] != nil) {
            SyphonName = [NSString stringWithString:[json valueForKey:@"syphon-name"]];
        }
        
    } else {
        NSLog(@"Couldn't find config json file, using defaults.");
    }
}


// Create the application on the UI thread.
- (void)createApp:(id)object {
    [NSApplication sharedApplication];
    
    [NSBundle loadNibNamed:@"MainMenu" owner:NSApp];
    
    // Set the delegate for application events.
    [NSApp setDelegate:self];
    
    [self loadJSONConfig];
    
    // Create the delegate for control and browser window events.
    ClientWindowDelegate* delegate = [[ClientWindowDelegate alloc] init];
    
    // Create the main application window.
    NSRect screen_rect = [[NSScreen mainScreen] visibleFrame];
    NSRect window_rect = { {0, screen_rect.size.height - WindowHeight},
        {WindowWidth, WindowHeight} };
    
    int styleMaskFlags = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
    
    CefRefPtr<CefCommandLine> options = AppGetCommandLine();
    if( bAllowResize) {
        styleMaskFlags = styleMaskFlags | NSResizableWindowMask;
    }
    
    NSWindow* mainWnd = [[UnderlayOpenGLHostingWindow alloc]
                         initWithContentRect:window_rect
                         styleMask:(styleMaskFlags)
                         backing:NSBackingStoreBuffered
                         defer:NO];
    
    [mainWnd setTitle:@"Chrome to Syphon"];
    [mainWnd setDelegate:delegate];
    
    // Rely on the window delegate to clean us up rather than immediately
    // releasing when the window gets closed. We use the delegate to do
    // everything from the autorelease pool so the window isn't on the stack
    // during cleanup (ie, a window close from javascript).
    [mainWnd setReleasedWhenClosed:NO];
    
    NSView* contentView = [mainWnd contentView];
    
    // Create the buttons.
    NSRect button_rect = [contentView bounds];
    button_rect.origin.y = window_rect.size.height - URLBAR_HEIGHT + (URLBAR_HEIGHT - BUTTON_HEIGHT) / 2;
    button_rect.size.height = BUTTON_HEIGHT;
    button_rect.origin.x += BUTTON_MARGIN;
    button_rect.size.width = BUTTON_WIDTH;
    
    NSButton* button = MakeButton(&button_rect, @"Reload", contentView);
    [button setTarget:delegate];
    [button setAction:@selector(reload:)];
    
    // Create the URL text field.
    button_rect.origin.x += BUTTON_MARGIN;
    button_rect.size.width = [contentView bounds].size.width -
    button_rect.origin.x - BUTTON_MARGIN;
    
    NSTextField* editWnd = [[NSTextField alloc] initWithFrame:button_rect];
    
    [contentView addSubview:editWnd];
    [editWnd setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [editWnd setTarget:delegate];
    [editWnd setAction:@selector(takeURLStringValueFrom:)];
    [[editWnd cell] setWraps:NO];
    [[editWnd cell] setScrollable:YES];
    
    // Create the handler.
    g_handler = new ClientHandler();
    g_handler->SetMainHwnd(contentView);
    g_handler->SetEditHwnd(editWnd);
    
    // Create the browser view.
    CefWindowInfo window_info;
    CefBrowserSettings settings;
    
    if (AppIsOffScreenRenderingEnabled()) {
        
        CefRefPtr<CefCommandLine> cmd_line = AppGetCommandLine();
        
        bool transparent = cmd_line->HasSwitch(cefclient::kTransparentPaintingEnabled);
        
        CefRefPtr<OSRWindow> osr_window =
        OSRWindow::Create(&g_main_browser_provider, transparent, contentView,
                          CefRect(0, 0, WindowWidth, WindowHeight), SyphonName);
        window_info.SetAsOffScreen(osr_window->GetWindowHandle());
        window_info.SetTransparentPainting(transparent);
        g_handler->SetOSRHandler(osr_window->GetRenderHandler().get());
    } else {
        // Initialize window info to the defaults for a child window.
        window_info.SetAsChild(contentView, 0, 0, WindowWidth, WindowHeight);
    }
    
    
    CefBrowserHost::CreateBrowser(window_info, g_handler.get(), [StartupURL UTF8String], settings);
    
    // Show the window.
    [mainWnd makeKeyAndOrderFront: nil];
    
    // Size the window.
    NSRect r = [mainWnd contentRectForFrameRect:[mainWnd frame]];
    
    r.size.width = WindowWidth;
    r.size.height = WindowHeight + URLBAR_HEIGHT;
    
    // MacOS coordinates 0,0 is the lower left corner because reasons.
    int windowTopAdjusted = [[NSScreen mainScreen] frame].size.height - WindowPositionY;
    
    [mainWnd setFrame:[mainWnd frameRectForContentRect:r] display:YES];
    [mainWnd setFrameTopLeftPoint:CGPointMake(WindowPositionX, windowTopAdjusted)];
    
    if(bStartMinimized) {
        [mainWnd performMiniaturize:self];
    }
}


// Called when the application's Quit menu item is selected.
- (NSApplicationTerminateReply)applicationShouldTerminate: (NSApplication *)sender {
    // Request that all browser windows close.
    if (g_handler.get()) {
        g_handler->CloseAllBrowsers(false);
    }
    
    // Cancel the termination. The application will exit after all windows have
    // closed.
    return NSTerminateCancel;
}

// Sent immediately before the application terminates. This signal should not
// be called because we cancel the termination.
- (void)applicationWillTerminate:(NSNotification *)aNotification {
    ASSERT(false);  // Not reached.
}

@end


int main(int argc, char* argv[]) {
    CefMainArgs main_args(argc, argv);
    CefRefPtr<ClientApp> app(new ClientApp);
    
    // Execute the secondary process, if any.
    int exit_code = CefExecuteProcess(main_args, app.get());
    if (exit_code >= 0)
        return exit_code;
    
    // Retrieve the current working directory.
    getcwd(szWorkingDir, sizeof(szWorkingDir));
    
    // Initialize the AutoRelease pool.
    NSAutoreleasePool* autopool = [[NSAutoreleasePool alloc] init];
    
    // Initialize the ClientApplication instance.
    [ClientApplication sharedApplication];
    
    // Parse command line arguments.
    AppInitCommandLine(argc, argv);
    
    CefSettings settings;
    
    // Populate the settings based on command line arguments.
    AppGetSettings(settings);
    
    // Initialize CEF.
    CefInitialize(main_args, settings, app.get());
    
    // Register the scheme handler.
    // scheme_test::InitTest();
    
    // Create the application delegate and window.
    NSObject* delegate = [[ClientAppDelegate alloc] init];
    [delegate performSelectorOnMainThread:@selector(createApp:) withObject:nil
                            waitUntilDone:NO];
    
    // Run the application message loop.
    CefRunMessageLoop();
    
    // Shut down CEF.
    CefShutdown();
    
    // Release the handler.
    g_handler = NULL;
    
    // Release the delegate.
    [delegate release];
    
    // Release the AutoRelease pool.
    [autopool release];
    
    return 0;
}


// Global functions

std::string AppGetWorkingDirectory() {
    return szWorkingDir;
}

void AppQuitMessageLoop() {
    CefQuitMessageLoop();
}
