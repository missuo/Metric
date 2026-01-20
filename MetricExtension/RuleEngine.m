//
//  RuleEngine.m
//  MetricExtension
//
//  Rule matching engine implementation
//

#import "RuleEngine.h"
#import "RuleModel.h"
#import "SharedConstants.h"
#import <arpa/inet.h>

@interface MTRuleEngine ()

@property (nonatomic, strong) NSMutableArray<MTRuleModel *> *mutableRules;
@property (nonatomic, strong) NSArray<MTRuleModel *> *cidrRules;
@property (nonatomic, strong) NSArray<MTRuleModel *> *hostRules;
@property (nonatomic, strong) NSUserDefaults *sharedDefaults;

@end

@implementation MTRuleEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableRules = [NSMutableArray array];
        _cidrRules = @[];
        _hostRules = @[];
        _sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:kMTAppGroupIdentifier];
    }
    return self;
}

- (NSArray<MTRuleModel *> *)rules {
    return [self.mutableRules copy];
}

#pragma mark - Rule Loading

- (void)loadRules {
    @synchronized (self) {
        [self.mutableRules removeAllObjects];

        // Load from file in App Group container (more reliable for System Extensions)
        NSURL *containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kMTAppGroupIdentifier];
        NSURL *rulesFileURL = [containerURL URLByAppendingPathComponent:@"rules.plist"];
        
        NSLog(@"[MetricExt] Container URL: %@", containerURL.path);
        NSLog(@"[MetricExt] Loading rules from: %@", rulesFileURL.path);
        
        // Check if container URL is nil
        if (!containerURL) {
            NSLog(@"[MetricExt] ERROR: containerURL is nil! App Group not accessible.");
            [self sendLog:@"[Rules] ERROR: App Group container not accessible"];
            return;
        }
        
        // Check if file exists
        BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:rulesFileURL.path];
        NSLog(@"[MetricExt] Rules file exists: %@", fileExists ? @"YES" : @"NO");
        
        // List container contents
        NSError *listError = nil;
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:containerURL.path error:&listError];
        NSLog(@"[MetricExt] Container contents: %@", contents);
        if (listError) {
            NSLog(@"[MetricExt] List error: %@", listError);
        }
        
        NSData *data = [NSData dataWithContentsOfURL:rulesFileURL];
        if (!data) {
            NSLog(@"[MetricExt] No rules file found or cannot read");
            [self sendLog:@"[Rules] No rules file found"];
            return;
        }
        
        NSError *error = nil;
        NSArray *dictArray = [NSPropertyListSerialization propertyListWithData:data
                                                                       options:NSPropertyListImmutable
                                                                        format:NULL
                                                                         error:&error];
        if (error || ![dictArray isKindOfClass:[NSArray class]]) {
            NSLog(@"[MetricExt] Error reading rules: %@", error);
            [self sendLog:@"[Rules] Error reading rules file"];
            return;
        }
        
        NSLog(@"[MetricExt] Found %lu rules in file", (unsigned long)dictArray.count);
        
        if (dictArray.count == 0) {
            [self sendLog:@"[Rules] Rules file is empty"];
            return;
        }

        [self sendLog:@"[Rules] Found %lu rules in storage", (unsigned long)dictArray.count];

        for (NSDictionary *dict in dictArray) {
            MTRuleModel *rule = [[MTRuleModel alloc] initWithDictionary:dict];
            if (rule.enabled && [rule isValid]) {
                [self.mutableRules addObject:rule];
                [self sendLog:@"[Rules] Loaded: %@ -> %@", rule.pattern, rule.interfaceName];
            }
        }

        // Sort by priority
        [self.mutableRules sortUsingComparator:^NSComparisonResult(MTRuleModel *a, MTRuleModel *b) {
            return [@(a.priority) compare:@(b.priority)];
        }];

        // Separate CIDR and Host rules for faster matching
        NSPredicate *cidrPredicate = [NSPredicate predicateWithFormat:@"type == %d", MTRuleTypeCIDR];
        NSPredicate *hostPredicate = [NSPredicate predicateWithFormat:@"type == %d", MTRuleTypeHost];

        self.cidrRules = [self.mutableRules filteredArrayUsingPredicate:cidrPredicate];
        self.hostRules = [self.mutableRules filteredArrayUsingPredicate:hostPredicate];

        [self sendLog:@"[Rules] Total active: %lu (CIDR: %lu, Host: %lu)",
              (unsigned long)self.mutableRules.count,
              (unsigned long)self.cidrRules.count,
              (unsigned long)self.hostRules.count];
    }
}

- (void)loadRulesFromArray:(NSArray<NSDictionary *> *)dictArray {
    @synchronized (self) {
        [self.mutableRules removeAllObjects];
        
        NSLog(@"[MetricExt] loadRulesFromArray: %lu rules", (unsigned long)dictArray.count);
        
        if (!dictArray || dictArray.count == 0) {
            NSLog(@"[MetricExt] No rules in array");
            [self sendLog:@"[Rules] No rules provided"];
            return;
        }
        
        for (NSDictionary *dict in dictArray) {
            NSLog(@"[MetricExt] Processing rule: %@", dict);
            MTRuleModel *rule = [[MTRuleModel alloc] initWithDictionary:dict];
            if (rule.enabled && [rule isValid]) {
                [self.mutableRules addObject:rule];
                NSLog(@"[MetricExt] Loaded rule: %@ -> %@", rule.pattern, rule.interfaceName);
                [self sendLog:@"[Rules] Loaded: %@ -> %@", rule.pattern, rule.interfaceName];
            } else {
                NSLog(@"[MetricExt] Skipped rule (disabled or invalid): %@", dict);
            }
        }
        
        // Sort by priority
        [self.mutableRules sortUsingComparator:^NSComparisonResult(MTRuleModel *a, MTRuleModel *b) {
            return [@(a.priority) compare:@(b.priority)];
        }];
        
        // Separate CIDR and Host rules for faster matching
        NSPredicate *cidrPredicate = [NSPredicate predicateWithFormat:@"type == %d", MTRuleTypeCIDR];
        NSPredicate *hostPredicate = [NSPredicate predicateWithFormat:@"type == %d", MTRuleTypeHost];
        
        self.cidrRules = [self.mutableRules filteredArrayUsingPredicate:cidrPredicate];
        self.hostRules = [self.mutableRules filteredArrayUsingPredicate:hostPredicate];
        
        NSLog(@"[MetricExt] Rules loaded - Total: %lu, CIDR: %lu, Host: %lu",
              (unsigned long)self.mutableRules.count,
              (unsigned long)self.cidrRules.count,
              (unsigned long)self.hostRules.count);
        
        [self sendLog:@"[Rules] Total active: %lu (CIDR: %lu, Host: %lu)",
              (unsigned long)self.mutableRules.count,
              (unsigned long)self.cidrRules.count,
              (unsigned long)self.hostRules.count];
    }
}

- (void)sendLog:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[MetricExt] %@", message);
    
    // Write to shared file for debugging
    NSMutableArray *logs = [[self.sharedDefaults arrayForKey:@"MTExtensionLogs"] mutableCopy] ?: [NSMutableArray array];
    
    while (logs.count > 100) {
        [logs removeObjectAtIndex:0];
    }
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] [INFO ] %@", timestamp, message];
    [logs addObject:logEntry];
    
    [self.sharedDefaults setObject:logs forKey:@"MTExtensionLogs"];
    [self.sharedDefaults synchronize];
}

#pragma mark - Rule Matching

- (MTRuleModel *)matchRuleForIP:(NSString *)ipAddress hostname:(NSString *)hostname {
    [self sendLog:@"[Match] Checking IP:%@ Host:%@ against %lu rules", 
          ipAddress ?: @"nil", hostname ?: @"nil", (unsigned long)self.mutableRules.count];
    
    // First try to match by hostname (more specific)
    if (hostname) {
        MTRuleModel *hostMatch = [self matchHostRuleForHostname:hostname];
        if (hostMatch) {
            [self sendLog:@"[Match] Found host match: %@", hostMatch.pattern];
            return hostMatch;
        }
    }

    // Then try to match by IP
    if (ipAddress) {
        MTRuleModel *cidrMatch = [self matchCIDRRuleForIP:ipAddress];
        if (cidrMatch) {
            [self sendLog:@"[Match] Found CIDR match: %@", cidrMatch.pattern];
            return cidrMatch;
        }
    }

    [self sendLog:@"[Match] No match found"];
    // No match found
    return nil;
}

- (MTRuleModel *)matchCIDRRuleForIP:(NSString *)ipAddress {
    if (!ipAddress) {
        return nil;
    }

    // Convert IP to uint32
    struct in_addr addr;
    if (inet_pton(AF_INET, [ipAddress UTF8String], &addr) != 1) {
        NSLog(@"[RuleEngine] Invalid IP address: %@", ipAddress);
        return nil;
    }

    uint32_t ipValue = ntohl(addr.s_addr);

    @synchronized (self) {
        // Find the most specific matching rule (longest prefix)
        MTRuleModel *bestMatch = nil;
        NSInteger longestPrefix = -1;

        for (MTRuleModel *rule in self.cidrRules) {
            if ([self ipValue:ipValue matchesRule:rule]) {
                if (rule.prefixLength > longestPrefix) {
                    longestPrefix = rule.prefixLength;
                    bestMatch = rule;
                }
            }
        }

        return bestMatch;
    }
}

- (BOOL)ipValue:(uint32_t)ipValue matchesRule:(MTRuleModel *)rule {
    return (ipValue & rule.subnetMask) == rule.networkAddress;
}

- (MTRuleModel *)matchHostRuleForHostname:(NSString *)hostname {
    if (!hostname) {
        return nil;
    }

    NSString *lowercaseHost = [hostname lowercaseString];

    @synchronized (self) {
        for (MTRuleModel *rule in self.hostRules) {
            NSString *pattern = [rule.pattern lowercaseString];

            // Exact match
            if ([lowercaseHost isEqualToString:pattern]) {
                return rule;
            }

            // Wildcard match (*.example.com matches sub.example.com)
            if ([pattern hasPrefix:@"*."]) {
                NSString *suffix = [pattern substringFromIndex:1]; // .example.com
                if ([lowercaseHost hasSuffix:suffix]) {
                    return rule;
                }
            }

            // Suffix match (example.com matches sub.example.com)
            if ([lowercaseHost hasSuffix:[@"." stringByAppendingString:pattern]]) {
                return rule;
            }
        }
    }

    return nil;
}

@end
