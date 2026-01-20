//
//  FlowHandler.m
//  MetricExtension
//
//  Flow handling implementation
//

#import "FlowHandler.h"
#import "RuleEngine.h"
#import "RuleModel.h"
#import "SharedConstants.h"
#import <Network/Network.h>
#import <arpa/inet.h>

@interface MTFlowHandler ()

// Flow references
@property(nonatomic, strong, nullable) NEAppProxyTCPFlow *tcpFlow;
@property(nonatomic, strong, nullable) NEAppProxyUDPFlow *udpFlow;
@property(nonatomic, weak) NETransparentProxyProvider *provider;

// Outbound connection
@property(nonatomic, strong, nullable) nw_connection_t connection;
@property(nonatomic, strong) dispatch_queue_t queue;

// Configuration
@property(nonatomic, copy) NSString *interfaceName;
@property(nonatomic, strong, nullable) MTRuleEngine *ruleEngine;

// State
@property(nonatomic, assign) BOOL isRunning;
@property(nonatomic, assign) BOOL isClosed;

@end

@implementation MTFlowHandler

#pragma mark - Initialization

- (instancetype)initWithFlow:(NEAppProxyTCPFlow *)flow
               interfaceName:(NSString *)interfaceName
                    provider:(NETransparentProxyProvider *)provider {
  self = [super init];
  if (self) {
    _tcpFlow = flow;
    _interfaceName = [interfaceName copy];
    _provider = provider;
    _queue = dispatch_queue_create("nz.owo.metric.flowhandler",
                                   DISPATCH_QUEUE_SERIAL);
    _isRunning = NO;
    _isClosed = NO;
  }
  return self;
}

- (instancetype)initWithUDPFlow:(NEAppProxyUDPFlow *)flow
                     ruleEngine:(MTRuleEngine *)ruleEngine
                       provider:(NETransparentProxyProvider *)provider {
  self = [super init];
  if (self) {
    _udpFlow = flow;
    _ruleEngine = ruleEngine;
    _provider = provider;
    _queue = dispatch_queue_create("nz.owo.metric.flowhandler.udp",
                                   DISPATCH_QUEUE_SERIAL);
    _isRunning = NO;
    _isClosed = NO;
  }
  return self;
}

#pragma mark - Lifecycle

- (void)start {
  if (self.isRunning || self.isClosed) {
    return;
  }

  self.isRunning = YES;

  if (self.tcpFlow) {
    [self startTCPFlow];
  } else if (self.udpFlow) {
    [self startUDPFlow];
  }
}

- (void)close {
  if (self.isClosed) {
    return;
  }

  self.isClosed = YES;
  self.isRunning = NO;

  if (self.connection) {
    nw_connection_cancel(self.connection);
    self.connection = nil;
  }

  if (self.tcpFlow) {
    [self.tcpFlow closeReadWithError:nil];
    [self.tcpFlow closeWriteWithError:nil];
  }

  if (self.udpFlow) {
    [self.udpFlow closeReadWithError:nil];
    [self.udpFlow closeWriteWithError:nil];
  }

  if (self.completionHandler) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self.completionHandler) {
        self.completionHandler();
      }
    });
  }
}

#pragma mark - TCP Flow Handling

- (void)startTCPFlow {
  NWEndpoint *remoteEndpoint = self.tcpFlow.remoteEndpoint;

  if (![remoteEndpoint isKindOfClass:[NWHostEndpoint class]]) {
    NSLog(@"[FlowHandler] Unsupported endpoint type");
    [self close];
    return;
  }

  NWHostEndpoint *hostEndpoint = (NWHostEndpoint *)remoteEndpoint;
  NSString *host = hostEndpoint.hostname;
  NSString *port = hostEndpoint.port;

  NSLog(@"[FlowHandler] Starting TCP flow to %@:%@ via %@", host, port,
        self.interfaceName);

  // Create NWConnection bound to specific interface
  nw_endpoint_t endpoint =
      nw_endpoint_create_host([host UTF8String], [port UTF8String]);

  nw_parameters_t parameters = nw_parameters_create_secure_tcp(
      NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);

  // Bind to specific interface
  [self bindParameters:parameters toInterface:self.interfaceName];

  self.connection = nw_connection_create(endpoint, parameters);

  __weak typeof(self) weakSelf = self;

  nw_connection_set_state_changed_handler(
      self.connection, ^(nw_connection_state_t state, nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf)
          return;

        switch (state) {
        case nw_connection_state_ready: {
          NSLog(@"[FlowHandler] Connection ready");
          [strongSelf.tcpFlow
              openWithLocalEndpoint:nil
                  completionHandler:^(NSError *openError) {
                    if (openError) {
                      NSLog(@"[FlowHandler] Failed to open flow: %@",
                            openError);
                      [strongSelf close];
                      return;
                    }
                    [strongSelf startReadingFromFlow];
                    [strongSelf startReadingFromConnection];
                  }];
          break;
        }
        case nw_connection_state_failed: {
          NSLog(@"[FlowHandler] Connection failed: %@", error);
          [strongSelf close];
          break;
        }
        case nw_connection_state_cancelled: {
          NSLog(@"[FlowHandler] Connection cancelled");
          [strongSelf close];
          break;
        }
        default:
          break;
        }
      });

  nw_connection_set_queue(self.connection, self.queue);
  nw_connection_start(self.connection);
}

- (void)startReadingFromFlow {
  if (self.isClosed)
    return;

  __weak typeof(self) weakSelf = self;

  [self.tcpFlow readDataWithCompletionHandler:^(NSData *data, NSError *error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.isClosed)
      return;

    if (error) {
      NSLog(@"[FlowHandler] Error reading from flow: %@", error);
      [strongSelf close];
      return;
    }

    if (data.length == 0) {
      // EOF
      NSLog(@"[FlowHandler] Flow EOF");
      [strongSelf close];
      return;
    }

    // Forward data to connection
    dispatch_data_t dispatchData =
        dispatch_data_create(data.bytes, data.length, strongSelf.queue,
                             DISPATCH_DATA_DESTRUCTOR_DEFAULT);

    nw_connection_send(
        strongSelf.connection, dispatchData,
        NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t sendError) {
          if (sendError) {
            NSLog(@"[FlowHandler] Error sending to connection: %@", sendError);
            [strongSelf close];
            return;
          }

          // Continue reading
          [strongSelf startReadingFromFlow];
        });
  }];
}

- (void)startReadingFromConnection {
  if (self.isClosed)
    return;

  __weak typeof(self) weakSelf = self;

  nw_connection_receive(
      self.connection, 1, UINT32_MAX,
      ^(dispatch_data_t content, nw_content_context_t context, bool is_complete,
        nw_error_t error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.isClosed)
          return;

        if (error) {
          NSLog(@"[FlowHandler] Error receiving from connection: %@", error);
          [strongSelf close];
          return;
        }

        if (content) {
          // Convert dispatch_data_t to NSData
          NSMutableData *nsData = [NSMutableData data];
          dispatch_data_apply(content,
                              ^bool(dispatch_data_t region, size_t offset,
                                    const void *buffer, size_t size) {
                                [nsData appendBytes:buffer length:size];
                                return true;
                              });

          // Write to flow
          [strongSelf.tcpFlow
                          writeData:nsData
              withCompletionHandler:^(NSError *writeError) {
                if (writeError) {
                  NSLog(@"[FlowHandler] Error writing to flow: %@", writeError);
                  [strongSelf close];
                  return;
                }

                if (!is_complete) {
                  // Continue reading
                  [strongSelf startReadingFromConnection];
                } else {
                  [strongSelf close];
                }
              }];
        } else if (is_complete) {
          [strongSelf close];
        } else {
          // Continue reading
          [strongSelf startReadingFromConnection];
        }
      });
}

#pragma mark - UDP Flow Handling

- (void)startUDPFlow {
  NSLog(@"[FlowHandler] Starting UDP flow");

  __weak typeof(self) weakSelf = self;

  [self.udpFlow
      openWithLocalEndpoint:nil
          completionHandler:^(NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf)
              return;

            if (error) {
              NSLog(@"[FlowHandler] Failed to open UDP flow: %@", error);
              [strongSelf close];
              return;
            }

            [strongSelf startReadingUDPDatagrams];
          }];
}

- (void)startReadingUDPDatagrams {
  if (self.isClosed)
    return;

  __weak typeof(self) weakSelf = self;

  [self.udpFlow readDatagramsWithCompletionHandler:^(
                    NSArray<NSData *> *datagrams,
                    NSArray<NWEndpoint *> *endpoints, NSError *error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf || strongSelf.isClosed)
      return;

    if (error) {
      NSLog(@"[FlowHandler] Error reading UDP datagrams: %@", error);
      [strongSelf close];
      return;
    }

    if (datagrams.count == 0) {
      [strongSelf close];
      return;
    }

    // Process each datagram
    for (NSUInteger i = 0; i < datagrams.count; i++) {
      NSData *datagram = datagrams[i];
      NWEndpoint *endpoint = endpoints[i];

      [strongSelf forwardUDPDatagram:datagram toEndpoint:endpoint];
    }

    // Continue reading
    [strongSelf startReadingUDPDatagrams];
  }];
}

- (void)forwardUDPDatagram:(NSData *)datagram
                toEndpoint:(NWEndpoint *)endpoint {
  if (![endpoint isKindOfClass:[NWHostEndpoint class]]) {
    return;
  }

  NWHostEndpoint *hostEndpoint = (NWHostEndpoint *)endpoint;
  NSString *host = hostEndpoint.hostname;

  // Determine interface based on rules
  NSString *interfaceName = nil;

  if (self.ruleEngine) {
    NSString *ip = [self isIPAddress:host] ? host : nil;
    NSString *hostname = ip ? nil : host;

    MTRuleModel *rule = [self.ruleEngine matchRuleForIP:ip hostname:hostname];
    if (rule) {
      interfaceName = rule.interfaceName;
      NSLog(@"[FlowHandler] UDP matched rule: %@ -> %@", rule.pattern, interfaceName);
    }
  }

  // If no rule matched, still forward through default route (no interface binding)
  if (!interfaceName) {
    NSLog(@"[FlowHandler] UDP no rule matched for %@, using default route", host);
  }

  // Create UDP connection for this datagram
  nw_endpoint_t nwEndpoint = nw_endpoint_create_host(
      [host UTF8String], [hostEndpoint.port UTF8String]);

  nw_parameters_t parameters = nw_parameters_create_secure_udp(
      NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);

  [self bindParameters:parameters toInterface:interfaceName];

  nw_connection_t udpConnection = nw_connection_create(nwEndpoint, parameters);

  __weak typeof(self) weakSelf = self;

  nw_connection_set_state_changed_handler(udpConnection, ^(
                                              nw_connection_state_t state,
                                              nw_error_t error) {
    if (state == nw_connection_state_ready) {
      dispatch_data_t data = dispatch_data_create(
          datagram.bytes, datagram.length, dispatch_get_main_queue(),
          DISPATCH_DATA_DESTRUCTOR_DEFAULT);

      nw_connection_send(
          udpConnection, data, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
          ^(nw_error_t sendError) {
            // Start receiving response
            nw_connection_receive(
                udpConnection, 1, UINT32_MAX,
                ^(dispatch_data_t content, nw_content_context_t ctx,
                  bool is_complete, nw_error_t recvError) {
                  __strong typeof(weakSelf) strongSelf = weakSelf;
                  if (!strongSelf || strongSelf.isClosed) {
                    nw_connection_cancel(udpConnection);
                    return;
                  }

                  if (content) {
                    NSMutableData *responseData = [NSMutableData data];
                    dispatch_data_apply(
                        content, ^bool(dispatch_data_t region, size_t offset,
                                       const void *buffer, size_t size) {
                          [responseData appendBytes:buffer length:size];
                          return true;
                        });

                    // Write response back to flow
                    [strongSelf.udpFlow
                           writeDatagrams:@[ responseData ]
                          sentByEndpoints:@[ endpoint ]
                        completionHandler:^(NSError *writeError) {
                          if (writeError) {
                            NSLog(
                                @"[FlowHandler] Error writing UDP response: %@",
                                writeError);
                          }
                        }];
                  }

                  nw_connection_cancel(udpConnection);
                });
          });
    } else if (state == nw_connection_state_failed ||
               state == nw_connection_state_cancelled) {
      // Connection ended
    }
  });

  nw_connection_set_queue(udpConnection, self.queue);
  nw_connection_start(udpConnection);
}

#pragma mark - Helpers

- (void)bindParameters:(nw_parameters_t)parameters
           toInterface:(NSString *)interfaceName {
  if (!interfaceName)
    return;

  nw_interface_t interface = [self getInterfaceWithName:interfaceName];
  if (interface) {
    nw_parameters_require_interface(parameters, interface);
  }
}

- (nw_interface_t)getInterfaceWithName:(NSString *)name {
  __block nw_interface_t result = nil;

  nw_path_monitor_t monitor = nw_path_monitor_create();
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
    nw_path_enumerate_interfaces(path, ^bool(nw_interface_t interface) {
      const char *ifName = nw_interface_get_name(interface);
      if (ifName && strcmp(ifName, [name UTF8String]) == 0) {
        result = interface;
        return false;
      }
      return true;
    });
    dispatch_semaphore_signal(semaphore);
  });

  nw_path_monitor_set_queue(monitor,
                            dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
  nw_path_monitor_start(monitor);

  dispatch_semaphore_wait(semaphore,
                          dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC));
  nw_path_monitor_cancel(monitor);

  return result;
}

- (BOOL)isIPAddress:(NSString *)string {
  if (!string)
    return NO;

  struct in_addr addr4;
  struct in6_addr addr6;

  return (inet_pton(AF_INET, [string UTF8String], &addr4) == 1 ||
          inet_pton(AF_INET6, [string UTF8String], &addr6) == 1);
}

@end
