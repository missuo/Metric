//
//  AddRuleViewController.m
//  Metric
//
//  View controller implementation for adding/editing rules
//

#import "AddRuleViewController.h"
#import "IPAddressHelper.h"
#import "NetworkInterfaceManager.h"
#import "Rule.h"
#import "SharedConstants.h"

@interface AddRuleViewController () <NSTextFieldDelegate>

@property(weak) IBOutlet NSPopUpButton *typePopUp;
@property(weak) IBOutlet NSTextField *patternField;
@property(weak) IBOutlet NSPopUpButton *interfacePopUp;
@property(weak) IBOutlet NSTextField *commentField;
@property(weak) IBOutlet NSButton *saveButton;
@property(weak) IBOutlet NSButton *cancelButton;
@property(weak) IBOutlet NSTextField *errorLabel;
@property(weak) IBOutlet NSTextField *titleLabel;

@end

@implementation AddRuleViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  // Set preferred content size for sheet presentation
  self.preferredContentSize = NSMakeSize(380, 220);
  
  [self setupUI];
  [self populateInterfaces];

  if (self.editingRule) {
    [self populateWithRule:self.editingRule];
    self.titleLabel.stringValue = @"Edit Rule";
    self.saveButton.title = @"Save";
  } else {
    self.titleLabel.stringValue = @"Add Rule";
    self.saveButton.title = @"Add";
  }

  self.patternField.delegate = self;
  [self validateInput];
}

#pragma mark - Setup

- (void)setupUI {
  // Setup type popup - only CIDR supported
  [self.typePopUp removeAllItems];
  [self.typePopUp addItemWithTitle:@"CIDR (IP Range)"];
  // Host rules removed - they don't work reliably with transparent proxy
  // because DNS resolution happens before traffic reaches the proxy

  self.errorLabel.stringValue = @"";
  self.errorLabel.textColor = [NSColor systemRedColor];
}

- (void)populateInterfaces {
  [self.interfacePopUp removeAllItems];

  MTNetworkInterfaceManager *manager =
      [MTNetworkInterfaceManager sharedManager];
  NSArray<MTNetworkInterface *> *interfaces = manager.interfaces;

  // Only add interfaces that have an IP address
  for (MTNetworkInterface *iface in interfaces) {
    if (!iface.hasIPv4 && !iface.hasIPv6) {
      continue; // Skip interfaces without IP
    }

    NSString *title =
        [NSString stringWithFormat:@"%@ (%@)", iface.displayName,
                                   iface.ipv4Address ?: iface.ipv6Address];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                  action:nil
                                           keyEquivalent:@""];
    item.representedObject = iface.name;
    [self.interfacePopUp.menu addItem:item];
  }

  // Add option for custom interface name
  if (self.interfacePopUp.menu.itemArray.count > 0) {
    [self.interfacePopUp.menu addItem:[NSMenuItem separatorItem]];
  }
  NSMenuItem *customItem = [[NSMenuItem alloc] initWithTitle:@"Custom..."
                                                      action:nil
                                               keyEquivalent:@""];
  customItem.representedObject = @"__custom__";
  [self.interfacePopUp.menu addItem:customItem];
}

- (void)populateWithRule:(MTRule *)rule {
  // Set type
  [self.typePopUp selectItemAtIndex:(rule.type == MTRuleTypeCIDR) ? 0 : 1];

  // Set pattern
  self.patternField.stringValue = rule.pattern;

  // Set interface
  for (NSMenuItem *item in self.interfacePopUp.menu.itemArray) {
    if ([item.representedObject isEqualToString:rule.interfaceName]) {
      [self.interfacePopUp selectItem:item];
      break;
    }
  }

  // Set comment
  self.commentField.stringValue = rule.comment ?: @"";
}

#pragma mark - Validation

- (void)validateInput {
  NSString *error = [self currentValidationError];
  self.errorLabel.stringValue = error ?: @"";
  self.saveButton.enabled = (error == nil);
}

- (NSString *)currentValidationError {
  NSString *pattern = [self.patternField.stringValue
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];

  if (pattern.length == 0) {
    return @"Please enter a CIDR pattern (e.g., 192.168.1.0/24)";
  }

  // Only CIDR is supported
  if (![MTIPAddressHelper isValidCIDR:pattern]) {
    // Check if it's at least a valid IP
    if ([MTIPAddressHelper isValidIPv4Address:pattern]) {
      return nil; // Valid single IP (will be treated as /32)
    }
    return @"Invalid CIDR format. Use: IP/prefix (e.g., 192.168.1.0/24)";
  }

  NSString *interfaceName = self.interfacePopUp.selectedItem.representedObject;
  if (!interfaceName || interfaceName.length == 0 ||
      [interfaceName isEqualToString:@"__custom__"]) {
    return @"Please select a network interface";
  }

  return nil;
}

#pragma mark - Actions

- (IBAction)typeChanged:(id)sender {
  [self validateInput];
}

- (IBAction)interfaceChanged:(id)sender {
  NSString *selected = self.interfacePopUp.selectedItem.representedObject;
  if ([selected isEqualToString:@"__custom__"]) {
    [self showCustomInterfaceDialog];
  }
  [self validateInput];
}

- (void)showCustomInterfaceDialog {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Enter Interface Name";
  alert.informativeText = @"Enter the network interface name (e.g., en0, en1):";
  alert.alertStyle = NSAlertStyleInformational;
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];

  NSTextField *input =
      [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
  input.placeholderString = @"en0";
  alert.accessoryView = input;

  [alert
      beginSheetModalForWindow:self.view.window
             completionHandler:^(NSModalResponse returnCode) {
               if (returnCode == NSAlertFirstButtonReturn &&
                   input.stringValue.length > 0) {
                 // Add custom interface to popup
                 NSString *title = input.stringValue;
                 NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                               action:nil
                                                        keyEquivalent:@""];
                 item.representedObject = title;
                 [self.interfacePopUp.menu
                     insertItem:item
                        atIndex:self.interfacePopUp.menu.itemArray.count - 2];
                 [self.interfacePopUp selectItem:item];
               } else {
                 // Select first real interface
                 if (self.interfacePopUp.menu.itemArray.count > 2) {
                   [self.interfacePopUp selectItemAtIndex:0];
                 }
               }
               [self validateInput];
             }];
}

- (IBAction)save:(id)sender {
  if ([self currentValidationError] != nil) {
    return;
  }

  MTRule *rule =
      self.editingRule ? [self.editingRule copy] : [[MTRule alloc] init];

  rule.type = MTRuleTypeCIDR;  // Only CIDR is supported
  rule.pattern = [self.patternField.stringValue
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  rule.interfaceName = self.interfacePopUp.selectedItem.representedObject;

  NSString *comment = [self.commentField.stringValue
      stringByTrimmingCharactersInSet:[NSCharacterSet
                                          whitespaceAndNewlineCharacterSet]];
  rule.comment = comment.length > 0 ? comment : nil;

  if (self.completionHandler) {
    self.completionHandler(rule);
  }

  [self closeWindow];
}

- (IBAction)cancel:(id)sender {
  if (self.completionHandler) {
    self.completionHandler(nil);
  }

  [self closeWindow];
}

- (void)closeWindow {
  // Close as sheet or regular window
  NSWindow *window = self.view.window;
  NSWindow *sheetParent = window.sheetParent;
  if (sheetParent) {
    [sheetParent endSheet:window];
  } else {
    [window close];
  }
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidChange:(NSNotification *)obj {
  [self validateInput];
}

@end
