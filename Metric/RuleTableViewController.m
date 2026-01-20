//
//  RuleTableViewController.m
//  Metric
//
//  Table view controller implementation
//

#import "RuleTableViewController.h"
#import "Rule.h"
#import "RuleManager.h"

@interface RuleTableViewController ()

@end

@implementation RuleTableViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  self.tableView.dataSource = self;
  self.tableView.delegate = self;

  // Register for drag and drop
  [self.tableView registerForDraggedTypes:@[ @"nz.owo.metric.rule" ]];

  // Observe rule changes
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(rulesDidChange:)
             name:MTRuleManagerDidChangeNotification
           object:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadData {
  [self.tableView reloadData];
}

#pragma mark - Notifications

- (void)rulesDidChange:(NSNotification *)notification {
  [self.tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
  return [MTRuleManager sharedManager].rules.count;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
  MTRule *rule = [MTRuleManager sharedManager].rules[row];
  NSString *identifier = tableColumn.identifier;

  if ([identifier isEqualToString:@"enabled"]) {
    return @(rule.enabled);
  } else if ([identifier isEqualToString:@"type"]) {
    return rule.typeString;
  } else if ([identifier isEqualToString:@"pattern"]) {
    return rule.pattern;
  } else if ([identifier isEqualToString:@"interface"]) {
    return rule.interfaceName;
  } else if ([identifier isEqualToString:@"comment"]) {
    return rule.comment ?: @"";
  }

  return nil;
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)object
    forTableColumn:(NSTableColumn *)tableColumn
               row:(NSInteger)row {
  if ([tableColumn.identifier isEqualToString:@"enabled"]) {
    MTRule *rule = [[MTRuleManager sharedManager].rules[row] copy];
    rule.enabled = [object boolValue];
    [[MTRuleManager sharedManager] updateRule:rule];
  }
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
      checkbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
      checkbox.identifier = identifier;
      [checkbox setButtonType:NSButtonTypeSwitch];
      checkbox.title = @"";
    }
    checkbox.state =
        rule.enabled ? NSControlStateValueOn : NSControlStateValueOff;
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
    textField.drawsBackground = NO;
    textField.lineBreakMode = NSLineBreakByTruncatingTail;
    [cellView addSubview:textField];
    cellView.textField = textField;

    textField.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
      [textField.leadingAnchor constraintEqualToAnchor:cellView.leadingAnchor
                                              constant:2],
      [textField.trailingAnchor constraintEqualToAnchor:cellView.trailingAnchor
                                               constant:-2],
      [textField.centerYAnchor constraintEqualToAnchor:cellView.centerYAnchor]
    ]];
  }

  NSString *value = @"";
  if ([identifier isEqualToString:@"type"]) {
    value = rule.typeString;
  } else if ([identifier isEqualToString:@"pattern"]) {
    value = rule.pattern;
  } else if ([identifier isEqualToString:@"interface"]) {
    value = rule.interfaceName;
  } else if ([identifier isEqualToString:@"comment"]) {
    value = rule.comment ?: @"";
  }

  cellView.textField.stringValue = value;
  return cellView;
}

#pragma mark - Drag and Drop

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
  NSPasteboardItem *item = info.draggingPasteboard.pasteboardItems.firstObject;
  NSString *rowString = [item stringForType:@"nz.owo.metric.rule"];
  if (!rowString) {
    return NO;
  }

  NSInteger sourceRow = [rowString integerValue];
  [[MTRuleManager sharedManager] moveRuleAtIndex:sourceRow toIndex:row];
  return YES;
}

@end
