//
//  SharedConstants.h
//  Metric
//
//  Shared constants between main app and extension
//

#ifndef SharedConstants_h
#define SharedConstants_h

#import <Foundation/Foundation.h>

// App Group identifier for sharing data between app and extension
static NSString *const kMTAppGroupIdentifier = @"group.nz.owo.metric.shared";

// UserDefaults keys
static NSString *const kMTRulesKey = @"MTRules";
static NSString *const kMTProxyEnabledKey = @"MTProxyEnabled";
static NSString *const kMTDefaultInterfaceKey = @"MTDefaultInterface";

// Notification names
static NSString *const kMTRulesDidChangeNotification =
    @"MTRulesDidChangeNotification";
static NSString *const kMTProxyStatusDidChangeNotification =
    @"MTProxyStatusDidChangeNotification";
static NSString *const kMTLogMessageNotification =
    @"MTLogMessageNotification";

// Log message keys
static NSString *const kMTLogMessageKey = @"message";
static NSString *const kMTLogTimestampKey = @"timestamp";
static NSString *const kMTLogLevelKey = @"level";

// Extension bundle identifier
static NSString *const kMTExtensionBundleIdentifier =
    @"nz.owo.Metric.MetricExtension";

// Rule types
typedef NS_ENUM(NSInteger, MTRuleType) {
  MTRuleTypeCIDR = 0,
  MTRuleTypeHost = 1
};

// Network interface types
typedef NS_ENUM(NSInteger, MTInterfaceType) {
  MTInterfaceTypeUnknown = 0,
  MTInterfaceTypeEthernet = 1,
  MTInterfaceTypeWiFi = 2,
  MTInterfaceTypeOther = 3
};

// Proxy status
typedef NS_ENUM(NSInteger, MTProxyStatus) {
  MTProxyStatusStopped = 0,
  MTProxyStatusStarting = 1,
  MTProxyStatusRunning = 2,
  MTProxyStatusStopping = 3,
  MTProxyStatusError = 4
};

// Log levels
typedef NS_ENUM(NSInteger, MTLogLevel) {
  MTLogLevelDebug = 0,
  MTLogLevelInfo = 1,
  MTLogLevelWarning = 2,
  MTLogLevelError = 3
};

#endif /* SharedConstants_h */
