//
//  RuleEngine.h
//  MetricExtension
//
//  Rule matching engine for the proxy
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MTRuleModel;

@interface MTRuleEngine : NSObject

// Loaded rules
@property (nonatomic, readonly) NSArray<MTRuleModel *> *rules;

// Load rules from shared storage
- (void)loadRules;

// Load rules from array (passed via providerConfiguration)
- (void)loadRulesFromArray:(NSArray<NSDictionary *> *)dictArray;

// Match rules against destination
- (nullable MTRuleModel *)matchRuleForIP:(nullable NSString *)ipAddress
                                hostname:(nullable NSString *)hostname;

// Direct matching methods
- (nullable MTRuleModel *)matchCIDRRuleForIP:(NSString *)ipAddress;
- (nullable MTRuleModel *)matchHostRuleForHostname:(NSString *)hostname;

@end

NS_ASSUME_NONNULL_END
