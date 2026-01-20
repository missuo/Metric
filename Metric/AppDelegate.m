//
//  AppDelegate.m
//  Metric
//
//  Main application delegate implementation
//

#import "AppDelegate.h"
#import "RuleManager.h"
#import "NetworkInterfaceManager.h"
#import "SharedConstants.h"
#import <NetworkExtension/NetworkExtension.h>
#import <SystemExtensions/SystemExtensions.h>

@interface AppDelegate () <OSSystemExtensionRequestDelegate>

@property (nonatomic, strong) NETransparentProxyManager *proxyManager;
@property (nonatomic, assign) BOOL extensionInstalled;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Initialize managers
    [MTRuleManager sharedManager];
    [MTNetworkInterfaceManager sharedManager];

    // Register for system notifications
    [self registerForNotifications];
    
    // Don't auto-prompt on startup - let user manually install via button
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Clean up
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

#pragma mark - Extension Management

- (void)checkAndPromptForExtensionInstallation {
    NSLog(@"Checking extension installation status...");
    
    // First check if extension is already configured/installed
    [NETransparentProxyManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETransparentProxyManager *> *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"Error loading proxy managers: %@", error);
                // Still try to show prompt even if there's an error
                [self showExtensionInstallPrompt];
                return;
            }
            
            NSLog(@"Found %lu proxy manager(s)", (unsigned long)managers.count);
            
            // Check if we already have a configured proxy manager for our extension
            BOOL extensionConfigured = NO;
            BOOL extensionWorking = NO;
            for (NETransparentProxyManager *manager in managers) {
                NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)manager.protocolConfiguration;
                NSLog(@"Checking manager with bundle ID: %@, status: %ld", 
                      protocol.providerBundleIdentifier, (long)manager.connection.status);
                if ([protocol.providerBundleIdentifier isEqualToString:kMTExtensionBundleIdentifier]) {
                    extensionConfigured = YES;
                    self.proxyManager = manager;
                    // Check if extension is in a valid state (not Invalid)
                    // NEVPNStatusInvalid = 0 means the configuration is not valid
                    if (manager.connection.status != NEVPNStatusInvalid) {
                        extensionWorking = YES;
                        self.extensionInstalled = YES;
                        NSLog(@"Extension configured and valid!");
                    } else {
                        NSLog(@"Extension configured but status is Invalid");
                    }
                    break;
                }
            }
            
            if (extensionConfigured && extensionWorking) {
                // Extension is installed and working, no need to prompt
                NSLog(@"Extension is working, skipping install prompt");
                return;
            }
            
            // Extension not configured or not working, show installation prompt
            NSLog(@"Extension not configured or not working, showing install prompt");
            [self showExtensionInstallPrompt];
        });
    }];
}

- (void)showExtensionInstallPrompt {
    NSLog(@"Showing extension install prompt...");
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Check if user has suppressed the prompt
    BOOL suppressPrompt = [defaults boolForKey:@"MTSuppressExtensionPrompt"];
    NSLog(@"Suppress prompt preference: %@", suppressPrompt ? @"YES" : @"NO");
    
    if (suppressPrompt) {
        NSLog(@"Extension prompt suppressed by user preference");
        return;
    }
    
    // Check if we've already prompted (to show suppression option)
    BOOL hasPrompted = [defaults boolForKey:@"MTHasPromptedForExtension"];
    NSLog(@"Has prompted before: %@", hasPrompted ? @"YES" : @"NO");
    
    // Bring app to front to ensure alert is visible
    [NSApp activateIgnoringOtherApps:YES];
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Install Network Extension";
    alert.informativeText = @"Metric needs to install a network extension to manage traffic routing.\n\nAfter clicking \"Install\", you may need to:\n1. Allow the extension in System Settings > Privacy & Security\n2. Allow network filtering when prompted";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"Install"];
    [alert addButtonWithTitle:hasPrompted ? @"Not Now" : @"Later"];
    
    if (hasPrompted) {
        [alert setShowsSuppressionButton:YES];
        alert.suppressionButton.title = @"Don't ask again on startup";
    }
    
    NSLog(@"Running alert modal...");
    NSModalResponse response = [alert runModal];
    NSLog(@"Alert response: %ld", (long)response);
    
    // Mark that we've prompted
    [defaults setBool:YES forKey:@"MTHasPromptedForExtension"];
    [defaults synchronize];
    
    // If suppression button is checked, remember not to prompt again
    if (alert.suppressionButton.state == NSControlStateValueOn) {
        [defaults setBool:YES forKey:@"MTSuppressExtensionPrompt"];
        [defaults synchronize];
    }
    
    if (response == NSAlertFirstButtonReturn) {
        // User wants to install - directly submit the activation request
        NSLog(@"User chose to install extension");
        [self installExtension];
    } else {
        NSLog(@"User declined extension installation");
    }
}

- (void)installExtension {
    OSSystemExtensionRequest *request = [OSSystemExtensionRequest
                                         activationRequestForExtension:kMTExtensionBundleIdentifier
                                         queue:dispatch_get_main_queue()];
    request.delegate = self;
    [[OSSystemExtensionManager sharedManager] submitRequest:request];
}

- (void)uninstallExtension {
    OSSystemExtensionRequest *request = [OSSystemExtensionRequest
                                         deactivationRequestForExtension:kMTExtensionBundleIdentifier
                                         queue:dispatch_get_main_queue()];
    request.delegate = self;
    [[OSSystemExtensionManager sharedManager] submitRequest:request];
}

#pragma mark - OSSystemExtensionRequestDelegate

- (OSSystemExtensionReplacementAction)request:(OSSystemExtensionRequest *)request
                  actionForReplacingExtension:(OSSystemExtensionProperties *)existing
                                withExtension:(OSSystemExtensionProperties *)ext {
    return OSSystemExtensionReplacementActionReplace;
}

- (void)request:(OSSystemExtensionRequest *)request didFailWithError:(NSError *)error {
    NSLog(@"System extension request failed: %@", error);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Extension Installation Failed";
        alert.informativeText = error.localizedDescription;
        alert.alertStyle = NSAlertStyleCritical;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    });
}

- (void)request:(OSSystemExtensionRequest *)request didFinishWithResult:(OSSystemExtensionRequestResult)result {
    NSLog(@"System extension request finished with result: %ld", (long)result);

    dispatch_async(dispatch_get_main_queue(), ^{
        switch (result) {
            case OSSystemExtensionRequestCompleted:
                self.extensionInstalled = YES;
                [self configureProxyManager];
                break;
            case OSSystemExtensionRequestWillCompleteAfterReboot:
                {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Reboot Required";
                    alert.informativeText = @"The extension will be activated after you reboot your Mac.";
                    alert.alertStyle = NSAlertStyleInformational;
                    [alert addButtonWithTitle:@"OK"];
                    [alert runModal];
                }
                break;
            default:
                break;
        }
    });
}

- (void)requestNeedsUserApproval:(OSSystemExtensionRequest *)request {
    NSLog(@"System extension needs user approval");

    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Approval Required";
        alert.informativeText = @"Please approve the system extension in System Preferences > Privacy & Security.";
        alert.alertStyle = NSAlertStyleInformational;
        [alert addButtonWithTitle:@"Open System Preferences"];
        [alert addButtonWithTitle:@"Cancel"];

        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy"]];
        }
    });
}

#pragma mark - Proxy Manager Configuration

- (void)configureProxyManager {
    [NETransparentProxyManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETransparentProxyManager *> *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"Error loading proxy managers: %@", error);
                return;
            }

            NETransparentProxyManager *manager = nil;

            for (NETransparentProxyManager *m in managers) {
                NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)m.protocolConfiguration;
                if ([protocol.providerBundleIdentifier isEqualToString:kMTExtensionBundleIdentifier]) {
                    manager = m;
                    break;
                }
            }

            if (!manager) {
                manager = [[NETransparentProxyManager alloc] init];
            }

            NETunnelProviderProtocol *protocol = [[NETunnelProviderProtocol alloc] init];
            protocol.providerBundleIdentifier = kMTExtensionBundleIdentifier;
            protocol.serverAddress = @"Metric";

            manager.protocolConfiguration = protocol;
            manager.localizedDescription = @"Metric Transparent Proxy";
            manager.enabled = YES;

            [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (saveError) {
                        NSLog(@"Error saving proxy manager: %@", saveError);
                        return;
                    }

                    self.proxyManager = manager;
                    NSLog(@"Proxy manager configured successfully");
                });
            }];
        });
    }];
}

#pragma mark - Notifications

- (void)registerForNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRulesDidChange:)
                                                 name:MTRuleManagerDidChangeNotification
                                               object:nil];
}

- (void)handleRulesDidChange:(NSNotification *)notification {
    // Rules changed, sync to extension
    [[MTRuleManager sharedManager] syncRulesToExtension];
}

#pragma mark - Menu Actions

- (IBAction)showMainWindow:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    for (NSWindow *window in [NSApp windows]) {
        if ([window.identifier isEqualToString:@"MainWindow"]) {
            [window makeKeyAndOrderFront:sender];
            return;
        }
    }
}

- (IBAction)installExtensionAction:(id)sender {
    [self installExtension];
}

- (IBAction)uninstallExtensionAction:(id)sender {
    [self uninstallExtension];
}

@end
