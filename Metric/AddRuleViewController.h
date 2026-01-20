//
//  AddRuleViewController.h
//  Metric
//
//  View controller for adding/editing rules
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MTRule;

typedef void(^MTAddRuleCompletionHandler)(MTRule * _Nullable rule);

@interface AddRuleViewController : NSViewController

// If set, we're editing an existing rule
@property (nonatomic, strong, nullable) MTRule *editingRule;

// Called when the user saves or cancels
@property (nonatomic, copy, nullable) MTAddRuleCompletionHandler completionHandler;

@end

NS_ASSUME_NONNULL_END
