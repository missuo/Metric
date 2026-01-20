//
//  RuleModel.m
//  Metric
//
//  Shared rule data model implementation
//

#import "RuleModel.h"
#import <arpa/inet.h>

@interface MTRuleModel ()

@property (nonatomic, assign) uint32_t networkAddress;
@property (nonatomic, assign) uint32_t subnetMask;
@property (nonatomic, assign) NSInteger prefixLength;

@end

@implementation MTRuleModel

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ruleId = [[NSUUID UUID] UUIDString];
        _type = MTRuleTypeCIDR;
        _pattern = @"";
        _interfaceName = @"";
        _enabled = YES;
        _comment = nil;
        _priority = 0;
        _networkAddress = 0;
        _subnetMask = 0;
        _prefixLength = 0;
    }
    return self;
}

- (instancetype)initWithType:(MTRuleType)type
                     pattern:(NSString *)pattern
               interfaceName:(NSString *)interfaceName {
    self = [self init];
    if (self) {
        _type = type;
        _pattern = [pattern copy];
        _interfaceName = [interfaceName copy];

        if (type == MTRuleTypeCIDR) {
            [self parseCIDR];
        }
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [self init];
    if (self) {
        _ruleId = dict[@"ruleId"] ?: [[NSUUID UUID] UUIDString];
        _type = [dict[@"type"] integerValue];
        _pattern = dict[@"pattern"] ?: @"";
        _interfaceName = dict[@"interfaceName"] ?: @"";
        _enabled = [dict[@"enabled"] boolValue];
        _comment = dict[@"comment"];
        _priority = [dict[@"priority"] integerValue];

        if (_type == MTRuleTypeCIDR) {
            [self parseCIDR];
        }
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [self init];
    if (self) {
        _ruleId = [coder decodeObjectOfClass:[NSString class] forKey:@"ruleId"];
        _type = [coder decodeIntegerForKey:@"type"];
        _pattern = [coder decodeObjectOfClass:[NSString class] forKey:@"pattern"];
        _interfaceName = [coder decodeObjectOfClass:[NSString class] forKey:@"interfaceName"];
        _enabled = [coder decodeBoolForKey:@"enabled"];
        _comment = [coder decodeObjectOfClass:[NSString class] forKey:@"comment"];
        _priority = [coder decodeIntegerForKey:@"priority"];

        if (_type == MTRuleTypeCIDR) {
            [self parseCIDR];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_ruleId forKey:@"ruleId"];
    [coder encodeInteger:_type forKey:@"type"];
    [coder encodeObject:_pattern forKey:@"pattern"];
    [coder encodeObject:_interfaceName forKey:@"interfaceName"];
    [coder encodeBool:_enabled forKey:@"enabled"];
    [coder encodeObject:_comment forKey:@"comment"];
    [coder encodeInteger:_priority forKey:@"priority"];
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"ruleId"] = self.ruleId;
    dict[@"type"] = @(self.type);
    dict[@"pattern"] = self.pattern;
    dict[@"interfaceName"] = self.interfaceName;
    dict[@"enabled"] = @(self.enabled);
    dict[@"priority"] = @(self.priority);
    if (self.comment) {
        dict[@"comment"] = self.comment;
    }
    return [dict copy];
}

- (BOOL)parseCIDR {
    if (self.type != MTRuleTypeCIDR || self.pattern.length == 0) {
        return NO;
    }

    NSArray *components = [self.pattern componentsSeparatedByString:@"/"];
    if (components.count != 2) {
        // Treat as /32 single host
        NSString *ipString = self.pattern;
        struct in_addr addr;
        if (inet_pton(AF_INET, [ipString UTF8String], &addr) != 1) {
            return NO;
        }
        self.networkAddress = ntohl(addr.s_addr);
        self.prefixLength = 32;
        self.subnetMask = 0xFFFFFFFF;
        return YES;
    }

    NSString *ipString = components[0];
    NSInteger prefix = [components[1] integerValue];

    if (prefix < 0 || prefix > 32) {
        return NO;
    }

    struct in_addr addr;
    if (inet_pton(AF_INET, [ipString UTF8String], &addr) != 1) {
        return NO;
    }

    self.prefixLength = prefix;
    self.subnetMask = prefix > 0 ? (0xFFFFFFFF << (32 - prefix)) : 0;
    self.networkAddress = ntohl(addr.s_addr) & self.subnetMask;

    return YES;
}

- (BOOL)isValid {
    if (self.pattern.length == 0 || self.interfaceName.length == 0) {
        return NO;
    }

    if (self.type == MTRuleTypeCIDR) {
        // Validate CIDR format
        NSArray *components = [self.pattern componentsSeparatedByString:@"/"];
        NSString *ipString = components[0];

        struct in_addr addr;
        if (inet_pton(AF_INET, [ipString UTF8String], &addr) != 1) {
            return NO;
        }

        if (components.count == 2) {
            NSInteger prefix = [components[1] integerValue];
            if (prefix < 0 || prefix > 32) {
                return NO;
            }
        }

        return YES;
    } else if (self.type == MTRuleTypeHost) {
        // Basic hostname validation
        NSString *hostnameRegex = @"^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$";
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", hostnameRegex];
        return [predicate evaluateWithObject:self.pattern];
    }

    return NO;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MTRuleModel: %@ type=%ld pattern=%@ interface=%@ enabled=%@>",
            self.ruleId, (long)self.type, self.pattern, self.interfaceName, self.enabled ? @"YES" : @"NO"];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[MTRuleModel class]]) {
        return NO;
    }
    MTRuleModel *other = (MTRuleModel *)object;
    return [self.ruleId isEqualToString:other.ruleId];
}

- (NSUInteger)hash {
    return [self.ruleId hash];
}

@end
