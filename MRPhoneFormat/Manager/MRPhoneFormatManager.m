//
//  MRPhoneFormatManager.m
//  Imora
//
//  Created by Panyangjun on 2017/6/29.
//  Copyright © 2017年 Mr Poon. All rights reserved.
//

#import "MRPhoneFormatManager.h"

#pragma mark - PhoneRule Model
@interface PhoneRule : NSObject

@property (nonatomic, assign) NSInteger minVal;
@property (nonatomic, assign) NSInteger maxVal;
@property (nonatomic, assign) NSInteger byte8;
@property (nonatomic, assign) NSInteger maxLen;
@property (nonatomic, assign) NSInteger otherFlag;
@property (nonatomic, assign) NSInteger prefixLen;
@property (nonatomic, assign) NSInteger flag12;
@property (nonatomic, assign) NSInteger flag13;
@property (nonatomic) NSString *format;
@property (nonatomic, readonly) BOOL hasIntlPrefix;
@property (nonatomic, readonly) BOOL hasTrunkPrefix;


- (NSString *)format:(NSString *)str intlPrefix:(NSString *)intlPrefix trunkPrefix:(NSString *)trunkPrefix;

@end

@implementation PhoneRule

- (BOOL)hasIntlPrefix {
    return (self.flag12 & 0x02);
}

- (BOOL)hasTrunkPrefix {
    return (self.flag12 & 0x01);
}

- (NSString *)format:(NSString *)str intlPrefix:(NSString *)intlPrefix trunkPrefix:(NSString *)trunkPrefix {
    BOOL hadC = NO;
    BOOL hadN = NO;
    BOOL hasOpen = NO;
    int spot = 0;
    NSMutableString *res = [NSMutableString stringWithCapacity:20];
    for (int i = 0; i < [self.format length]; i++) {
        unichar ch = [self.format characterAtIndex:i];
        switch (ch) {
            case 'c':
                // Add international prefix if there is one.
                hadC = YES;
                if (intlPrefix != nil) {
                    [res appendString:intlPrefix];
                }
                break;
            case 'n':
                // Add trunk prefix if there is one.
                hadN = YES;
                if (trunkPrefix != nil) {
                    [res appendString:trunkPrefix];
                }
                break;
            case '#':
                // Add next digit from number. If there aren't enough digits left then do nothing unless we need to
                // space-fill a pair of parenthesis.
                if (spot < [str length]) {
                    [res appendString:[str substringWithRange:NSMakeRange(spot, 1)]];
                    spot++;
                } else if (hasOpen) {
                    [res appendString:@" "];
                }
                break;
            case '(':
                // Flag we found an open paren so it can be space-filled. But only do so if we aren't beyond the
                // end of the number.
                if (spot < [str length]) {
                    hasOpen = YES;
                }
                // fall through
            default: // rest like ) and -
                // Don't show space after n if no trunkPrefix or after c if no intlPrefix
                if (!(ch == ' ' && i > 0 && (([self.format characterAtIndex:i - 1] == 'n' && trunkPrefix == nil) || ([self.format characterAtIndex:i - 1] == 'c' && intlPrefix == nil)))) {
                    // Only show punctuation if not beyond the end of the supplied number.
                    // The only exception is to show a close paren if we had found
                    if (spot < [str length] || (hasOpen && ch == ')')) {
                        [res appendString:[self.format substringWithRange:NSMakeRange(i, 1)]];
                        if (ch == ')') {
                            hasOpen = NO; // close it
                        }
                    }
                }
                break;
        }
    }
    
    // Not all format strings have a 'c' or 'n' in them. If we have an international prefix or a trunk prefix but the
    // format string doesn't explictly say where to put it then simply add it to the beginning.
    if (intlPrefix != nil && !hadC) {
        [res insertString:[NSString stringWithFormat:@"%@ ", intlPrefix] atIndex:0];
    } else if (trunkPrefix != nil && !hadN) {
        [res insertString:trunkPrefix atIndex:0];
    }
    
    return res;
}



@end

#pragma mark - RuleSet

@interface RuleSet : NSObject

@property (nonatomic, assign) int matchLen;
@property (nonatomic) NSMutableArray *rules;
@property (nonatomic, assign) BOOL hasRuleWithIntlPrefix;
@property (nonatomic, assign) BOOL hasRuleWithTrunkPrefix;

- (NSString *)format:(NSString *)str intlPrefix:(NSString *)intlPrefix trunkPrefix:(NSString *)trunkPrefix prefixRequired:(BOOL)prefixRequired;

@end

@implementation RuleSet

- (NSString *)format:(NSString *)str intlPrefix:(NSString *)intlPrefix trunkPrefix:(NSString *)trunkPrefix prefixRequired:(BOOL)prefixRequired {
    // First check the number's length against this rule set's match length. If the supplied number is too short then
    // this rule set is ignored.
    if ([str length] >= self.matchLen) {
        // Otherwise we make two passes through the rules in the set. The first pass looks for rules that match the
        // number's prefix and length. It also finds the best rule match based on the prefix flag.
        NSString *begin = [str substringToIndex:self.matchLen];
        int val = [begin intValue];
        for (PhoneRule *rule in self.rules) {
            // Check the rule's range and length against the start of the number
            if (val >= rule.minVal && val <= rule.maxVal && [str length] <= rule.maxLen) {
                if (prefixRequired) {
                    // This pass is trying to find the most restrictive match
                    // A prefix flag of 0 means the format string does not explicitly use the trunk prefix or
                    // international prefix. So only use one of these if the number has no trunk or international prefix.
                    // A prefix flag of 1 means the format string has a reference to the trunk prefix. Only use that
                    // rule if the number has a trunk prefix.
                    // A prefix flag of 2 means the format string has a reference to the international prefix. Only use
                    // that rule if the number has an international prefix.
                    if (((rule.flag12 & 0x03) == 0 && trunkPrefix == nil && intlPrefix == nil) || (trunkPrefix != nil && (rule.flag12 & 0x01)) || (intlPrefix != nil && (rule.flag12 & 0x02))) {
                        return [rule format:str intlPrefix:intlPrefix trunkPrefix:trunkPrefix];
                    }
                } else {
                    // This pass is less restrictive. If this is called it means there was not an exact match based on
                    // prefix flag and any supplied prefix in the number. So now we can use this rule if there is no
                    // prefix regardless of the flag12.
                    if ((trunkPrefix == nil && intlPrefix == nil) || (trunkPrefix != nil && (rule.flag12 & 0x01)) || (intlPrefix != nil && (rule.flag12 & 0x02))) {
                        return [rule format:str intlPrefix:intlPrefix trunkPrefix:trunkPrefix];
                    }
                }
            }
        }
        
        // If we get this far it means the supplied number has either a trunk prefix or an international prefix but
        // none of the rules explictly use that prefix. So now we make one last pass finding a matching rule by totally
        // ignoring the prefix flag.
        if (!prefixRequired) {
            if (intlPrefix != nil) {
                // Strings with intl prefix should use rule with c in it if possible. If not found above then find
                // matching rule with no c.
                for (PhoneRule *rule in self.rules) {
                    if (val >= rule.minVal && val <= rule.maxVal && [str length] <= rule.maxLen) {
                        if (trunkPrefix == nil || (rule.flag12 & 0x01)) {
                            // We found a matching rule.
                            return [rule format:str intlPrefix:intlPrefix trunkPrefix:trunkPrefix];
                        }
                    }
                }
            } else if (trunkPrefix != nil) {
                // Strings with trunk prefix should use rule with n in it if possible. If not found above then find
                // matching rule with no n.
                for (PhoneRule *rule in self.rules) {
                    if (val >= rule.minVal && val <= rule.maxVal && [str length] <= rule.maxLen) {
                        if (intlPrefix == nil || (rule.flag12 & 0x02)) {
                            // We found a matching rule.
                            return [rule format:str intlPrefix:intlPrefix trunkPrefix:trunkPrefix];
                        }
                    }
                }
            }
        }
        
        return nil; // no match found
    } else {
        return nil; // not long enough to compare
    }
}

- (BOOL)isValid:(NSString *)str intlPrefix:(NSString *)intlPrefix trunkPrefix:(NSString *)trunkPrefix prefixRequired:(BOOL)prefixRequired {
    // First check the number's length against this rule set's match length. If the supplied number is the wrong length then
    // this rule set is ignored.
    if ([str length] >= self.matchLen) {
        // Otherwise we make two passes through the rules in the set. The first pass looks for rules that match the
        // number's prefix and length. It also finds the best rule match based on the prefix flag.
        NSString *begin = [str substringToIndex:self.matchLen];
        int val = [begin intValue];
        for (PhoneRule *rule in self.rules) {
            // Check the rule's range and length against the start of the number
            if (val >= rule.minVal && val <= rule.maxVal && [str length] == rule.maxLen) {
                if (prefixRequired) {
                    // This pass is trying to find the most restrictive match
                    // A prefix flag of 0 means the format string does not explicitly use the trunk prefix or
                    // international prefix. So only use one of these if the number has no trunk or international prefix.
                    // A prefix flag of 1 means the format string has a reference to the trunk prefix. Only use that
                    // rule if the number has a trunk prefix.
                    // A prefix flag of 2 means the format string has a reference to the international prefix. Only use
                    // that rule if the number has an international prefix.
                    if (((rule.flag12 & 0x03) == 0 && trunkPrefix == nil && intlPrefix == nil) || (trunkPrefix != nil && (rule.flag12 & 0x01)) || (intlPrefix != nil && (rule.flag12 & 0x02))) {
                        return YES; // full match
                    }
                } else {
                    // This pass is less restrictive. If this is called it means there was not an exact match based on
                    // prefix flag and any supplied prefix in the number. So now we can use this rule if there is no
                    // prefix regardless of the flag12.
                    if ((trunkPrefix == nil && intlPrefix == nil) || (trunkPrefix != nil && (rule.flag12 & 0x01)) || (intlPrefix != nil && (rule.flag12 & 0x02))) {
                        return YES; // full match
                    }
                }
            }
        }
        
        // If we get this far it means the supplied number has either a trunk prefix or an international prefix but
        // none of the rules explictly use that prefix. So now we make one last pass finding a matching rule by totally
        // ignoring the prefix flag.
        if (!prefixRequired) {
            if (intlPrefix != nil && !self.hasRuleWithIntlPrefix) {
                // Strings with intl prefix should use rule with c in it if possible. If not found above then find
                // matching rule with no c.
                for (PhoneRule *rule in self.rules) {
                    if (val >= rule.minVal && val <= rule.maxVal && [str length] == rule.maxLen) {
                        if (trunkPrefix == nil || (rule.flag12 & 0x01)) {
                            // We found a matching rule.
                            return YES;
                        }
                    }
                }
            } else if (trunkPrefix != nil && !self.hasRuleWithTrunkPrefix) {
                // Strings with trunk prefix should use rule with n in it if possible. If not found above then find
                // matching rule with no n.
                for (PhoneRule *rule in self.rules) {
                    if (val >= rule.minVal && val <= rule.maxVal && [str length] == rule.maxLen) {
                        if (intlPrefix == nil || (rule.flag12 & 0x02)) {
                            // We found a matching rule.
                            return YES;
                        }
                    }
                }
            }
        }
        
        return NO; // no match found
    } else {
        return NO; // not the correct length
    }
}


@end


@interface CallingCodeInfo : NSObject

@property (nonatomic) NSSet *countries;
@property (nonatomic) NSString *callingCode;
@property (nonatomic) NSMutableArray *trunkPrefixes;
@property (nonatomic) NSMutableArray *intlPrefixes;
@property (nonatomic) NSMutableArray *ruleSets;
@property (nonatomic) NSMutableArray *formatStrings;

- (NSString *)matchingAccessCode:(NSString *)str;
- (NSString *)format:(NSString *)orig andPlusPrefix:(BOOL)isPlusPrefix;

@end

@implementation CallingCodeInfo

- (NSString *)matchingAccessCode:(NSString *)str {
    for (NSString *code in self.intlPrefixes) {
        if ([str hasPrefix:code]) {
            return code;
        }
    }
    
    return nil;
}

- (NSString *)matchingTrunkCode:(NSString *)str {
    for (NSString *code in self.trunkPrefixes) {
        if ([str hasPrefix:code]) {
            return code;
        }
    }
    return nil;
}

- (NSString *)format:(NSString *)orig andPlusPrefix:(BOOL)isPlusPrefix{
    // First see if the number starts with either the country's trunk prefix or international prefix. If so save it
    // off and remove from the number.
    NSString *str = orig;
    NSString *trunkPrefix = nil;
    NSString *intlPrefix = nil;
    if ([str hasPrefix:self.callingCode] && isPlusPrefix) {
        intlPrefix = self.callingCode;
        str = [str substringFromIndex:[intlPrefix length]];
    } else {
        NSString *trunk = [self matchingTrunkCode:str];
        if (trunk) {
            trunkPrefix = trunk;
            str = [str substringFromIndex:[trunkPrefix length]];
        }
    }
    
    // Scan through all sets find best match with no optional prefixes allowed
    for (RuleSet *set in self.ruleSets) {
        NSString *phone = [set format:str intlPrefix:intlPrefix trunkPrefix:trunkPrefix prefixRequired:YES];
        if (phone) {
            return phone;
        }
    }
    
    // No exact matches so now allow for optional prefixes
    for (RuleSet *set in self.ruleSets) {
        NSString *phone = [set format:str intlPrefix:intlPrefix trunkPrefix:trunkPrefix prefixRequired:NO];
        if (phone) {
            return phone;
        }
    }
    
    // No rules matched. If there is an international prefix then display and the rest of the number with a space.
    if (intlPrefix != nil && [str length]) {
        return [NSString stringWithFormat:@"%@ %@", intlPrefix, str];
    }
    
    // Nothing worked so just return the original number as-is.
    return orig;
}


@end




static NSCharacterSet *phoneChars = nil;

@interface MRPhoneFormatManager ()
@property(nonatomic, strong) NSArray *countryCodes;
@property(nonatomic, strong) NSArray *specialCodes;
@end

@implementation MRPhoneFormatManager {
    NSData *_data;
    NSString *_defaultCountry;
    NSString *_defaultCallingCode;
    NSMutableDictionary *_callingCodeOffsets;
    NSMutableDictionary *_callingCodeCountries;
    NSMutableDictionary *_callingCodeData;
    NSMutableDictionary *_countryCallingCode;
}

+ (void)initialize {
    phoneChars = [NSCharacterSet characterSetWithCharactersInString:@"0123456789,;+*#"];
    
}

+ (NSString *)strip:(NSString *)str {
    NSMutableString *res = [NSMutableString stringWithString:str];
    for (NSInteger i = res.length - 1; i >= 0; i--) {
        if (![phoneChars characterIsMember:[res characterAtIndex:i]]) {
            [res deleteCharactersInRange:NSMakeRange(i, 1)];
        }
    }
    
    return res;
}

+ (MRPhoneFormatManager *)defaultInstance {
    static MRPhoneFormatManager *instance = nil;
    static dispatch_once_t predicate = 0;
    
    dispatch_once(&predicate, ^{ instance = [self new]; });
    
    return instance;
}

- (id)init {
    self = [self initWithDefaultCountry:nil];
    
    return self;
}

- (id)initWithDefaultCountry:(NSString *)countryCode {
    if ((self = [super init])) {
        _data = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"PhoneFormats" ofType:@"dat"]];
        if (countryCode.length) {
            _defaultCountry = countryCode;
        } else {
            NSLocale *loc = [NSLocale currentLocale];
            _defaultCountry = [[loc objectForKey:NSLocaleCountryCode] lowercaseString];
        }
        _callingCodeOffsets = [[NSMutableDictionary alloc] initWithCapacity:255];
        _callingCodeCountries = [[NSMutableDictionary alloc] initWithCapacity:255];
        _callingCodeData = [[NSMutableDictionary alloc] initWithCapacity:10];
        _countryCallingCode = [[NSMutableDictionary alloc] initWithCapacity:255];
        
        [self parseDataHeader];
    }
    
    return self;
}

- (NSString *)defaultCallingCode {
    return [self callingCodeForCountryCode:_defaultCountry];
}

- (NSString *)callingCodeForCountryCode:(NSString *)countryCode {
    return [_countryCallingCode objectForKey:[countryCode lowercaseString]];
}

- (NSSet *)countriesForCallingCode:(NSString *)callingCode {
    if ([callingCode hasPrefix:@"+"]) {
        callingCode = [callingCode substringFromIndex:1];
    }
    
    return [_callingCodeCountries objectForKey:callingCode];
}

- (CallingCodeInfo *)findCallingCodeInfo:(NSString *)str {
    CallingCodeInfo *res = nil;
    for (int i = 0; i < 3; i++) {
        if (i < [str length]) {
            res = [self callingCodeInfo:[str substringToIndex:i + 1]];
            if (res) {
                break;
            }
        } else {
            break;
        }
    }
    
    return res;
}
-(NSArray *)countryCodes
{
    if (!_countryCodes) {
        _countryCodes = @[@"86",@"886",@"81",@"82"];
    }
    return _countryCodes;
}
-(NSArray *)specialCodes
{
    if (!_specialCodes) {
        _specialCodes = @[@",",@";",@"*",@"#"];
    }
    return _specialCodes;
}
-(NSCharacterSet *)phoneNumberChars
{
    if (!_phoneNumberChars) {
        _phoneNumberChars = phoneChars;
    }
    return _phoneNumberChars;
}

- (BOOL)isMobileNumber:(NSString *)mobileNum {
    NSString *secondStr = @"34578";
    if ([mobileNum hasPrefix:@"1"]) {
        if (mobileNum.length > 1) {
            if ([secondStr containsString:[mobileNum substringWithRange:NSMakeRange(1, 1)]]) {
                return YES;
            }
        }
    }
    return NO;
}

-(NSString *)formatNumberAndDelZero:(NSString *)phoneNumber
{
    NSString *formatStr = [self formatNumber:phoneNumber];
    if (!formatStr) {
        return @"";
    }
    formatStr = [self numberStringDelZero:formatStr];
    return formatStr;
}

-(NSString *)numberStringDelZero:(NSString *)number
{
    //去除国家码和手机号之间的（0）
    NSString *formatString = number;
    if ([formatString hasPrefix:@"+"]) {
        NSString *zeroStr = @" (0) ";
        if ([formatString containsString:zeroStr]) {
            formatString = [formatString stringByReplacingOccurrencesOfString:zeroStr withString:@""];
        }
    }
    return formatString;
}


-(NSString *)formatNumber:(NSString *)phoneNumber {
    NSString *orig = phoneNumber;
    NSString *str = [MRPhoneFormatManager strip:orig];
    BOOL haveExtensionCode = NO; //分机号处理
    NSString *separateStr = @"";
    for (NSString *specialCode in self.specialCodes) {
        if ([str containsString:specialCode]) {
            separateStr = specialCode;
            break;
        }
    }
    NSString *extensionStr = @"";
    if ([str containsString:separateStr]) {
        haveExtensionCode = YES;
        NSArray *components = [str componentsSeparatedByString:separateStr];
        NSString *firstComponent = [components firstObject];
        extensionStr = [str substringFromIndex:firstComponent.length];
        str = firstComponent;
    }
    
    NSString *numberStr;
    if ([str hasPrefix:@"+"]) {
        numberStr = [self handleNumberFormatWithCountryCodeAndStr:str andOriginStr:orig andExtensionCode:extensionStr];
    } else {
        numberStr = [self handleNumberFormatWithStr:str andOriginStr:orig andExtensionCode:extensionStr];
    }
    return [numberStr stringByReplacingOccurrencesOfString:@"-" withString:@" "];
}

//国家码+手机/电话
-(NSString *)handleNumberFormatWithCountryCodeAndStr:(NSString *)str andOriginStr:(NSString *)orig andExtensionCode:(NSString *)extensionCode
{
    BOOL haveZoroCode = NO;
    BOOL isValidCode = NO;
    NSString *countryCode;
    for (NSString *code in self.countryCodes) {
        if ([[str substringFromIndex:1] hasPrefix:code]) {
            isValidCode = YES;
            countryCode = code;
            break;
        }
    }
    NSString *rest = [str substringFromIndex:1];
    if (isValidCode && rest.length > countryCode.length) {
        NSString *tempStr = [rest substringWithRange:NSMakeRange(countryCode.length, 1)];
        if ([tempStr isEqualToString:@"0"]) {
            haveZoroCode = YES;
            if (rest.length > countryCode.length + 1) {
                //+86大陆手机号 (0)处理
                NSString *number = [rest substringFromIndex:countryCode.length + 1];
                if ([self isMobileNumber:number] && number.length > 3 && [countryCode isEqualToString:@"86"]) {
                    haveZoroCode = NO;
                }else{
                    rest = [NSString stringWithFormat:@"%@%@",countryCode,[rest substringFromIndex:countryCode.length + 1]];
                }
            }else{
                rest = [NSString stringWithFormat:@"%@",countryCode];
            }
        }
        
    }
    CallingCodeInfo *info = [self findCallingCodeInfo:rest];
    if (info) {
        NSString *phone = [info format:rest andPlusPrefix:YES];
        if ([phone hasPrefix:@"81"] && phone.length > 3) {//日本号码格式统一替换为“-”
            NSString *value = [phone substringFromIndex:3];
            if ([value containsString:@" "]) {
                value = [value stringByReplacingOccurrencesOfString:@" " withString:@"-"];
            }
            phone = [@"81 " stringByAppendingString:value];
        }
        if (haveZoroCode) {
            NSString *centerStr = @" (0) ";
            if ((phone.length - countryCode.length) > 1) {
                phone = [NSString stringWithFormat:@"%@%@%@", countryCode, centerStr,[phone substringFromIndex:countryCode.length + 1]];
            }else{
                phone = [NSString stringWithFormat:@"%@%@", countryCode, centerStr];
            }
        }
        if (extensionCode.length > 0) {
            phone = [phone stringByAppendingString:extensionCode];
        }
        return [@"+" stringByAppendingString:phone];
    } else {
        return orig;
    }
}
//（无国家码）手机/电话
-(NSString *)handleNumberFormatWithStr:(NSString *)str andOriginStr:(NSString *)orig andExtensionCode:(NSString *)extensionCode
{
    CallingCodeInfo *info = [self callingCodeInfo:_defaultCallingCode];
    if (info == nil) {
        return orig;
    }
    NSString *accessCode = [info matchingAccessCode:str];
    if (accessCode) {
        NSString *rest = [str substringFromIndex:[accessCode length]];
        NSString *phone = rest;
        CallingCodeInfo *info2 = [self findCallingCodeInfo:rest];
        if (info2) {
            phone = [info2 format:rest andPlusPrefix:NO];
        }
        if (extensionCode.length > 0) {
            phone = [phone stringByAppendingString:extensionCode];
        }
        if ([phone length] == 0) {
            return accessCode;
        } else {
            return [NSString stringWithFormat:@"%@ %@", accessCode, phone];
        }
    } else {
        NSString *phone = [info format:str andPlusPrefix:NO];
        if (extensionCode.length > 0) {
            phone = [phone stringByAppendingString:extensionCode];
        }
        return phone;
    }
}


- (uint32_t)value32:(NSUInteger)offset {
    if (offset + 4 <= [_data length]) {
        return OSReadLittleInt32([_data bytes], offset);
    } else {
        return 0;
    }
}

- (int)value16:(NSUInteger)offset {
    if (offset + 2 <= [_data length]) {
        return OSReadLittleInt16([_data bytes], offset);
    } else {
        return 0;
    }
}

- (int)value16BE:(NSUInteger)offset {
    if (offset + 2 <= [_data length]) {
        return OSReadBigInt16([_data bytes], offset);
    } else {
        return 0;
    }
}

- (CallingCodeInfo *)callingCodeInfo:(NSString *)callingCode {
    CallingCodeInfo *res = [_callingCodeData objectForKey:callingCode];
    if (res == nil) {
        NSNumber *num = [_callingCodeOffsets objectForKey:callingCode];
        if (num) {
            const uint8_t *bytes = [_data bytes];
            NSInteger start = [num longValue];
            NSInteger offset = start;
            res = [[CallingCodeInfo alloc] init];
            res.callingCode = callingCode;
            res.countries = [_callingCodeCountries objectForKey:callingCode];
            [_callingCodeData setObject:res forKey:callingCode];
            
            uint16_t block1Len = [self value16:offset];
            offset += 4;
            uint16_t block2Len = [self value16:offset];
            offset += 4;
            uint16_t setCnt = [self value16:offset];
            offset += 4;
            NSMutableArray *strs = [NSMutableArray arrayWithCapacity:5];
            NSString *str;
            while ([(str = [NSString stringWithCString:(char *)bytes + offset encoding:NSUTF8StringEncoding]) length]) {
                [strs addObject:str];
                offset += [str length] + 1;
            }
            res.trunkPrefixes = strs;
            offset++; // skip NULL
            
            strs = [NSMutableArray arrayWithCapacity:5];
            while ([(str = [NSString stringWithCString:(char *)bytes + offset encoding:NSUTF8StringEncoding]) length]) {
                [strs addObject:str];
                offset += [str length] + 1;
            }
            res.intlPrefixes = strs;
            
            NSMutableArray *ruleSets = [NSMutableArray arrayWithCapacity:setCnt];
            offset = start + block1Len; // Start of rule sets
            for (int s = 0; s < setCnt; s++) {
                RuleSet *ruleSet = [[RuleSet alloc] init];
                int matchCnt = [self value16:offset];
                ruleSet.matchLen = matchCnt;
                offset += 2;
                int ruleCnt = [self value16:offset];
                offset += 2;
                NSMutableArray *rules = [NSMutableArray arrayWithCapacity:ruleCnt];
                for (int r = 0; r < ruleCnt; r++) {
                    PhoneRule *rule = [[PhoneRule alloc] init];
                    rule.minVal = [self value32:offset];
                    offset += 4;
                    rule.maxVal = [self value32:offset];
                    offset += 4;
                    rule.byte8 = (int)bytes[offset++];
                    rule.maxLen = (int)bytes[offset++];
                    rule.otherFlag = (int)bytes[offset++];
                    rule.prefixLen = (int)bytes[offset++];
                    rule.flag12 = (int)bytes[offset++];
                    rule.flag13 = (int)bytes[offset++];
                    uint16_t strOffset = [self value16:offset];
                    offset += 2;
                    rule.format = [NSString stringWithCString:(char *)bytes + start + block1Len + block2Len + strOffset encoding:NSUTF8StringEncoding];
                    // Several formats contain [[9]] or [[8]]. Using the Contacts app as a test, I can find no use
                    // for these. Do they mean "optional"? They don't seem to have any use. This code strips out
                    // anything in [[..]]
                    NSRange openPos = [rule.format rangeOfString:@"[["];
                    if (openPos.location != NSNotFound) {
                        NSRange closePos = [rule.format rangeOfString:@"]]"];
                        rule.format = [NSString stringWithFormat:@"%@%@", [rule.format substringToIndex:openPos.location], [rule.format substringFromIndex:closePos.location + closePos.length]];
                    }
                    
                    [rules addObject:rule];
                    
                    if (rule.hasIntlPrefix) {
                        ruleSet.hasRuleWithIntlPrefix = YES;
                    }
                    if (rule.hasTrunkPrefix) {
                        ruleSet.hasRuleWithTrunkPrefix = YES;
                    }
                }
                ruleSet.rules = rules;
                [ruleSets addObject:ruleSet];
            }
            res.ruleSets = ruleSets;
        }
    }
    
    return res;
}

- (void)parseDataHeader {
    int count = [self value32:0];
    uint32_t base = count * 12 + 4;
    const void *bytes = [_data bytes];
    NSUInteger spot = 4;
    for (int i = 0; i < count; i++) {
        NSString *callingCode = [NSString stringWithCString:bytes + spot encoding:NSUTF8StringEncoding];
        spot += 4;
        NSString *country = [NSString stringWithCString:bytes + spot encoding:NSUTF8StringEncoding];
        spot += 4;
        uint32_t offset = [self value32:spot] + base;
        spot += 4;
        
        if ([country isEqualToString:_defaultCountry]) {
            _defaultCallingCode = callingCode;
        }
        
        [_countryCallingCode setObject:callingCode forKey:country];
        
        [_callingCodeOffsets setObject:[NSNumber numberWithLong:offset] forKey:callingCode];
        NSMutableSet *countries = [_callingCodeCountries objectForKey:callingCode];
        if (!countries) {
            countries = [[NSMutableSet alloc] init];
            [_callingCodeCountries setObject:countries forKey:callingCode];
        }
        [countries addObject:country];
    }
    
    if (_defaultCallingCode) {
        [self callingCodeInfo:_defaultCallingCode];
    }
}


#pragma mark -

- (BOOL)isValidateByRegex:(NSString *)regex andNumber:(NSString *)number{
    NSPredicate *pre = [NSPredicate predicateWithFormat:@"SELF MATCHES %@",regex];
    return [pre evaluateWithObject:number];
}

//手机号分服务商
- (BOOL)isPhoneNumberValid:(NSString *)number{
    
    /**
     * 手机号码
     * 移动：134[0-8],135,136,137,138,139,150,151,152,157,158,159,182,183,187,188,1705,147,178
     * 联通：130,131,132,152,155,156,185,186,1709,145,176,1709
     * 电信：133,1349,153,180,181,189,1700,177
     */
    NSString * CM = @"^1(34[0-8]|(3[5-9]|47|5[0127-9]|78|8[2-478])\\d|705)\\d{7}$";
    NSString * CU = @"^1((3[0-2]|45|5[56]|76|8[56])\\d|709)\\d{7}$";
    NSString * CT = @"^1((33|53|8[019]|77)\\d|349|700)\\d{7}$";
    
    //判断是否+86
    number = [MRPhoneFormatManager strip:number];
    if ([number hasPrefix:@"+86"]) {
        number = [self numberStringDelZero:number];
        number = [number substringFromIndex:3];
    }
    //    NSPredicate *regextestmobile = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", MOBILE];
    if (([self isValidateByRegex:CM andNumber:number])
        || ([self isValidateByRegex:CU andNumber:number])
        || ([self isValidateByRegex:CT andNumber:number])){
        return YES;
    }
    else{
        return NO;
    }
}

- (NSString *)removeFormatForNumber:(NSString *)number
{
    
    if (!number) {
        return @"";
    }
    NSCharacterSet *phoneChars = [NSCharacterSet characterSetWithCharactersInString:@"0123456789;+*#"];
    NSMutableString *res = [NSMutableString stringWithString:number];
    for (NSInteger i = res.length - 1; i >= 0; i--) {
        if (![phoneChars characterIsMember:[res characterAtIndex:i]]) {
            [res deleteCharactersInRange:NSMakeRange(i, 1)];
        }
    }
    NSString *newNumber = res;
    if ([newNumber hasPrefix:@"+"]) {
        newNumber = [newNumber substringFromIndex:1];
        if (newNumber.length > 2) {
            for (NSString *code in self.countryCodes) {
                if ([newNumber hasPrefix:code]) {
                    newNumber = [newNumber substringFromIndex:2];
                    break;
                }
            }
        }
    }
    return newNumber;
}

@end
