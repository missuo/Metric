//
//  NetworkInterfaceManager.h
//  Metric
//
//  Network interface detection and management
//

#import <Foundation/Foundation.h>
#import "SharedConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTNetworkInterface : NSObject

@property (nonatomic, copy, readonly) NSString *name;           // e.g., "en0"
@property (nonatomic, copy, readonly) NSString *displayName;    // e.g., "Ethernet"
@property (nonatomic, assign, readonly) MTInterfaceType type;
@property (nonatomic, copy, readonly, nullable) NSString *ipv4Address;
@property (nonatomic, copy, readonly, nullable) NSString *ipv6Address;
@property (nonatomic, copy, readonly, nullable) NSString *macAddress;
@property (nonatomic, assign, readonly) BOOL isActive;
@property (nonatomic, assign, readonly) BOOL hasIPv4;
@property (nonatomic, assign, readonly) BOOL hasIPv6;

- (instancetype)initWithName:(NSString *)name
                 displayName:(NSString *)displayName
                        type:(MTInterfaceType)type;

@end

@interface MTNetworkInterfaceManager : NSObject

// Singleton
+ (instancetype)sharedManager;

// All detected interfaces
@property (nonatomic, readonly) NSArray<MTNetworkInterface *> *interfaces;

// Active interfaces only
@property (nonatomic, readonly) NSArray<MTNetworkInterface *> *activeInterfaces;

// Specific interface types
@property (nonatomic, readonly, nullable) MTNetworkInterface *ethernetInterface;
@property (nonatomic, readonly, nullable) MTNetworkInterface *wifiInterface;

// Refresh interfaces
- (void)refreshInterfaces;

// Find interface by name
- (nullable MTNetworkInterface *)interfaceWithName:(NSString *)name;

// Interface display names for UI
- (NSArray<NSString *> *)interfaceDisplayNames;
- (NSArray<NSString *> *)activeInterfaceDisplayNames;

// Get interface name from display string
- (nullable NSString *)interfaceNameFromDisplayString:(NSString *)displayString;

@end

// Notifications
extern NSNotificationName const MTNetworkInterfacesDidChangeNotification;

NS_ASSUME_NONNULL_END
