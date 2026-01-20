//
//  IPAddressHelper.m
//  Metric
//
//  IP address and CIDR parsing utilities implementation
//

#import "IPAddressHelper.h"
#import <arpa/inet.h>
#import <netdb.h>

@implementation MTIPAddressHelper

#pragma mark - IP Address Validation

+ (BOOL)isValidIPv4Address:(NSString *)address {
    if (!address || address.length == 0) {
        return NO;
    }

    struct in_addr addr;
    return inet_pton(AF_INET, [address UTF8String], &addr) == 1;
}

+ (BOOL)isValidIPv6Address:(NSString *)address {
    if (!address || address.length == 0) {
        return NO;
    }

    struct in6_addr addr;
    return inet_pton(AF_INET6, [address UTF8String], &addr) == 1;
}

+ (BOOL)isValidIPAddress:(NSString *)address {
    return [self isValidIPv4Address:address] || [self isValidIPv6Address:address];
}

#pragma mark - CIDR Validation and Parsing

+ (BOOL)isValidCIDR:(NSString *)cidr {
    if (!cidr || cidr.length == 0) {
        return NO;
    }

    uint32_t address, mask;
    NSInteger prefixLen;
    return [self parseCIDR:cidr outAddress:&address outMask:&mask outPrefixLen:&prefixLen];
}

+ (BOOL)parseCIDR:(NSString *)cidr
       outAddress:(uint32_t *)outAddress
          outMask:(uint32_t *)outMask
     outPrefixLen:(NSInteger *)outPrefixLen {

    if (!cidr || cidr.length == 0) {
        return NO;
    }

    NSArray *components = [cidr componentsSeparatedByString:@"/"];
    NSString *ipString = components[0];

    // Validate IP portion
    struct in_addr addr;
    if (inet_pton(AF_INET, [ipString UTF8String], &addr) != 1) {
        return NO;
    }

    uint32_t ipValue = ntohl(addr.s_addr);
    NSInteger prefixLength = 32;

    // Parse prefix length if present
    if (components.count == 2) {
        NSString *prefixString = components[1];

        // Validate prefix is a number
        NSScanner *scanner = [NSScanner scannerWithString:prefixString];
        NSInteger scannedValue;
        if (![scanner scanInteger:&scannedValue] || ![scanner isAtEnd]) {
            return NO;
        }

        prefixLength = scannedValue;
        if (prefixLength < 0 || prefixLength > 32) {
            return NO;
        }
    } else if (components.count > 2) {
        return NO;
    }

    // Calculate mask
    uint32_t mask = prefixLength > 0 ? (0xFFFFFFFF << (32 - prefixLength)) : 0;

    if (outAddress) {
        *outAddress = ipValue & mask;
    }
    if (outMask) {
        *outMask = mask;
    }
    if (outPrefixLen) {
        *outPrefixLen = prefixLength;
    }

    return YES;
}

#pragma mark - CIDR Matching

+ (BOOL)ipAddress:(NSString *)ip matchesCIDR:(NSString *)cidr {
    if (!ip || !cidr) {
        return NO;
    }

    uint32_t ipValue = [self ipv4StringToUInt32:ip];
    if (ipValue == 0 && ![ip isEqualToString:@"0.0.0.0"]) {
        return NO;
    }

    uint32_t network, mask;
    NSInteger prefixLen;
    if (![self parseCIDR:cidr outAddress:&network outMask:&mask outPrefixLen:&prefixLen]) {
        return NO;
    }

    return [self ipAddressValue:ipValue matchesNetwork:network withMask:mask];
}

+ (BOOL)ipAddressValue:(uint32_t)ipValue
       matchesNetwork:(uint32_t)network
             withMask:(uint32_t)mask {
    return (ipValue & mask) == network;
}

#pragma mark - IP Address Conversion

+ (uint32_t)ipv4StringToUInt32:(NSString *)ipString {
    if (!ipString || ipString.length == 0) {
        return 0;
    }

    struct in_addr addr;
    if (inet_pton(AF_INET, [ipString UTF8String], &addr) != 1) {
        return 0;
    }

    return ntohl(addr.s_addr);
}

+ (NSString *)uint32ToIPv4String:(uint32_t)ipValue {
    struct in_addr addr;
    addr.s_addr = htonl(ipValue);

    char buffer[INET_ADDRSTRLEN];
    if (inet_ntop(AF_INET, &addr, buffer, sizeof(buffer)) == NULL) {
        return nil;
    }

    return [NSString stringWithUTF8String:buffer];
}

#pragma mark - Network Calculations

+ (NSString *)networkAddressForCIDR:(NSString *)cidr {
    uint32_t network, mask;
    NSInteger prefixLen;
    if (![self parseCIDR:cidr outAddress:&network outMask:&mask outPrefixLen:&prefixLen]) {
        return nil;
    }

    return [self uint32ToIPv4String:network];
}

+ (NSString *)broadcastAddressForCIDR:(NSString *)cidr {
    uint32_t network, mask;
    NSInteger prefixLen;
    if (![self parseCIDR:cidr outAddress:&network outMask:&mask outPrefixLen:&prefixLen]) {
        return nil;
    }

    uint32_t broadcast = network | ~mask;
    return [self uint32ToIPv4String:broadcast];
}

+ (uint32_t)hostCountForPrefixLength:(NSInteger)prefixLength {
    if (prefixLength < 0 || prefixLength > 32) {
        return 0;
    }

    if (prefixLength == 32) {
        return 1;
    }

    if (prefixLength == 31) {
        return 2;
    }

    // Subtract 2 for network and broadcast addresses
    return (1U << (32 - prefixLength)) - 2;
}

#pragma mark - Hostname Validation

+ (BOOL)isValidHostname:(NSString *)hostname {
    if (!hostname || hostname.length == 0 || hostname.length > 253) {
        return NO;
    }

    // RFC 1123 hostname pattern
    NSString *pattern = @"^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:nil];
    if (!regex) {
        return NO;
    }

    NSRange range = NSMakeRange(0, hostname.length);
    NSUInteger matches = [regex numberOfMatchesInString:hostname options:0 range:range];
    return matches > 0;
}

@end
