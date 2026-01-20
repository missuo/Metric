//
//  Rule.m
//  Metric
//
//  Rule model implementation
//

#import "Rule.h"
#import "RuleModel.h"
#import <arpa/inet.h>

@interface MTRule ()

@property (nonatomic, copy) NSString *ruleId;

@end

@implementation MTRule

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
    }
    return self;
}

- (instancetype)initWithRuleModel:(MTRuleModel *)model {
    self = [self init];
    if (self) {
        _ruleId = [model.ruleId copy];
        _type = model.type;
        _pattern = [model.pattern copy];
        _interfaceName = [model.interfaceName copy];
        _enabled = model.enabled;
        _comment = [model.comment copy];
        _priority = model.priority;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    MTRule *copy = [[MTRule alloc] init];
    copy.ruleId = [self.ruleId copy];
    copy.type = self.type;
    copy.pattern = [self.pattern copy];
    copy.interfaceName = [self.interfaceName copy];
    copy.enabled = self.enabled;
    copy.comment = [self.comment copy];
    copy.priority = self.priority;
    return copy;
}

- (MTRuleModel *)toRuleModel {
    MTRuleModel *model = [[MTRuleModel alloc] init];
    model.ruleId = self.ruleId;
    model.type = self.type;
    model.pattern = self.pattern;
    model.interfaceName = self.interfaceName;
    model.enabled = self.enabled;
    model.comment = self.comment;
    model.priority = self.priority;
    return model;
}

- (NSString *)typeString {
    switch (self.type) {
        case MTRuleTypeCIDR:
            return @"CIDR";
        case MTRuleTypeHost:
            return @"Host";
        default:
            return @"Unknown";
    }
}

- (NSString *)displayString {
    return [NSString stringWithFormat:@"%@ → %@", self.pattern, self.interfaceName];
}

- (BOOL)isValid {
    return [self validationError] == nil;
}

- (NSString *)validationError {
    if (self.pattern.length == 0) {
        return @"Pattern cannot be empty";
    }

    if (self.interfaceName.length == 0) {
        return @"Interface must be selected";
    }

    if (self.type == MTRuleTypeCIDR) {
        return [self validateCIDR];
    } else if (self.type == MTRuleTypeHost) {
        return [self validateHost];
    }

    return @"Unknown rule type";
}

- (NSString *)validateCIDR {
    NSArray *components = [self.pattern componentsSeparatedByString:@"/"];

    if (components.count > 2) {
        return @"Invalid CIDR format. Use format: IP/prefix (e.g., 192.168.1.0/24)";
    }

    NSString *ipString = components[0];
    struct in_addr addr;

    if (inet_pton(AF_INET, [ipString UTF8String], &addr) != 1) {
        return @"Invalid IP address";
    }

    if (components.count == 2) {
        NSInteger prefix = [components[1] integerValue];
        if (prefix < 0 || prefix > 32) {
            return @"Prefix length must be between 0 and 32";
        }

        // Check if the string is actually a number
        NSScanner *scanner = [NSScanner scannerWithString:components[1]];
        NSInteger scannedValue;
        if (![scanner scanInteger:&scannedValue] || ![scanner isAtEnd]) {
            return @"Invalid prefix length";
        }
    }

    return nil;
}

- (NSString *)validateHost {
    // Basic hostname validation
    if (self.pattern.length > 253) {
        return @"Hostname too long (max 253 characters)";
    }

    // Check for valid hostname characters
    NSCharacterSet *allowedChars = [NSCharacterSet characterSetWithCharactersInString:
                                    @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"];
    NSCharacterSet *inputChars = [NSCharacterSet characterSetWithCharactersInString:self.pattern];

    if (![allowedChars isSupersetOfSet:inputChars]) {
        return @"Hostname contains invalid characters";
    }

    // Check that it doesn't start or end with a hyphen or dot
    if ([self.pattern hasPrefix:@"-"] || [self.pattern hasSuffix:@"-"] ||
        [self.pattern hasPrefix:@"."] || [self.pattern hasSuffix:@"."]) {
        return @"Hostname cannot start or end with a hyphen or dot";
    }

    return nil;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MTRule: %@ [%@] %@ → %@ enabled=%@>",
            self.ruleId, self.typeString, self.pattern, self.interfaceName,
            self.enabled ? @"YES" : @"NO"];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[MTRule class]]) {
        return NO;
    }
    MTRule *other = (MTRule *)object;
    return [self.ruleId isEqualToString:other.ruleId];
}

- (NSUInteger)hash {
    return [self.ruleId hash];
}

@end
