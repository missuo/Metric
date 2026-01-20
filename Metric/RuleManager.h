//
//  RuleManager.h
//  Metric
//
//  Manages rules storage and persistence
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MTRule;

@interface MTRuleManager : NSObject

// Singleton
+ (instancetype)sharedManager;

// Rules array (KVO observable)
@property (nonatomic, readonly) NSArray<MTRule *> *rules;

// CRUD operations
- (void)addRule:(MTRule *)rule;
- (void)insertRule:(MTRule *)rule atIndex:(NSUInteger)index;
- (void)removeRule:(MTRule *)rule;
- (void)removeRuleAtIndex:(NSUInteger)index;
- (void)updateRule:(MTRule *)rule;
- (void)moveRuleAtIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex;

// Bulk operations
- (void)setRules:(NSArray<MTRule *> *)rules;
- (void)removeAllRules;

// Query
- (nullable MTRule *)ruleWithId:(NSString *)ruleId;
- (NSArray<MTRule *> *)enabledRules;
- (NSArray<MTRule *> *)rulesForInterface:(NSString *)interfaceName;

// Persistence
- (void)saveRules;
- (void)loadRules;

// Import/Export
- (BOOL)exportRulesToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)importRulesFromURL:(NSURL *)url error:(NSError **)error;

// Sync rules to extension
- (void)syncRulesToExtension;

@end

// Notifications
extern NSNotificationName const MTRuleManagerDidChangeNotification;
extern NSString * const MTRuleManagerChangeTypeKey;
extern NSString * const MTRuleManagerChangedRuleKey;
extern NSString * const MTRuleManagerChangedIndexKey;

typedef NS_ENUM(NSInteger, MTRuleManagerChangeType) {
    MTRuleManagerChangeTypeAdd,
    MTRuleManagerChangeTypeRemove,
    MTRuleManagerChangeTypeUpdate,
    MTRuleManagerChangeTypeMove,
    MTRuleManagerChangeTypeReload
};

NS_ASSUME_NONNULL_END
