//
//  RuleModel.h
//  Metric
//
//  Shared rule data model for serialization between app and extension
//

#import <Foundation/Foundation.h>
#import "SharedConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTRuleModel : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *ruleId;
@property (nonatomic, assign) MTRuleType type;
@property (nonatomic, copy) NSString *pattern;
@property (nonatomic, copy) NSString *interfaceName;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *comment;
@property (nonatomic, assign) NSInteger priority;

// Convenience initializers
- (instancetype)initWithType:(MTRuleType)type
                     pattern:(NSString *)pattern
               interfaceName:(NSString *)interfaceName;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

// Serialization
- (NSDictionary *)toDictionary;

// Validation
- (BOOL)isValid;

// For CIDR rules - parsed values
@property (nonatomic, readonly) uint32_t networkAddress;
@property (nonatomic, readonly) uint32_t subnetMask;
@property (nonatomic, readonly) NSInteger prefixLength;

// Parse CIDR pattern
- (BOOL)parseCIDR;

@end

NS_ASSUME_NONNULL_END
