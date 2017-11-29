//
//  ViewController.m
//  MRPhoneFormat
//
//  Created by Panyangjun on 2017/11/29.
//  Copyright © 2017年 Mr Poon. All rights reserved.
//

#import "ViewController.h"
#import "MRPhoneFormatManager.h"

@interface ViewController ()<UITextFieldDelegate>

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UITextField *textField = [[UITextField alloc] init];
    textField.frame = CGRectMake(40, 64, self.view.frame.size.width - 80, 44);
    textField.backgroundColor = [UIColor lightGrayColor];
    textField.textColor = [UIColor blackColor];
    textField.font = [UIFont systemFontOfSize:18];
    textField.keyboardType = UIKeyboardTypePhonePad;
    textField.delegate = self;
    [self.view addSubview:textField];
    UILabel *label = [[UILabel alloc] init];
    label.numberOfLines = 0;
    label.text = @"支持手机号/电话格式化,格式标准和iPhone系统一致";
    label.frame = CGRectMake(40, CGRectGetMaxY(textField.frame) + 40, self.view.frame.size.width - 80, 100);
    [self.view addSubview:label];
}

#pragma mark UITextFieldDelegate methods

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    //根据光标的range获取当前操作(添加/删除)的内容
    UITextRange *selRange = textField.selectedTextRange;
    UITextPosition *selStartPos = selRange.start;
    UITextPosition *selEndPos = selRange.end;
    NSInteger start = [textField offsetFromPosition:textField.beginningOfDocument toPosition:selStartPos];
    NSInteger end = [textField offsetFromPosition:textField.beginningOfDocument toPosition:selEndPos];
    NSRange repRange;
    if (start == end) {
        if (string.length == 0) {
            repRange = NSMakeRange(start - 1, 1);
        } else {
            repRange = NSMakeRange(start, end - start);
        }
    } else {
        repRange = NSMakeRange(start, end - start);
    }
    
    //处理删除特殊字符情况
    BOOL isExistSpecial = NO;
    NSArray *specialChars = @[@"-",@" "];
    for (NSString *secialChar in specialChars) {
        if ([[textField.text substringWithRange:repRange] hasPrefix:secialChar]) {
            isExistSpecial = YES;break;
        }
    }
    
    if (isExistSpecial) {
        repRange = NSMakeRange(repRange.location - 1, repRange.length + 1);
    }
    NSString *txt = [textField.text stringByReplacingCharactersInRange:repRange withString:string];
    MRPhoneFormatManager *manager = [MRPhoneFormatManager defaultInstance];
    NSString *phone =  [manager formatNumber:txt];
    if ([phone isEqualToString:txt]) {
        return YES;
    } else {
        //记录当前光标位置
        NSInteger cnt = 0;
        for (NSUInteger i = 0; i < repRange.location + string.length; i++) {
            if ([manager.phoneNumberChars characterIsMember:[txt characterAtIndex:i]]) {
                cnt++;
            }
        }
        //计算format后字符串中光标位置
        NSInteger pos = [phone length];
        NSInteger cnt2 = 0;
        for (NSUInteger i = 0; i < [phone length]; i++) {
            if ([manager.phoneNumberChars characterIsMember:[phone characterAtIndex:i]]) {
                cnt2++;
            }
            if (cnt == 0) {
                pos = 0;
                break;
            }
            if (cnt2 == cnt) {
                pos = i + 1;
                break;
            }
        }
        textField.text = phone;
        UITextPosition *startPos = [textField positionFromPosition:textField.beginningOfDocument offset:pos];
        UITextRange *textRange = [textField textRangeFromPosition:startPos toPosition:startPos];
        textField.selectedTextRange = textRange;
        return NO;
    }
}



@end
