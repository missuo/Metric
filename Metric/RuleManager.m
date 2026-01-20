//
//  RuleManager.m
//  Metric
//
//  Rules storage and persistence implementation
//

#import "RuleManager.h"
#import "Rule.h"
#import "RuleModel.h"
#import "SharedConstants.h"

NSNotificationName const MTRuleManagerDidChangeNotification = @"MTRuleManagerDidChangeNotification";
NSString * const MTRuleManagerChangeTypeKey = @"changeType";
NSString * const MTRuleManagerChangedRuleKey = @"changedRule";
NSString * const MTRuleManagerChangedIndexKey = @"changedIndex";

@interface MTRuleManager ()

@property (nonatomic, strong) NSMutableArray<MTRule *> *mutableRules;
@property (nonatomic, strong) NSUserDefaults *sharedDefaults;

@end

@implementation MTRuleManager

+ (instancetype)sharedManager {
    static MTRuleManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[MTRuleManager alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableRules = [NSMutableArray array];
        _sharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:kMTAppGroupIdentifier];
        [self loadRules];
    }
    return self;
}

#pragma mark - Properties

- (NSArray<MTRule *> *)rules {
    return [self.mutableRules copy];
}

#pragma mark - CRUD Operations

- (void)addRule:(MTRule *)rule {
    [self insertRule:rule atIndex:self.mutableRules.count];
}

- (void)insertRule:(MTRule *)rule atIndex:(NSUInteger)index {
    if (index > self.mutableRules.count) {
        index = self.mutableRules.count;
    }

    [self willChangeValueForKey:@"rules"];
    [self.mutableRules insertObject:rule atIndex:index];
    [self didChangeValueForKey:@"rules"];

    [self saveRules];
    [self postNotificationWithType:MTRuleManagerChangeTypeAdd rule:rule index:index];
}

- (void)removeRule:(MTRule *)rule {
    NSUInteger index = [self.mutableRules indexOfObject:rule];
    if (index != NSNotFound) {
        [self removeRuleAtIndex:index];
    }
}

- (void)removeRuleAtIndex:(NSUInteger)index {
    if (index >= self.mutableRules.count) {
        return;
    }

    MTRule *rule = self.mutableRules[index];

    [self willChangeValueForKey:@"rules"];
    [self.mutableRules removeObjectAtIndex:index];
    [self didChangeValueForKey:@"rules"];

    [self saveRules];
    [self postNotificationWithType:MTRuleManagerChangeTypeRemove rule:rule index:index];
}

- (void)updateRule:(MTRule *)rule {
    NSUInteger index = [self.mutableRules indexOfObject:rule];
    if (index == NSNotFound) {
        return;
    }

    [self willChangeValueForKey:@"rules"];
    self.mutableRules[index] = rule;
    [self didChangeValueForKey:@"rules"];

    [self saveRules];
    [self postNotificationWithType:MTRuleManagerChangeTypeUpdate rule:rule index:index];
}

- (void)moveRuleAtIndex:(NSUInteger)fromIndex toIndex:(NSUInteger)toIndex {
    if (fromIndex >= self.mutableRules.count || toIndex > self.mutableRules.count) {
        return;
    }

    if (fromIndex == toIndex) {
        return;
    }

    MTRule *rule = self.mutableRules[fromIndex];

    [self willChangeValueForKey:@"rules"];
    [self.mutableRules removeObjectAtIndex:fromIndex];
    if (toIndex > fromIndex) {
        toIndex--;
    }
    [self.mutableRules insertObject:rule atIndex:toIndex];
    [self didChangeValueForKey:@"rules"];

    // Update priorities
    [self updatePriorities];

    [self saveRules];
    [self postNotificationWithType:MTRuleManagerChangeTypeMove rule:rule index:toIndex];
}

#pragma mark - Bulk Operations

- (void)setRules:(NSArray<MTRule *> *)rules {
    [self willChangeValueForKey:@"rules"];
    [self.mutableRules setArray:rules];
    [self didChangeValueForKey:@"rules"];

    [self updatePriorities];
    [self saveRules];
    [self postNotificationWithType:MTRuleManagerChangeTypeReload rule:nil index:NSNotFound];
}

- (void)removeAllRules {
    [self willChangeValueForKey:@"rules"];
    [self.mutableRules removeAllObjects];
    [self didChangeValueForKey:@"rules"];

    [self saveRules];
    [self postNotificationWithType:MTRuleManagerChangeTypeReload rule:nil index:NSNotFound];
}

#pragma mark - Query

- (MTRule *)ruleWithId:(NSString *)ruleId {
    for (MTRule *rule in self.mutableRules) {
        if ([rule.ruleId isEqualToString:ruleId]) {
            return rule;
        }
    }
    return nil;
}

- (NSArray<MTRule *> *)enabledRules {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"enabled == YES"];
    return [self.mutableRules filteredArrayUsingPredicate:predicate];
}

- (NSArray<MTRule *> *)rulesForInterface:(NSString *)interfaceName {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"interfaceName == %@", interfaceName];
    return [self.mutableRules filteredArrayUsingPredicate:predicate];
}

#pragma mark - Persistence

- (void)saveRules {
    NSMutableArray *dictArray = [NSMutableArray arrayWithCapacity:self.mutableRules.count];
    for (MTRule *rule in self.mutableRules) {
        MTRuleModel *model = [rule toRuleModel];
        [dictArray addObject:[model toDictionary]];
    }

    // Save to file in App Group container (more reliable for System Extensions)
    NSURL *containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kMTAppGroupIdentifier];
    NSURL *rulesFileURL = [containerURL URLByAppendingPathComponent:@"rules.plist"];
    
    NSLog(@"[RuleManager] Saving %lu rules to: %@", (unsigned long)dictArray.count, rulesFileURL.path);
    
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dictArray
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (error) {
        NSLog(@"[RuleManager] Error serializing rules: %@", error);
        return;
    }
    
    BOOL success = [data writeToURL:rulesFileURL options:NSDataWritingAtomic error:&error];
    if (!success) {
        NSLog(@"[RuleManager] Error writing rules file: %@", error);
    } else {
        NSLog(@"[RuleManager] Rules saved successfully");
    }

    [self syncRulesToExtension];
}

- (void)loadRules {
    // Load from file in App Group container
    NSURL *containerURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kMTAppGroupIdentifier];
    NSURL *rulesFileURL = [containerURL URLByAppendingPathComponent:@"rules.plist"];
    
    NSLog(@"[RuleManager] Loading rules from: %@", rulesFileURL.path);
    
    NSData *data = [NSData dataWithContentsOfURL:rulesFileURL];
    if (!data) {
        NSLog(@"[RuleManager] No rules file found");
        return;
    }
    
    NSError *error = nil;
    NSArray *dictArray = [NSPropertyListSerialization propertyListWithData:data
                                                                   options:NSPropertyListImmutable
                                                                    format:NULL
                                                                     error:&error];
    if (error || ![dictArray isKindOfClass:[NSArray class]]) {
        NSLog(@"[RuleManager] Error reading rules: %@", error);
        return;
    }

    [self willChangeValueForKey:@"rules"];
    [self.mutableRules removeAllObjects];

    for (NSDictionary *dict in dictArray) {
        MTRuleModel *model = [[MTRuleModel alloc] initWithDictionary:dict];
        MTRule *rule = [[MTRule alloc] initWithRuleModel:model];
        [self.mutableRules addObject:rule];
    }

    [self didChangeValueForKey:@"rules"];
    NSLog(@"[RuleManager] Loaded %lu rules", (unsigned long)self.mutableRules.count);
}

#pragma mark - Import/Export

- (BOOL)exportRulesToURL:(NSURL *)url error:(NSError **)error {
    NSMutableArray *dictArray = [NSMutableArray arrayWithCapacity:self.mutableRules.count];
    for (MTRule *rule in self.mutableRules) {
        MTRuleModel *model = [rule toRuleModel];
        [dictArray addObject:[model toDictionary]];
    }

    NSDictionary *exportDict = @{
        @"version": @1,
        @"exportDate": [NSDate date].description,
        @"rules": dictArray
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:exportDict
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:error];
    if (!jsonData) {
        return NO;
    }

    return [jsonData writeToURL:url options:NSDataWritingAtomic error:error];
}

- (BOOL)importRulesFromURL:(NSURL *)url error:(NSError **)error {
    NSData *jsonData = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!jsonData) {
        return NO;
    }

    NSDictionary *importDict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                               options:0
                                                                 error:error];
    if (!importDict) {
        return NO;
    }

    NSArray *dictArray = importDict[@"rules"];
    if (![dictArray isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"MTRuleManager"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid file format"}];
        }
        return NO;
    }

    NSMutableArray<MTRule *> *importedRules = [NSMutableArray array];
    for (NSDictionary *dict in dictArray) {
        MTRuleModel *model = [[MTRuleModel alloc] initWithDictionary:dict];
        // Generate new IDs for imported rules
        model.ruleId = [[NSUUID UUID] UUIDString];
        MTRule *rule = [[MTRule alloc] initWithRuleModel:model];
        [importedRules addObject:rule];
    }

    [self willChangeValueForKey:@"rules"];
    [self.mutableRules addObjectsFromArray:importedRules];
    [self didChangeValueForKey:@"rules"];

    [self updatePriorities];
    [self saveRules];
    [self postNotificationWithType:MTRuleManagerChangeTypeReload rule:nil index:NSNotFound];

    return YES;
}

#pragma mark - Extension Sync

- (void)syncRulesToExtension {
    // Post notification for extension to reload rules
    [[NSDistributedNotificationCenter defaultCenter]
     postNotificationName:kMTRulesDidChangeNotification
     object:nil
     userInfo:nil
     deliverImmediately:YES];
}

#pragma mark - Private

- (void)updatePriorities {
    for (NSUInteger i = 0; i < self.mutableRules.count; i++) {
        self.mutableRules[i].priority = i;
    }
}

- (void)postNotificationWithType:(MTRuleManagerChangeType)type
                            rule:(nullable MTRule *)rule
                           index:(NSUInteger)index {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[MTRuleManagerChangeTypeKey] = @(type);
    if (rule) {
        userInfo[MTRuleManagerChangedRuleKey] = rule;
    }
    if (index != NSNotFound) {
        userInfo[MTRuleManagerChangedIndexKey] = @(index);
    }

    [[NSNotificationCenter defaultCenter]
     postNotificationName:MTRuleManagerDidChangeNotification
     object:self
     userInfo:userInfo];
}

@end
