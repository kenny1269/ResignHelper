//
//  ArgumentParser.h
//  ResignHelper
//
//  Created by Jordon on 2019/5/1.
//  Copyright © 2019年 junhai. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ArgumentParser : NSObject

+ (void)addArgumentWithKey:(NSString *)key option:(NSString *)option description:(NSString *)description required:(BOOL)required;

+ (void)parse;

+ (NSString *)valueForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
