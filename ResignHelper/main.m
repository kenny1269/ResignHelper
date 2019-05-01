//
//  main.m
//  ResignHelper
//
//  Created by junhai on 2019/4/29.
//  Copyright © 2019年 junhai. All rights reserved.
//

#import <Foundation/Foundation.h>

static NSString *ipaPath;
static NSString *ipaInDir;
static NSString *ppPath;
static NSString *signIdentity;
static NSString *payloadPath;
static NSString *outputPath;

void cleanUp (void) {
    [[NSFileManager defaultManager] removeItemAtPath:payloadPath error:nil];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        NSLog(@"Hello, World!");
        
        NSError *error;
        
        NSArray *arguments = [[NSProcessInfo processInfo] arguments];
        
        for (NSInteger i = 1; i < arguments.count; i++) {
            NSString *argument = arguments[i];
            
            if ([argument isEqualToString:@"-p"]) {
                
                ppPath = arguments[i+1];
                
                if (![[NSFileManager defaultManager] fileExistsAtPath:ipaPath]) {
                    NSLog(@"provisioning profile not exist in %@", ipaPath);
                    return -1;
                }
                
            } else if ([argument isEqualToString:@"-i"]) {
                
                ipaPath = arguments[i+1];
                
                if (![[NSFileManager defaultManager] fileExistsAtPath:ipaPath]) {
                    NSLog(@"ipa not exist in %@", ipaPath);
                    return -1;
                }
                
                ipaInDir = [ipaPath stringByDeletingLastPathComponent];
                
            } else if ([argument isEqualToString:@"-o"]) {
                outputPath = arguments[i+1];
                
            } else if ([argument isEqualToString:@"-s"]) {
                signIdentity = arguments[i+1];
            }
        }
        
        if (!ipaPath) {
            NSLog(@"need to specify ipa path with -i");
            return -1;
        }
        
        if (!ppPath) {
            NSLog(@"need to specify provisioning profile path with -p");
            return -1;
        }
        
        if (!signIdentity) {
            NSLog(@"need to specify sign identity path with -s");
            return -1;
        }
        
        NSString *ipatToUnzipPath = [ipaInDir stringByAppendingPathComponent:@"ipaToUnzip.ipa"];
        [[NSFileManager defaultManager] copyItemAtPath:ipaPath toPath:ipatToUnzipPath error:&error];
        if (error) {
            NSLog(@"ipa unzip failed with error:%@", error);
            return -1;
        }
        
        [[NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/unzip"] arguments:@[@"-q", @"-o", ipatToUnzipPath, @"-d", ipaInDir] error:&error terminationHandler:nil] waitUntilExit];
        [[NSFileManager defaultManager] removeItemAtPath:ipatToUnzipPath error:nil];
        if (error) {
            NSLog(@"ipa unzip failed with error:%@", error);
            return -1;
        }
        
        payloadPath = [ipaInDir stringByAppendingPathComponent:@"Payload"];
        NSString *appBundlePath;
        for (NSString *subpath in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:payloadPath error:nil]) {
            if ([subpath containsString:@".app"]) {
                appBundlePath = [payloadPath stringByAppendingPathComponent:subpath];
                break;
            }
        }
        
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/security";
        task.arguments = @[@"cms", @"-D", @"-i", ppPath];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        NSFileHandle *handle = [pipe fileHandleForReading];
        [task launchAndReturnError:&error];
        if (error) {
            NSLog(@"dump entitlements error:%@", error);
            return -1;
        }
        
        NSDictionary* plist = [NSPropertyListSerialization propertyListWithData:[handle readDataToEndOfFile] options:NSPropertyListImmutable format:NULL error:&error][@"Entitlements"];
        NSMutableDictionary *entitlements = @{}.mutableCopy;
        entitlements[@"application-identifier"] = plist[@"application-identifier"];
        entitlements[@"com.apple.developer.team-identifier"] = plist[@"com.apple.developer.team-identifier"];
        entitlements[@"get-task-allow"] = plist[@"get-task-allow"];
        entitlements[@"keychain-access-groups"] = plist[@"keychain-access-groups"];
        NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:entitlements format:NSPropertyListXMLFormat_v1_0 options:kCFPropertyListImmutable error:nil];
        if (!xmlData) {
            NSLog(@"dump entitlements error:%@", error);
            return -1;
        }
        
        NSString *entitlementsPath = [appBundlePath stringByAppendingPathComponent:@"entitlements.plist"];
        if (![xmlData writeToFile:entitlementsPath options:(0) error:&error])
        {
            NSLog(@"dump entitlements error:%@", error);
            return -1;
        }
        
        NSString *embeddedPPPath = [appBundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:embeddedPPPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:embeddedPPPath error:nil];
        }
        [[NSFileManager defaultManager] copyItemAtPath:ppPath toPath:embeddedPPPath error:&error];
        if (error) {
            NSLog(@"copy pp file error:%@", error);
            return -1;
        }
        
        NSArray *subpaths = [[NSFileManager defaultManager] subpathsAtPath:appBundlePath];
        for (NSString *subpath in subpaths) {
            NSString *machoPath;
            if ([subpath hasSuffix:@".framework"]) {
                machoPath = [subpath stringByAppendingPathComponent:[[subpath stringByDeletingPathExtension] lastPathComponent]];
            }
            if ([subpath hasSuffix:@".dylib"]) {
                machoPath = subpath;
            }
            if (!machoPath) {
                continue;
            }
            [[NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/codesign"] arguments:@[@"-f", @"-s", signIdentity, [appBundlePath stringByAppendingPathComponent:machoPath]] error:nil terminationHandler:nil] waitUntilExit];
        }
        
        [[NSFileManager defaultManager] removeItemAtPath:[appBundlePath stringByAppendingPathComponent:@"_CodeSignature"] error:nil];
        
        [[NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/codesign"] arguments:@[@"-f", @"-s", signIdentity, @"--entitlements", entitlementsPath, appBundlePath] error:&error terminationHandler:nil] waitUntilExit];
        if (error) {
            NSLog(@"code sign app failed with error:%@", error);
            return -1;
        }
        
        if (![[NSFileManager defaultManager] changeCurrentDirectoryPath:ipaInDir]) {
//            NSLog(@"can't change working path");
        }
        
        NSString *targetIpaPath;
        if (outputPath) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:outputPath withIntermediateDirectories:YES attributes:nil error:nil];
            }
            targetIpaPath = [outputPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-resigned.ipa", [[ipaPath stringByDeletingPathExtension] lastPathComponent]]];
        } else {
            targetIpaPath = [ipaInDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-resigned.ipa", [[ipaPath stringByDeletingPathExtension] lastPathComponent]]];
        }
        
        [[NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/zip"] arguments:@[@"-q", @"-r", targetIpaPath, @"Payload"] error:&error terminationHandler:nil] waitUntilExit];
        if (error) {
            NSLog(@"zip payload failed with error:%@", error);
            return -1;
        }
        
        cleanUp();
        
        NSLog(@"resign complete!");
        NSLog(@"output path:%@", targetIpaPath);
    }
    return 0;
}



