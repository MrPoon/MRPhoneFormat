//
//  MRPhoneFormatManager.h
//  Imora
//
//  Created by Panyangjun on 2017/6/29.
//  Copyright © 2017年 Mr Poon. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MRPhoneFormatManager : NSObject
@property(nonatomic, strong) NSCharacterSet *phoneNumberChars;
+ (MRPhoneFormatManager *)defaultInstance;

//联系人格式化 格式支持+86 156-3394-4345 / +86 156 3394 4345
- (NSString *)formatNumber:(NSString *)phoneNumber;

//联系人格式化 且去零（国家码后的零自动去除（0））
- (NSString *)formatNumberAndDelZero:(NSString *)phoneNumber;
//联系人去除（0）
- (NSString *)numberStringDelZero:(NSString *)number;

//电话/手机判断
- (BOOL)isPhoneNumberValid:(NSString *)number;
- (NSString *)removeFormatForNumber:(NSString *)number;
@end
