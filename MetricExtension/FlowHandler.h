//
//  FlowHandler.h
//  MetricExtension
//
//  Handles individual network flows
//

#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

NS_ASSUME_NONNULL_BEGIN

@class MTRuleEngine;

typedef void(^MTFlowCompletionHandler)(void);

@interface MTFlowHandler : NSObject

@property (nonatomic, copy, nullable) MTFlowCompletionHandler completionHandler;

// Initialize for TCP flow
- (instancetype)initWithFlow:(NEAppProxyTCPFlow *)flow
               interfaceName:(NSString *)interfaceName
                    provider:(NETransparentProxyProvider *)provider;

// Initialize for UDP flow
- (instancetype)initWithUDPFlow:(NEAppProxyUDPFlow *)flow
                     ruleEngine:(MTRuleEngine *)ruleEngine
                       provider:(NETransparentProxyProvider *)provider;

// Start handling the flow
- (void)start;

// Close the flow handler
- (void)close;

@end

NS_ASSUME_NONNULL_END
