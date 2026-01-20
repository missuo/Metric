//
//  TransparentProxyProvider.m
//  MetricExtension
//
//  NETransparentProxyProvider implementation
//

#import "TransparentProxyProvider.h"
#import "FlowHandler.h"
#import "RuleEngine.h"
#import "RuleModel.h"
#import "SharedConstants.h"
#import <Network/Network.h>
#import <arpa/inet.h>

@interface TransparentProxyProvider ()

@property(nonatomic, strong) MTRuleEngine *ruleEngine;
@property(nonatomic, strong)
    NSMutableDictionary<NSString *, MTFlowHandler *> *flowHandlers;
@property(nonatomic, strong) dispatch_queue_t flowQueue;

@end

@implementation TransparentProxyProvider

- (instancetype)init {
  self = [super init];
  if (self) {
    _ruleEngine = [[MTRuleEngine alloc] init];
    _flowHandlers = [NSMutableDictionary dictionary];
    _flowQueue = dispatch_queue_create("nz.owo.metric.extension.flowQueue",
                                       DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

#pragma mark - Provider Lifecycle

- (void)startProxyWithOptions:(NSDictionary<NSString *, id> *)options
            completionHandler:(void (^)(NSError *_Nullable))completionHandler {

  NSLog(@"[MetricExt] ========== startProxyWithOptions called ==========");
  [self sendLogToApp:@"[Extension] Starting transparent proxy..." level:MTLogLevelInfo];

  // Load rules from providerConfiguration (passed from main app)
  NETunnelProviderProtocol *protocol = (NETunnelProviderProtocol *)self.protocolConfiguration;
  NSDictionary *providerConfig = protocol.providerConfiguration;
  NSArray *rulesArray = providerConfig[@"rules"];
  
  NSLog(@"[MetricExt] providerConfiguration: %@", providerConfig);
  NSLog(@"[MetricExt] Rules from config: %lu", (unsigned long)rulesArray.count);
  
  if (rulesArray && rulesArray.count > 0) {
    [self.ruleEngine loadRulesFromArray:rulesArray];
    [self sendLogToApp:[NSString stringWithFormat:@"[Extension] Loaded %lu rules from config", (unsigned long)rulesArray.count] level:MTLogLevelInfo];
  } else {
    [self sendLogToApp:@"[Extension] No rules in providerConfiguration" level:MTLogLevelWarning];
  }

  // Register for rule change notifications
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(handleRulesDidChange:)
             name:kMTRulesDidChangeNotification
           object:nil];

  [self sendLogToApp:[NSString stringWithFormat:@"[Extension] Loaded %lu rules", (unsigned long)self.ruleEngine.rules.count] level:MTLogLevelInfo];

  // Create NETransparentProxyNetworkSettings - this is required for transparent proxy
  NETransparentProxyNetworkSettings *settings =
      [[NETransparentProxyNetworkSettings alloc] initWithTunnelRemoteAddress:@"127.0.0.1"];

  // Configure includedNetworkRules to specify what traffic to intercept
  // Only intercept TCP for now - UDP (including DNS) will use system routing
  NSMutableArray<NENetworkRule *> *rules = [NSMutableArray array];

  // Match all outbound TCP traffic
  NENetworkRule *tcpRule = [[NENetworkRule alloc]
      initWithRemoteNetwork:nil
               remotePrefix:0
               localNetwork:nil
                localPrefix:0
                   protocol:NENetworkRuleProtocolTCP
                  direction:NETrafficDirectionOutbound];
  [rules addObject:tcpRule];

  // NOTE: Not intercepting UDP to allow DNS and other UDP services to work normally
  // If UDP routing is needed in the future, we need to properly forward unmatched datagrams

  settings.includedNetworkRules = rules;

  [self sendLogToApp:@"[Extension] Setting network rules (TCP outbound only)..." level:MTLogLevelInfo];

  __weak typeof(self) weakSelf = self;
  [self setTunnelNetworkSettings:settings
               completionHandler:^(NSError *_Nullable error) {
                  if (error) {
                    [weakSelf sendLogToApp:[NSString stringWithFormat:@"[Extension] ERROR: Failed to set network settings: %@", error.localizedDescription] level:MTLogLevelError];
                    completionHandler(error);
                  } else {
                    [weakSelf sendLogToApp:@"[Extension] Network settings applied successfully" level:MTLogLevelInfo];
                    completionHandler(nil);
                  }
               }];
}

- (void)stopProxyWithReason:(NEProviderStopReason)reason
          completionHandler:(void (^)(void))completionHandler {

  NSLog(@"[Metric] Stopping transparent proxy (reason: %ld)", (long)reason);

  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];

  // Close all flow handlers
  dispatch_sync(self.flowQueue, ^{
    for (MTFlowHandler *handler in self.flowHandlers.allValues) {
      [handler close];
    }
    [self.flowHandlers removeAllObjects];
  });

  completionHandler();
}

#pragma mark - Flow Handling

- (BOOL)handleNewFlow:(NEAppProxyFlow *)flow {
  // Log every flow for debugging
  NSString *flowType = [flow isKindOfClass:[NEAppProxyTCPFlow class]] ? @"TCP" : @"UDP";
  NSString *appId = flow.metaData.sourceAppSigningIdentifier ?: @"unknown";

  NSLog(@"[MetricExt] handleNewFlow: %@ from %@, rules count: %lu", 
        flowType, appId, (unsigned long)self.ruleEngine.rules.count);

  [self sendLogToApp:[NSString stringWithFormat:@"[Flow] New %@ from %@", flowType, appId] level:MTLogLevelDebug];

  // Determine the destination endpoint
  NWEndpoint *remoteEndpoint = nil;
  NSString *remoteHostname = nil;  // Original hostname from "connect by name" API

  if ([flow isKindOfClass:[NEAppProxyTCPFlow class]]) {
    NEAppProxyTCPFlow *tcpFlow = (NEAppProxyTCPFlow *)flow;
    remoteEndpoint = tcpFlow.remoteEndpoint;
    remoteHostname = tcpFlow.remoteHostname;  // Get hostname if available
    
    NSLog(@"[MetricExt] TCP flow remoteHostname: %@", remoteHostname ?: @"(nil)");
  } else if ([flow isKindOfClass:[NEAppProxyUDPFlow class]]) {
    [self sendLogToApp:@"[Flow] Handling UDP flow" level:MTLogLevelDebug];
    return [self handleUDPFlow:(NEAppProxyUDPFlow *)flow];
  }

  if (!remoteEndpoint) {
    [self sendLogToApp:@"[Flow] No remote endpoint, rejecting" level:MTLogLevelWarning];
    return NO;
  }

  // Extract destination info
  NSString *destinationHost = remoteHostname;  // Prefer remoteHostname if available
  NSString *destinationIP = nil;

  if ([remoteEndpoint isKindOfClass:[NWHostEndpoint class]]) {
    NWHostEndpoint *hostEndpoint = (NWHostEndpoint *)remoteEndpoint;
    NSString *endpointHost = hostEndpoint.hostname;
    NSString *port = hostEndpoint.port;

    [self sendLogToApp:[NSString stringWithFormat:@"[Flow] Endpoint: %@:%@, remoteHostname: %@", 
          endpointHost, port, remoteHostname ?: @"(nil)"] level:MTLogLevelDebug];

    // Extract IP from endpoint (could be IP or hostname)
    if ([self isIPAddress:endpointHost]) {
      destinationIP = endpointHost;
    } else if (!destinationHost) {
      // If remoteHostname was nil, use endpoint hostname
      destinationHost = endpointHost;
    }
  }

  // Log rule matching details
  [self sendLogToApp:[NSString stringWithFormat:@"[Flow] Matching - IP: %@, Host: %@, Rules count: %lu", 
        destinationIP ?: @"(none)", 
        destinationHost ?: @"(none)",
        (unsigned long)self.ruleEngine.rules.count] level:MTLogLevelDebug];

  // Match against rules
  MTRuleModel *matchedRule = [self.ruleEngine matchRuleForIP:destinationIP
                                                    hostname:destinationHost];

  if (!matchedRule) {
    [self sendLogToApp:[NSString stringWithFormat:@"[Flow] No rule matched for %@ - using default route",
          destinationIP ?: destinationHost ?: @"unknown"] level:MTLogLevelInfo];
    // Return NO to let the system handle this flow normally
    return NO;
  }

  [self sendLogToApp:[NSString stringWithFormat:@"[Flow] MATCHED: %@ -> %@ (pattern: %@)", 
        destinationIP ?: destinationHost, matchedRule.interfaceName, matchedRule.pattern] level:MTLogLevelInfo];

  // Create a flow handler for TCP flow
  MTFlowHandler *handler =
      [[MTFlowHandler alloc] initWithFlow:(NEAppProxyTCPFlow *)flow
                            interfaceName:matchedRule.interfaceName
                                 provider:self];

  NSString *flowId = [[NSUUID UUID] UUIDString];

  dispatch_sync(self.flowQueue, ^{
    self.flowHandlers[flowId] = handler;
  });

  handler.completionHandler = ^{
    dispatch_sync(self.flowQueue, ^{
      [self.flowHandlers removeObjectForKey:flowId];
    });
  };

  [handler start];

  return YES;
}

- (BOOL)handleUDPFlow:(NEAppProxyUDPFlow *)flow {
  // Check if we have any rules at all - if not, let system handle UDP
  if (self.ruleEngine.rules.count == 0) {
    [self sendLogToApp:@"[Flow] No rules defined, letting system handle UDP" level:MTLogLevelDebug];
    return NO;
  }
  
  // For UDP, we need to handle datagrams individually
  MTFlowHandler *handler =
      [[MTFlowHandler alloc] initWithUDPFlow:flow
                                  ruleEngine:self.ruleEngine
                                    provider:self];

  NSString *flowId = [[NSUUID UUID] UUIDString];

  dispatch_sync(self.flowQueue, ^{
    self.flowHandlers[flowId] = handler;
  });

  handler.completionHandler = ^{
    dispatch_sync(self.flowQueue, ^{
      [self.flowHandlers removeObjectForKey:flowId];
    });
  };

  [handler start];

  return YES;
}

#pragma mark - Rule Updates

- (void)handleRulesDidChange:(NSNotification *)notification {
  NSLog(@"[Metric] Rules changed, reloading...");
  [self.ruleEngine loadRules];
  NSLog(@"[Metric] Reloaded %lu rules",
        (unsigned long)self.ruleEngine.rules.count);
}

#pragma mark - Helpers

- (BOOL)isIPAddress:(NSString *)string {
  if (!string)
    return NO;

  struct in_addr addr4;
  struct in6_addr addr6;

  return (inet_pton(AF_INET, [string UTF8String], &addr4) == 1 ||
          inet_pton(AF_INET6, [string UTF8String], &addr6) == 1);
}

#pragma mark - Logging

- (void)sendLogToApp:(NSString *)format, ... {
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  [self sendLogToApp:message level:MTLogLevelInfo];
}

- (void)sendLogToApp:(NSString *)message level:(MTLogLevel)level {
  // Always log to system log
  NSLog(@"[MetricExt] %@", message);

  // Also try distributed notification (may not work in system extension)
  NSDictionary *userInfo = @{
    kMTLogMessageKey: message,
    kMTLogTimestampKey: @([[NSDate date] timeIntervalSince1970]),
    kMTLogLevelKey: @(level)
  };

  [[NSDistributedNotificationCenter defaultCenter]
      postNotificationName:kMTLogMessageNotification
                    object:nil
                  userInfo:userInfo
        deliverImmediately:YES];
  
  // Also write to shared file for debugging
  [self writeLogToSharedFile:message level:level];
}

- (void)writeLogToSharedFile:(NSString *)message level:(MTLogLevel)level {
  NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:kMTAppGroupIdentifier];
  
  NSMutableArray *logs = [[shared arrayForKey:@"MTExtensionLogs"] mutableCopy] ?: [NSMutableArray array];
  
  // Keep only last 100 logs
  while (logs.count > 100) {
    [logs removeObjectAtIndex:0];
  }
  
  NSString *levelStr = @"INFO";
  if (level == MTLogLevelDebug) levelStr = @"DEBUG";
  else if (level == MTLogLevelWarning) levelStr = @"WARN";
  else if (level == MTLogLevelError) levelStr = @"ERROR";
  
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.dateFormat = @"HH:mm:ss";
  NSString *timestamp = [formatter stringFromDate:[NSDate date]];
  
  NSString *logEntry = [NSString stringWithFormat:@"[%@] [%@] %@", timestamp, levelStr, message];
  [logs addObject:logEntry];
  
  [shared setObject:logs forKey:@"MTExtensionLogs"];
  [shared synchronize];
}

@end
