//
//  ArgumentParser.m
//  ResignHelper
//
//  Created by Jordon on 2019/5/1.
//  Copyright © 2019年 junhai. All rights reserved.
//

#import "ArgumentParser.h"

@interface Argument : NSObject

@property (nonatomic, copy) NSString *key;

@property (nonatomic, copy) NSString *option;

@property (nonatomic, copy) NSString *desc;

@property (nonatomic, assign) BOOL required;

@property (nonatomic, copy) NSString *value;

@end

@implementation Argument

@end

@interface ArgumentParser ()

@property (nonatomic, class, strong) NSMutableDictionary *arguments;

@end

@implementation ArgumentParser

@dynamic arguments;

+ (void)addArgumentWithKey:(NSString *)key option:(NSString *)option description:(NSString *)description required:(BOOL)required {
    Argument *a = [[Argument alloc] init];
    a.key = key;
    a.option = option;
    a.desc = description;
    a.required = required;
    
    self.arguments[key] = a;
}

+ (void)parse {
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    
    for (NSInteger i = 1; i < arguments.count; i++) {
        NSString *argument = arguments[i];
        
        for (Argument *a in self.arguments.allValues) {
            if ([a.option isEqualToString:argument]) {
                if (i+1 < arguments.count) {
                    a.value = arguments[i+1];
                }
            }
        }
    }
    
    for (Argument *a in self.arguments.allValues) {
        if (a.required && a.value == nil) {
            NSLog(@"argument %@ is required", a.option);
            exit(-1);
        }
    }
}

+ (NSString *)valueForKey:(NSString *)key {
    return [self.arguments[key] value];
}

#pragma mark -

+ (NSMutableDictionary *)arguments {
    static NSMutableDictionary *arguments;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        arguments = [NSMutableDictionary dictionary];
    });
    return arguments;
}

@end
