//
//  IPAddressHelper.h
//  Metric
//
//  IP address and CIDR parsing utilities
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTIPAddressHelper : NSObject

// IP Address validation
+ (BOOL)isValidIPv4Address:(NSString *)address;
+ (BOOL)isValidIPv6Address:(NSString *)address;
+ (BOOL)isValidIPAddress:(NSString *)address;

// CIDR validation and parsing
+ (BOOL)isValidCIDR:(NSString *)cidr;
+ (BOOL)parseCIDR:(NSString *)cidr
       outAddress:(uint32_t *)outAddress
          outMask:(uint32_t *)outMask
     outPrefixLen:(NSInteger *)outPrefixLen;

// CIDR matching
+ (BOOL)ipAddress:(NSString *)ip matchesCIDR:(NSString *)cidr;
+ (BOOL)ipAddressValue:(uint32_t)ipValue
       matchesNetwork:(uint32_t)network
             withMask:(uint32_t)mask;

// IP address conversion
+ (uint32_t)ipv4StringToUInt32:(NSString *)ipString;
+ (NSString *)uint32ToIPv4String:(uint32_t)ipValue;

// Network calculations
+ (NSString *)networkAddressForCIDR:(NSString *)cidr;
+ (NSString *)broadcastAddressForCIDR:(NSString *)cidr;
+ (uint32_t)hostCountForPrefixLength:(NSInteger)prefixLength;

// Hostname validation
+ (BOOL)isValidHostname:(NSString *)hostname;

@end

NS_ASSUME_NONNULL_END
