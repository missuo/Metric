//
//  NetworkInterfaceManager.m
//  Metric
//
//  Network interface detection and management implementation
//

#import "NetworkInterfaceManager.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <net/if_dl.h>

NSNotificationName const MTNetworkInterfacesDidChangeNotification = @"MTNetworkInterfacesDidChangeNotification";

#pragma mark - MTNetworkInterface Implementation

@interface MTNetworkInterface ()

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) MTInterfaceType type;
@property (nonatomic, copy, nullable) NSString *ipv4Address;
@property (nonatomic, copy, nullable) NSString *ipv6Address;
@property (nonatomic, copy, nullable) NSString *macAddress;
@property (nonatomic, assign) BOOL isActive;

@end

@implementation MTNetworkInterface

- (instancetype)initWithName:(NSString *)name
                 displayName:(NSString *)displayName
                        type:(MTInterfaceType)type {
    self = [super init];
    if (self) {
        _name = [name copy];
        _displayName = [displayName copy];
        _type = type;
        _isActive = NO;
    }
    return self;
}

- (BOOL)hasIPv4 {
    return self.ipv4Address != nil && self.ipv4Address.length > 0;
}

- (BOOL)hasIPv6 {
    return self.ipv6Address != nil && self.ipv6Address.length > 0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@ (%@) - %@ active=%@>",
            NSStringFromClass([self class]),
            self.name,
            self.displayName,
            self.ipv4Address ?: @"No IP",
            self.isActive ? @"YES" : @"NO"];
}

@end

#pragma mark - MTNetworkInterfaceManager Implementation

@interface MTNetworkInterfaceManager () {
    SCDynamicStoreRef _dynamicStore;
    BOOL _isInitialized;
}

@property (nonatomic, strong) NSMutableArray<MTNetworkInterface *> *mutableInterfaces;

@end

@implementation MTNetworkInterfaceManager

+ (instancetype)sharedManager {
    static MTNetworkInterfaceManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[MTNetworkInterfaceManager alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableInterfaces = [NSMutableArray array];
        _isInitialized = NO;
        [self setupDynamicStore];
        [self refreshInterfacesInternal];
        _isInitialized = YES;
    }
    return self;
}

- (void)dealloc {
    if (_dynamicStore) {
        CFRelease(_dynamicStore);
    }
}

#pragma mark - Properties

- (NSArray<MTNetworkInterface *> *)interfaces {
    return [self.mutableInterfaces copy];
}

- (NSArray<MTNetworkInterface *> *)activeInterfaces {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"isActive == YES"];
    return [self.mutableInterfaces filteredArrayUsingPredicate:predicate];
}

- (MTNetworkInterface *)ethernetInterface {
    for (MTNetworkInterface *iface in self.mutableInterfaces) {
        if (iface.type == MTInterfaceTypeEthernet && iface.isActive) {
            return iface;
        }
    }
    return nil;
}

- (MTNetworkInterface *)wifiInterface {
    for (MTNetworkInterface *iface in self.mutableInterfaces) {
        if (iface.type == MTInterfaceTypeWiFi && iface.isActive) {
            return iface;
        }
    }
    return nil;
}

#pragma mark - Interface Detection

- (void)refreshInterfaces {
    [self refreshInterfacesInternal];

    // Only post notification after initialization is complete to avoid recursive dispatch_once
    if (_isInitialized) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MTNetworkInterfacesDidChangeNotification
                                                            object:self];
    }
}

- (void)refreshInterfacesInternal {
    [self.mutableInterfaces removeAllObjects];

    // Get all network interfaces using getifaddrs
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;

    if (getifaddrs(&interfaces) != 0) {
        NSLog(@"Failed to get network interfaces: %s", strerror(errno));
        return;
    }

    NSMutableDictionary<NSString *, MTNetworkInterface *> *interfaceDict = [NSMutableDictionary dictionary];

    temp_addr = interfaces;
    while (temp_addr != NULL) {
        NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];

        // Skip loopback and other non-relevant interfaces
        if ([name hasPrefix:@"lo"] || [name hasPrefix:@"gif"] ||
            [name hasPrefix:@"stf"] || [name hasPrefix:@"utun"] ||
            [name hasPrefix:@"awdl"] || [name hasPrefix:@"bridge"] ||
            [name hasPrefix:@"llw"] || [name hasPrefix:@"anpi"]) {
            temp_addr = temp_addr->ifa_next;
            continue;
        }

        MTNetworkInterface *iface = interfaceDict[name];
        if (!iface) {
            MTInterfaceType type = [self interfaceTypeForName:name];
            NSString *displayName = [self displayNameForInterface:name type:type];
            iface = [[MTNetworkInterface alloc] initWithName:name
                                                displayName:displayName
                                                       type:type];
            interfaceDict[name] = iface;
        }

        // Check if interface is up
        if ((temp_addr->ifa_flags & IFF_UP) && (temp_addr->ifa_flags & IFF_RUNNING)) {
            iface.isActive = YES;
        }

        // Get addresses
        if (temp_addr->ifa_addr->sa_family == AF_INET) {
            // IPv4
            char addrBuf[INET_ADDRSTRLEN];
            struct sockaddr_in *addr = (struct sockaddr_in *)temp_addr->ifa_addr;
            inet_ntop(AF_INET, &addr->sin_addr, addrBuf, sizeof(addrBuf));
            iface.ipv4Address = [NSString stringWithUTF8String:addrBuf];
        } else if (temp_addr->ifa_addr->sa_family == AF_INET6) {
            // IPv6
            char addrBuf[INET6_ADDRSTRLEN];
            struct sockaddr_in6 *addr = (struct sockaddr_in6 *)temp_addr->ifa_addr;
            inet_ntop(AF_INET6, &addr->sin6_addr, addrBuf, sizeof(addrBuf));
            NSString *ipv6 = [NSString stringWithUTF8String:addrBuf];
            // Skip link-local addresses for display
            if (![ipv6 hasPrefix:@"fe80:"]) {
                iface.ipv6Address = ipv6;
            }
        } else if (temp_addr->ifa_addr->sa_family == AF_LINK) {
            // MAC address
            struct sockaddr_dl *sdl = (struct sockaddr_dl *)temp_addr->ifa_addr;
            if (sdl->sdl_alen == 6) {
                unsigned char *mac = (unsigned char *)LLADDR(sdl);
                iface.macAddress = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
                                    mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]];
            }
        }

        temp_addr = temp_addr->ifa_next;
    }

    freeifaddrs(interfaces);

    // Add interfaces to array, sorted by type
    NSArray *sortedKeys = [interfaceDict.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        MTNetworkInterface *ifaceA = interfaceDict[a];
        MTNetworkInterface *ifaceB = interfaceDict[b];

        // Sort by type first (Ethernet, WiFi, Other)
        if (ifaceA.type != ifaceB.type) {
            return ifaceA.type < ifaceB.type ? NSOrderedAscending : NSOrderedDescending;
        }

        // Then by name
        return [a compare:b];
    }];

    for (NSString *name in sortedKeys) {
        [self.mutableInterfaces addObject:interfaceDict[name]];
    }
}

- (MTInterfaceType)interfaceTypeForName:(NSString *)name {
    // Common naming conventions on macOS
    // en0 is typically the built-in Ethernet or Wi-Fi (depending on Mac model)
    // en1 is typically the secondary (Wi-Fi if en0 is Ethernet)

    // Use IOKit or SystemConfiguration to determine actual type
    // For now, use a heuristic based on common patterns

    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("Metric"), NULL, NULL);
    if (!store) {
        return MTInterfaceTypeOther;
    }

    CFStringRef key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(NULL,
                                                                     kSCDynamicStoreDomainState,
                                                                     (__bridge CFStringRef)name,
                                                                     kSCEntNetAirPort);
    CFDictionaryRef airportDict = SCDynamicStoreCopyValue(store, key);
    CFRelease(key);

    if (airportDict) {
        CFRelease(airportDict);
        CFRelease(store);
        return MTInterfaceTypeWiFi;
    }

    // Check for Ethernet
    key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(NULL,
                                                         kSCDynamicStoreDomainState,
                                                         (__bridge CFStringRef)name,
                                                         kSCEntNetEthernet);
    CFDictionaryRef ethernetDict = SCDynamicStoreCopyValue(store, key);
    CFRelease(key);

    if (ethernetDict) {
        CFRelease(ethernetDict);
        CFRelease(store);
        return MTInterfaceTypeEthernet;
    }

    CFRelease(store);

    // Fallback heuristics
    if ([name hasPrefix:@"en"]) {
        // Try to determine from interface media type
        // For simplicity, assume en0 could be either based on Mac type
        return MTInterfaceTypeOther;
    }

    return MTInterfaceTypeOther;
}

- (NSString *)displayNameForInterface:(NSString *)name type:(MTInterfaceType)type {
    switch (type) {
        case MTInterfaceTypeEthernet:
            return [NSString stringWithFormat:@"Ethernet (%@)", name];
        case MTInterfaceTypeWiFi:
            return [NSString stringWithFormat:@"Wi-Fi (%@)", name];
        default:
            return [NSString stringWithFormat:@"Network (%@)", name];
    }
}

#pragma mark - Dynamic Store

- (void)setupDynamicStore {
    SCDynamicStoreContext context = {0, (__bridge void *)self, NULL, NULL, NULL};

    _dynamicStore = SCDynamicStoreCreate(NULL,
                                          CFSTR("Metric"),
                                          dynamicStoreCallback,
                                          &context);
    if (!_dynamicStore) {
        NSLog(@"Failed to create dynamic store");
        return;
    }

    // Watch for network changes
    CFStringRef pattern = SCDynamicStoreKeyCreateNetworkInterfaceEntity(NULL,
                                                                         kSCDynamicStoreDomainState,
                                                                         kSCCompAnyRegex,
                                                                         kSCEntNetIPv4);
    CFArrayRef patterns = CFArrayCreate(NULL, (const void **)&pattern, 1, &kCFTypeArrayCallBacks);
    SCDynamicStoreSetNotificationKeys(_dynamicStore, NULL, patterns);
    CFRelease(pattern);
    CFRelease(patterns);

    CFRunLoopSourceRef runLoopSource = SCDynamicStoreCreateRunLoopSource(NULL, _dynamicStore, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopDefaultMode);
    CFRelease(runLoopSource);
}

static void dynamicStoreCallback(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info) {
    MTNetworkInterfaceManager *manager = (__bridge MTNetworkInterfaceManager *)info;
    dispatch_async(dispatch_get_main_queue(), ^{
        [manager refreshInterfaces];
    });
}

#pragma mark - Lookup Methods

- (MTNetworkInterface *)interfaceWithName:(NSString *)name {
    for (MTNetworkInterface *iface in self.mutableInterfaces) {
        if ([iface.name isEqualToString:name]) {
            return iface;
        }
    }
    return nil;
}

- (NSArray<NSString *> *)interfaceDisplayNames {
    NSMutableArray *names = [NSMutableArray array];
    for (MTNetworkInterface *iface in self.mutableInterfaces) {
        NSString *displayStr = [NSString stringWithFormat:@"%@ - %@",
                                iface.displayName,
                                iface.ipv4Address ?: @"No IP"];
        [names addObject:displayStr];
    }
    return names;
}

- (NSArray<NSString *> *)activeInterfaceDisplayNames {
    NSMutableArray *names = [NSMutableArray array];
    for (MTNetworkInterface *iface in self.activeInterfaces) {
        NSString *displayStr = [NSString stringWithFormat:@"%@ - %@",
                                iface.displayName,
                                iface.ipv4Address ?: @"No IP"];
        [names addObject:displayStr];
    }
    return names;
}

- (NSString *)interfaceNameFromDisplayString:(NSString *)displayString {
    // Extract interface name from display string like "Ethernet (en0) - 192.168.1.100"
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\(([a-z0-9]+)\\)"
                                                                           options:0
                                                                             error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:displayString
                                                    options:0
                                                      range:NSMakeRange(0, displayString.length)];
    if (match && match.numberOfRanges > 1) {
        return [displayString substringWithRange:[match rangeAtIndex:1]];
    }
    return nil;
}

@end
