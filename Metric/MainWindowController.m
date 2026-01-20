//
//  MainWindowController.m
//  Metric
//
//  Main window controller implementation
//

#import "MainWindowController.h"
#import "AddRuleViewController.h"
#import "NetworkInterfaceManager.h"
#import "Rule.h"
#import "RuleManager.h"
#import "RuleModel.h"
#import "RuleTableViewController.h"
#import "SharedConstants.h"
#import <NetworkExtension/NetworkExtension.h>
#import <SystemExtensions/SystemExtensions.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MainWindowController () <NSTableViewDataSource, NSTableViewDelegate,
                                    OSSystemExtensionRequestDelegate>

// UI Outlets
@property(weak) IBOutlet NSSwitch *proxySwitch;
@property(weak) IBOutlet NSTextField *statusLabel;
@property(weak) IBOutlet NSTextField *ethernetLabel;
@property(weak) IBOutlet NSTextField *wifiLabel;
@property(weak) IBOutlet NSTableView *rulesTableView;
@property(weak) IBOutlet NSButton *addButton;
@property(weak) IBOutlet NSButton *removeButton;
@property(weak) IBOutlet NSTextField *extensionStatusLabel;

// State
@property(nonatomic, strong) NETransparentProxyManager *proxyManager;
@property(nonatomic, assign) MTProxyStatus proxyStatus;

@end

@implementation MainWindowController

- (void)viewDidLoad {
  [super viewDidLoad];

  [self setupTableView];
  [self setupNotifications];
  [self updateInterfaceLabels];
  [self updateExtensionStatus];
  [self checkProxyStatus];
  
  NSLog(@"[App] Metric started");
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Setup

- (void)setupTableView {
  self.rulesTableView.dataSource = self;
  self.rulesTableView.delegate = self;

  // Enable drag and drop for reordering
  [self.rulesTableView registerForDraggedTypes:@[ @"nz.owo.metric.rule" ]];
  self.rulesTableView.draggingDestinationFeedbackStyle =
      NSTableViewDraggingDestinationFeedbackStyleGap;
}

- (void)setupNotifications {
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(rulesDidChange:)
             name:MTRuleManagerDidChangeNotification
           object:nil];

  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(interfacesDidChange:)
             name:MTNetworkInterfacesDidChangeNotification
           object:nil];
}

#pragma mark - UI Updates

- (void)updateInterfaceLabels {
  MTNetworkInterfaceManager *manager =
      [MTNetworkInterfaceManager sharedManager];
  
  // Collect all active interfaces
  NSMutableArray<NSString *> *activeInterfaces = [NSMutableArray array];
  NSMutableArray<NSString *> *otherInterfaces = [NSMutableArray array];
  
  for (MTNetworkInterface *iface in manager.interfaces) {
    if (iface.hasIPv4 || iface.hasIPv6) {
      NSString *ipInfo = iface.ipv4Address ?: iface.ipv6Address ?: @"No IP";
      NSString *label = [NSString stringWithFormat:@"%@ (%@): %@", 
                         iface.displayName, iface.name, ipInfo];
      [activeInterfaces addObject:label];
    } else {
      [otherInterfaces addObject:[NSString stringWithFormat:@"%@ (%@): Not connected",
                                  iface.displayName, iface.name]];
    }
  }
  
  // Display in the two available labels
  if (activeInterfaces.count >= 1) {
    self.ethernetLabel.stringValue = activeInterfaces[0];
    self.ethernetLabel.textColor = [NSColor labelColor];
  } else if (otherInterfaces.count >= 1) {
    self.ethernetLabel.stringValue = otherInterfaces[0];
    self.ethernetLabel.textColor = [NSColor secondaryLabelColor];
  } else {
    self.ethernetLabel.stringValue = @"No interfaces found";
    self.ethernetLabel.textColor = [NSColor secondaryLabelColor];
  }
  
  if (activeInterfaces.count >= 2) {
    self.wifiLabel.stringValue = activeInterfaces[1];
    self.wifiLabel.textColor = [NSColor labelColor];
  } else if (activeInterfaces.count == 1 && otherInterfaces.count >= 1) {
    self.wifiLabel.stringValue = otherInterfaces[0];
    self.wifiLabel.textColor = [NSColor secondaryLabelColor];
  } else if (otherInterfaces.count >= 2) {
    self.wifiLabel.stringValue = otherInterfaces[1];
    self.wifiLabel.textColor = [NSColor secondaryLabelColor];
  } else {
    self.wifiLabel.stringValue = @"";
  }
}

- (void)updateStatusLabel {
  switch (self.proxyStatus) {
  case MTProxyStatusStopped:
    self.statusLabel.stringValue = @"Stopped";
    self.proxySwitch.state = NSControlStateValueOff;
    break;
  case MTProxyStatusStarting:
    self.statusLabel.stringValue = @"Starting...";
    break;
  case MTProxyStatusRunning:
    self.statusLabel.stringValue = @"Running";
    self.proxySwitch.state = NSControlStateValueOn;
    break;
  case MTProxyStatusStopping:
    self.statusLabel.stringValue = @"Stopping...";
    break;
  case MTProxyStatusError:
    self.statusLabel.stringValue = @"Error";
    self.proxySwitch.state = NSControlStateValueOff;
    break;
  }
}

- (void)updateExtensionStatus {
  [NETransparentProxyManager loadAllFromPreferencesWithCompletionHandler:^(
                                 NSArray<NETransparentProxyManager *> *managers,
                                 NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) {
        self.extensionStatusLabel.stringValue = @"Extension: Error";
        self.extensionStatusLabel.textColor = [NSColor systemRedColor];
        return;
      }
      
      BOOL hasExtension = NO;
      BOOL isEnabled = NO;
      
      for (NETransparentProxyManager *m in managers) {
        NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)m.protocolConfiguration;
        if ([protocol.providerBundleIdentifier isEqualToString:kMTExtensionBundleIdentifier]) {
          hasExtension = YES;
          isEnabled = m.enabled;
          break;
        }
      }
      
      if (hasExtension) {
        if (isEnabled) {
          self.extensionStatusLabel.stringValue = @"Extension: Installed & Enabled";
          self.extensionStatusLabel.textColor = [NSColor systemGreenColor];
        } else {
          self.extensionStatusLabel.stringValue = @"Extension: Installed (Disabled)";
          self.extensionStatusLabel.textColor = [NSColor systemOrangeColor];
        }
      } else {
        self.extensionStatusLabel.stringValue = @"Extension: Not Installed";
        self.extensionStatusLabel.textColor = [NSColor secondaryLabelColor];
      }
    });
  }];
}

#pragma mark - Proxy Management

- (void)checkProxyStatus {
  NSLog(@"[App] Checking proxy status...");

  [NETransparentProxyManager loadAllFromPreferencesWithCompletionHandler:^(
                                 NSArray<NETransparentProxyManager *> *managers,
                                 NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (error) {
        NSLog(@"[App] ERROR loading managers: %@", error.localizedDescription);
        self.proxyStatus = MTProxyStatusError;
        [self updateStatusLabel];
        return;
      }

      NSLog(@"[App] Found %lu proxy manager(s)", (unsigned long)managers.count);

      // Find manager matching our extension
      NETransparentProxyManager *manager = nil;
      for (NETransparentProxyManager *m in managers) {
        NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)m.protocolConfiguration;
        NSLog(@"[App] Manager: %@, enabled=%d", protocol.providerBundleIdentifier, m.enabled);
        if ([protocol.providerBundleIdentifier isEqualToString:kMTExtensionBundleIdentifier]) {
          manager = m;
          break;
        }
      }

      if (!manager) {
        NSLog(@"[App] No proxy configuration found, creating one...");
        // Create new manager
        manager = [[NETransparentProxyManager alloc] init];
        NETunnelProviderProtocol *protocol = [[NETunnelProviderProtocol alloc] init];
        protocol.providerBundleIdentifier = kMTExtensionBundleIdentifier;
        protocol.serverAddress = @"127.0.0.1";
        manager.protocolConfiguration = protocol;
        manager.localizedDescription = @"Metric Transparent Proxy";
        manager.enabled = YES;

        [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (saveError) {
              NSLog(@"[App] ERROR saving manager: %@ (code: %ld)", saveError.localizedDescription, (long)saveError.code);
              self.proxyStatus = MTProxyStatusError;
              [self updateStatusLabel];
            } else {
              NSLog(@"[App] Proxy configuration created successfully");
              self.proxyManager = manager;
              [self observeProxyStatus];
              self.proxyStatus = MTProxyStatusStopped;
              [self updateStatusLabel];
            }
          });
        }];
        return;
      } else {
        NSLog(@"[App] Found existing manager, status: %ld", (long)manager.connection.status);
        self.proxyManager = manager;
        [self observeProxyStatus];
        [self updateProxyStatusFromConnection];
      }
    });
  }];
}

- (void)observeProxyStatus {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(vpnStatusDidChange:)
                                               name:NEVPNStatusDidChangeNotification
                                             object:self.proxyManager.connection];
}

- (void)vpnStatusDidChange:(NSNotification *)notification {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateProxyStatusFromConnection];
  });
}

- (void)updateProxyStatusFromConnection {
  if (!self.proxyManager) {
    self.proxyStatus = MTProxyStatusStopped;
    [self updateStatusLabel];
    return;
  }

  NEVPNStatus status = self.proxyManager.connection.status;
  NSString *statusName = @"Unknown";

  switch (status) {
    case NEVPNStatusConnected:
      self.proxyStatus = MTProxyStatusRunning;
      statusName = @"Connected";
      break;
    case NEVPNStatusConnecting:
      self.proxyStatus = MTProxyStatusStarting;
      statusName = @"Connecting";
      break;
    case NEVPNStatusDisconnecting:
      self.proxyStatus = MTProxyStatusStopping;
      statusName = @"Disconnecting";
      break;
    case NEVPNStatusDisconnected:
      self.proxyStatus = MTProxyStatusStopped;
      statusName = @"Disconnected";
      break;
    case NEVPNStatusInvalid:
      self.proxyStatus = MTProxyStatusStopped;
      statusName = @"Invalid";
      break;
    case NEVPNStatusReasserting:
      self.proxyStatus = MTProxyStatusStarting;
      statusName = @"Reasserting";
      break;
  }

  NSLog(@"[App] Connection status: %@", statusName);
  [self updateStatusLabel];
}

- (void)startProxy {
  if (!self.proxyManager) {
    NSLog(@"[App] No proxy manager, checking status first...");
    [self checkProxyStatus];
    return;
  }

  NSLog(@"[App] Starting proxy...");
  self.proxyStatus = MTProxyStatusStarting;
  [self updateStatusLabel];

  NSLog(@"[App] Loading preferences before start...");

  // Reload from preferences before starting
  [self.proxyManager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (loadError) {
        NSLog(@"[App] Error loading preferences: %@", loadError.localizedDescription);
        self.proxyStatus = MTProxyStatusError;
        [self updateStatusLabel];
        [self showErrorAlert:@"Failed to Load Configuration" message:loadError.localizedDescription];
        return;
      }

      NSLog(@"[App] Preferences loaded, manager.enabled=%d", self.proxyManager.enabled);

      // Ensure manager is enabled
      if (!self.proxyManager.enabled) {
        NSLog(@"[App] Manager is disabled, enabling...");
        self.proxyManager.enabled = YES;
        [self.proxyManager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (saveError) {
              NSLog(@"[App] Error enabling manager: %@", saveError.localizedDescription);
              self.proxyStatus = MTProxyStatusError;
              [self updateStatusLabel];
              [self showErrorAlert:@"Failed to Enable Proxy" message:saveError.localizedDescription];
              return;
            }
            NSLog(@"[App] Manager enabled, starting tunnel...");
            [self actuallyStartVPNTunnel];
          });
        }];
      } else {
        [self actuallyStartVPNTunnel];
      }
    });
  }];
}

- (void)actuallyStartVPNTunnel {
  NSLog(@"[App] Starting VPN tunnel...");

  // Update provider configuration with current rules before starting
  NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)self.proxyManager.protocolConfiguration;
  
  // Get rules as dictionary array
  NSMutableArray *rulesArray = [NSMutableArray array];
  for (MTRule *rule in [MTRuleManager sharedManager].rules) {
    MTRuleModel *model = [rule toRuleModel];
    [rulesArray addObject:[model toDictionary]];
  }
  
  protocol.providerConfiguration = @{
    @"rules": rulesArray
  };
  
  NSLog(@"[App] Passing %lu rules to extension via providerConfiguration", (unsigned long)rulesArray.count);
  
  // Save the updated configuration
  [self.proxyManager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (saveError) {
        NSLog(@"[App] Error saving config: %@", saveError.localizedDescription);
        self.proxyStatus = MTProxyStatusError;
        [self updateStatusLabel];
        return;
      }
      
      // Now start the tunnel
      NSError *error = nil;
      BOOL started = [self.proxyManager.connection startVPNTunnelAndReturnError:&error];
      
      if (error) {
        NSLog(@"[App] ERROR starting tunnel: %@ (code: %ld)", error.localizedDescription, (long)error.code);
        self.proxyStatus = MTProxyStatusError;
        [self updateStatusLabel];
        [self showErrorAlert:@"Failed to Start Proxy" message:error.localizedDescription];
        return;
      }
      
      NSLog(@"[App] Tunnel start initiated (started=%d)", started);
    });
  }];
}

- (void)showErrorAlert:(NSString *)title message:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = title;
  alert.informativeText = message;
  alert.alertStyle = NSAlertStyleCritical;
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
}

- (void)stopProxy {
  if (!self.proxyManager) {
    NSLog(@"[App] No proxy manager to stop");
    return;
  }

  NSLog(@"[App] Stopping proxy...");
  self.proxyStatus = MTProxyStatusStopping;
  [self updateStatusLabel];

  [self.proxyManager.connection stopVPNTunnel];
}

#pragma mark - Actions

- (IBAction)proxySwitchChanged:(NSSwitch *)sender {
  NSLog(@"[App] Proxy switch changed: %@", 
      sender.state == NSControlStateValueOn ? @"ON" : @"OFF");
  
  if (sender.state == NSControlStateValueOn) {
    [self startProxy];
  } else {
    [self stopProxy];
  }
}

- (IBAction)addRule:(id)sender {
  AddRuleViewController *addVC =
      [[AddRuleViewController alloc] initWithNibName:@"AddRuleViewController"
                                              bundle:nil];
  addVC.completionHandler = ^(MTRule *_Nullable rule) {
    if (rule) {
      [[MTRuleManager sharedManager] addRule:rule];
    }
  };

  // Present as a window sheet
  NSWindow *addWindow = [NSWindow windowWithContentViewController:addVC];
  addWindow.title = @"Add Rule";
  addWindow.styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
  [addWindow setContentSize:NSMakeSize(380, 220)];
  
  [self.view.window beginSheet:addWindow completionHandler:^(NSModalResponse returnCode) {
    // Sheet dismissed
  }];
}

- (IBAction)removeRule:(id)sender {
  NSInteger selectedRow = self.rulesTableView.selectedRow;
  if (selectedRow < 0) {
    return;
  }

  MTRule *rule = [MTRuleManager sharedManager].rules[selectedRow];

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Delete Rule";
  alert.informativeText = [NSString
      stringWithFormat:@"Are you sure you want to delete the rule \"%@\"?",
                       rule.pattern];
  alert.alertStyle = NSAlertStyleWarning;
  [alert addButtonWithTitle:@"Delete"];
  [alert addButtonWithTitle:@"Cancel"];

  [alert
      beginSheetModalForWindow:self.view.window
             completionHandler:^(NSModalResponse returnCode) {
               if (returnCode == NSAlertFirstButtonReturn) {
                 [[MTRuleManager sharedManager] removeRuleAtIndex:selectedRow];
               }
             }];
}

- (IBAction)editRule:(id)sender {
  NSInteger selectedRow = self.rulesTableView.selectedRow;
  if (selectedRow < 0) {
    return;
  }

  MTRule *rule = [[MTRuleManager sharedManager].rules[selectedRow] copy];

  AddRuleViewController *editVC =
      [[AddRuleViewController alloc] initWithNibName:@"AddRuleViewController"
                                              bundle:nil];
  editVC.editingRule = rule;
  editVC.completionHandler = ^(MTRule *_Nullable updatedRule) {
    if (updatedRule) {
      [[MTRuleManager sharedManager] updateRule:updatedRule];
    }
  };

  // Present as a window sheet
  NSWindow *editWindow = [NSWindow windowWithContentViewController:editVC];
  editWindow.title = @"Edit Rule";
  editWindow.styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
  [editWindow setContentSize:NSMakeSize(380, 220)];
  
  [self.view.window beginSheet:editWindow completionHandler:^(NSModalResponse returnCode) {
    // Sheet dismissed
  }];
}

- (IBAction)installExtension:(id)sender {
  NSLog(@"[App] Installing system extension...");
  NSLog(@"[App] Extension bundle ID: %@", kMTExtensionBundleIdentifier);
  
  OSSystemExtensionRequest *request = [OSSystemExtensionRequest
      activationRequestForExtension:kMTExtensionBundleIdentifier
                              queue:dispatch_get_main_queue()];
  request.delegate = self;
  [[OSSystemExtensionManager sharedManager] submitRequest:request];
}

- (IBAction)uninstallExtension:(id)sender {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Uninstall Extension";
  alert.informativeText =
      @"Are you sure you want to uninstall the network extension?";
  alert.alertStyle = NSAlertStyleWarning;
  [alert addButtonWithTitle:@"Uninstall"];
  [alert addButtonWithTitle:@"Cancel"];

  [alert
      beginSheetModalForWindow:self.view.window
             completionHandler:^(NSModalResponse returnCode) {
               if (returnCode == NSAlertFirstButtonReturn) {
                 OSSystemExtensionRequest *request = [OSSystemExtensionRequest
                     deactivationRequestForExtension:
                         kMTExtensionBundleIdentifier
                                               queue:dispatch_get_main_queue()];
                 request.delegate = self;
                 [[OSSystemExtensionManager sharedManager]
                     submitRequest:request];
               }
             }];
}

- (IBAction)exportRules:(id)sender {
  NSSavePanel *savePanel = [NSSavePanel savePanel];
  savePanel.allowedContentTypes =
      @[ [UTType typeWithFilenameExtension:@"json"] ];
  savePanel.nameFieldStringValue = @"metric_rules.json";

  [savePanel beginSheetModalForWindow:self.view.window
                    completionHandler:^(NSModalResponse result) {
                      if (result == NSModalResponseOK && savePanel.URL) {
                        NSError *error = nil;
                        if (![[MTRuleManager sharedManager]
                                exportRulesToURL:savePanel.URL
                                           error:&error]) {
                          NSAlert *alert = [NSAlert alertWithError:error];
                          [alert runModal];
                        }
                      }
                    }];
}

- (IBAction)importRules:(id)sender {
  NSOpenPanel *openPanel = [NSOpenPanel openPanel];
  openPanel.allowedContentTypes =
      @[ [UTType typeWithFilenameExtension:@"json"] ];
  openPanel.allowsMultipleSelection = NO;

  [openPanel beginSheetModalForWindow:self.view.window
                    completionHandler:^(NSModalResponse result) {
                      if (result == NSModalResponseOK && openPanel.URL) {
                        NSError *error = nil;
                        if (![[MTRuleManager sharedManager]
                                importRulesFromURL:openPanel.URL
                                             error:&error]) {
                          NSAlert *alert = [NSAlert alertWithError:error];
                          [alert runModal];
                        }
                      }
                    }];
}

#pragma mark - Notifications

- (void)rulesDidChange:(NSNotification *)notification {
  [self.rulesTableView reloadData];
}

- (void)interfacesDidChange:(NSNotification *)notification {
  [self updateInterfaceLabels];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return [MTRuleManager sharedManager].rules.count;
}

#pragma mark - NSTableViewDelegate

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)row {
  MTRule *rule = [MTRuleManager sharedManager].rules[row];
  NSString *identifier = tableColumn.identifier;

  if ([identifier isEqualToString:@"enabled"]) {
    NSButton *checkbox = [tableView makeViewWithIdentifier:identifier
                                                     owner:self];
    if (!checkbox) {
      checkbox = [[NSButton alloc] init];
      checkbox.identifier = identifier;
      [checkbox setButtonType:NSButtonTypeSwitch];
      checkbox.title = @"";
      checkbox.target = self;
      checkbox.action = @selector(toggleRuleEnabled:);
    }
    checkbox.state =
        rule.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    checkbox.tag = row;
    return checkbox;
  }

  NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier
                                                          owner:self];
  if (!cellView) {
    cellView = [[NSTableCellView alloc] init];
    cellView.identifier = identifier;
    NSTextField *textField = [[NSTextField alloc] init];
    textField.bordered = NO;
    textField.editable = NO;
    textField.backgroundColor = [NSColor clearColor];
    cellView.textField = textField;
    [cellView addSubview:textField];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
      [textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor],
      [textField.trailingAnchor
          constraintEqualToAnchor:cellView.trailingAnchor],
      [textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor]
    ]];
  }

  if ([identifier isEqualToString:@"pattern"]) {
    cellView.textField.stringValue = rule.pattern;
  } else if ([identifier isEqualToString:@"interface"]) {
    cellView.textField.stringValue = rule.interfaceName;
  } else if ([identifier isEqualToString:@"comment"]) {
    cellView.textField.stringValue = rule.comment ?: @"";
  }

  return cellView;
}

- (void)toggleRuleEnabled:(NSButton *)sender {
  NSInteger row = sender.tag;
  if (row < 0 || row >= [MTRuleManager sharedManager].rules.count) {
    return;
  }

  MTRule *rule = [[MTRuleManager sharedManager].rules[row] copy];
  rule.enabled = (sender.state == NSControlStateValueOn);
  [[MTRuleManager sharedManager] updateRule:rule];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  self.removeButton.enabled = (self.rulesTableView.selectedRow >= 0);
}

// Drag and drop support
- (id<NSPasteboardWriting>)tableView:(NSTableView *)tableView
              pasteboardWriterForRow:(NSInteger)row {
  NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
  [item setString:[@(row) stringValue] forType:@"nz.owo.metric.rule"];
  return item;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation {
  if (dropOperation == NSTableViewDropAbove) {
    return NSDragOperationMove;
  }
  return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
  NSPasteboardItem *item =
      [[info draggingPasteboard] pasteboardItems].firstObject;
  NSString *rowString = [item stringForType:@"nz.owo.metric.rule"];
  NSInteger sourceRow = [rowString integerValue];

  [[MTRuleManager sharedManager] moveRuleAtIndex:sourceRow toIndex:row];
  return YES;
}

#pragma mark - OSSystemExtensionRequestDelegate

- (OSSystemExtensionReplacementAction)
                        request:(OSSystemExtensionRequest *)request
    actionForReplacingExtension:(OSSystemExtensionProperties *)existing
                  withExtension:(OSSystemExtensionProperties *)ext {
  return OSSystemExtensionReplacementActionReplace;
}

- (void)request:(OSSystemExtensionRequest *)request
    didFailWithError:(NSError *)error {
  NSLog(@"System extension request failed: %@", error);
  dispatch_async(dispatch_get_main_queue(), ^{
    NSLog(@"[App] Extension install failed: %@ (code: %ld)", 
        error.localizedDescription, (long)error.code);
    
    NSString *detailedMessage = error.localizedDescription;
    
    // Provide helpful guidance based on error
    if (error.code == 8) { // OSSystemExtensionErrorCodeExtensionCategoryInvalid
      detailedMessage = @"Extension category error.\n\n"
        @"This usually means:\n"
        @"1. Network Extension entitlement is not configured in Apple Developer Portal\n"
        @"2. Provisioning profile doesn't include App Proxy capability\n"
        @"3. App is not properly signed\n\n"
        @"Please check your Apple Developer account settings.";
    }
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Extension Installation Failed";
    alert.informativeText = detailedMessage;
    alert.alertStyle = NSAlertStyleCritical;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
  });
}

- (void)request:(OSSystemExtensionRequest *)request
    didFinishWithResult:(OSSystemExtensionRequestResult)result {
  NSLog(@"System extension request finished: %ld", (long)result);
  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateExtensionStatus];
    if (result == OSSystemExtensionRequestCompleted) {
      [self checkProxyStatus];
    } else if (result == OSSystemExtensionRequestWillCompleteAfterReboot) {
      NSAlert *alert = [[NSAlert alloc] init];
      alert.messageText = @"Reboot Required";
      alert.informativeText =
          @"Please reboot your Mac to complete the extension installation.";
      [alert addButtonWithTitle:@"OK"];
      [alert runModal];
    }
  });
}

- (void)requestNeedsUserApproval:(OSSystemExtensionRequest *)request {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Approval Required";
    alert.informativeText = @"Please approve the system extension in System "
                            @"Preferences > Privacy & Security.";
    [alert addButtonWithTitle:@"Open System Preferences"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
      [[NSWorkspace sharedWorkspace]
          openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple."
                                       @"preference.security?Privacy"]];
    }
  });
}

@end
