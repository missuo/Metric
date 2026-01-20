//
//  RuleTableViewController.h
//  Metric
//
//  Table view controller for displaying rules
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RuleTableViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

@property (weak) IBOutlet NSTableView *tableView;

- (void)reloadData;

@end

NS_ASSUME_NONNULL_END
