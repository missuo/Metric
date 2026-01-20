//
//  Rule.h
//  Metric
//
//  Rule model for the main application
//

#import <Foundation/Foundation.h>
#import "SharedConstants.h"

NS_ASSUME_NONNULL_BEGIN

@class MTRuleModel;

@interface MTRule : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString *ruleId;
@property (nonatomic, assign) MTRuleType type;
@property (nonatomic, copy) NSString *pattern;
@property (nonatomic, copy) NSString *interfaceName;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy, nullable) NSString *comment;
@property (nonatomic, assign) NSInteger priority;

// Computed properties
@property (nonatomic, readonly) NSString *typeString;
@property (nonatomic, readonly) NSString *displayString;

// Initializers
- (instancetype)initWithType:(MTRuleType)type
                     pattern:(NSString *)pattern
               interfaceName:(NSString *)interfaceName;

- (instancetype)initWithRuleModel:(MTRuleModel *)model;

// Conversion
- (MTRuleModel *)toRuleModel;

// Validation
- (BOOL)isValid;
- (nullable NSString *)validationError;

@end

NS_ASSUME_NONNULL_END
