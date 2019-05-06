//
//  main.m
//  ResignHelper
//
//  Created by ky on 2019/4/29.
//  Copyright © 2019年 ky. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ArgumentParser.h"

#import <mach-o/fat.h>
#import <mach-o/loader.h>

static NSString *ipaPath;
static NSString *ipaInDir;
static NSString *ppPath;
static NSString *signIdentity;
static NSString *payloadPath;
static NSString *outputPath;

void cleanUp (void) {
    if (payloadPath) {
        [[NSFileManager defaultManager] removeItemAtPath:payloadPath error:nil];
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        NSLog(@"Resigning...");
        
        atexit(&cleanUp);
        
        NSError *error;
        
        [ArgumentParser addArgumentWithKey:@"ipaPath" option:@"-i" description:@"path of ipa to be resigned" required:YES];
        [ArgumentParser addArgumentWithKey:@"signIdentity" option:@"-s" description:@"sign identity of provisioning profile" required:YES];
        [ArgumentParser addArgumentWithKey:@"ppPath" option:@"-p" description:@"path of provisioning profile" required:YES];
        [ArgumentParser addArgumentWithKey:@"outputPath" option:@"-o" description:@"path of ipa resigned" required:NO];
        [ArgumentParser parse];
        
        ipaPath = [ArgumentParser valueForKey:@"ipaPath"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:ipaPath]) {
            NSLog(@"ipa not exist in %@", ipaPath);
            return -1;
        }
        
        ppPath = [ArgumentParser valueForKey:@"ppPath"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:ppPath]) {
            NSLog(@"provisioning profile not exist in %@", ppPath);
            return -1;
        }
        
        //unzip ipa
        
        ipaInDir = [ipaPath stringByDeletingLastPathComponent];
        BOOL isDir;
        if ([[NSFileManager defaultManager] fileExistsAtPath:[ipaInDir stringByAppendingPathComponent:@"Payload"] isDirectory:&isDir]) {
            if (isDir) {
                NSLog(@"there is already a Payload directory in %@, please remove the Payload directory first", ipaInDir);
                return -1;
            }
        }
        
        NSTask *unzipTask = [[NSTask alloc] init];
        unzipTask.launchPath = @"/usr/bin/unzip";
        unzipTask.arguments = @[@"-q", @"-o", ipaPath, @"-d", ipaInDir];
        [unzipTask launch];
        [unzipTask waitUntilExit];
        if (unzipTask.terminationStatus != 0) {
            NSLog(@"ipa unzip failed with status:%d", unzipTask.terminationStatus);
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
        
        //dump entitlement plist
        
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/security";
        task.arguments = @[@"cms", @"-D", @"-i", ppPath];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        NSFileHandle *handle = [pipe fileHandleForReading];
        [task launch];
        [task waitUntilExit];
        if (task.terminationStatus != 0) {
            NSLog(@"security cms failed with status:%d", task.terminationStatus);
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
        
        //add pp
        
        NSString *embeddedPPPath = [appBundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:embeddedPPPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:embeddedPPPath error:nil];
        }
        [[NSFileManager defaultManager] copyItemAtPath:ppPath toPath:embeddedPPPath error:&error];
        if (error) {
            NSLog(@"copy pp file error:%@", error);
            return -1;
        }
        
        //resign mach-o
        
        signIdentity = [ArgumentParser valueForKey:@"signIdentity"];
        NSArray *subpaths = [[NSFileManager defaultManager] subpathsAtPath:appBundlePath];
        for (NSString *subpath in subpaths) {
            NSString *path = [appBundlePath stringByAppendingPathComponent:subpath];
            BOOL isDir;
            [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
            if (!isDir) {
                NSData *data = [NSData dataWithContentsOfFile:path];
                uint32_t header;
                [data getBytes:&header length:sizeof(uint32_t)];

                if (header == MH_MAGIC_64 || header == MH_CIGAM_64 || header == FAT_MAGIC_64 || header == FAT_MAGIC || header == FAT_CIGAM_64 || header == FAT_CIGAM) {
                    NSTask *task = [[NSTask alloc] init];
                    task.launchPath = @"/usr/bin/codesign";
                    task.arguments = @[@"-f", @"-s", signIdentity, path];
                    [task launch];
                    [task waitUntilExit];
                    if (task.terminationStatus != 0) {
                        NSLog(@"code sign failed with status:%d", task.terminationStatus);
                        return -1;
                    }
                }
            }
        }

        //delete _CodeSignature dir

        [[NSFileManager defaultManager] removeItemAtPath:[appBundlePath stringByAppendingPathComponent:@"_CodeSignature"] error:nil];
        
        //code sign app
        
        NSTask *codeSignTask = [[NSTask alloc] init];
        codeSignTask.launchPath = @"/usr/bin/codesign";
        codeSignTask.arguments = @[@"-f", @"-s", signIdentity, @"--entitlements", entitlementsPath, appBundlePath];
        [codeSignTask launchAndReturnError:&error];
        [codeSignTask waitUntilExit];
        if (codeSignTask.terminationStatus != 0) {
            NSLog(@"code sign app failed with status:%d", codeSignTask.terminationStatus);
            return -1;
        }
        
        //change current working dir
        
        [[NSFileManager defaultManager] changeCurrentDirectoryPath:ipaInDir];
        
        //create resigned ipa
        
        NSString *targetIpaPath;
        outputPath = [ArgumentParser valueForKey:@"outputPath"];
        if (outputPath) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:outputPath withIntermediateDirectories:YES attributes:nil error:nil];
            }
            targetIpaPath = [outputPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-resigned.ipa", [[ipaPath stringByDeletingPathExtension] lastPathComponent]]];
        } else {
            targetIpaPath = [ipaInDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-resigned.ipa", [[ipaPath stringByDeletingPathExtension] lastPathComponent]]];
        }
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:targetIpaPath isDirectory:&isDir]) {
            if (!isDir) {
                [[NSFileManager defaultManager] removeItemAtPath:targetIpaPath error:nil];
            }
        }
        
        NSTask *createIpaTask = [[NSTask alloc] init];
        createIpaTask.launchPath = @"/usr/bin/zip";
        createIpaTask.arguments = @[@"-q", @"-r", targetIpaPath, @"Payload"];
        [createIpaTask launch];
        [createIpaTask waitUntilExit];
        if (createIpaTask.terminationStatus != 0) {
            NSLog(@"code sign app failed with status:%d", createIpaTask.terminationStatus);
            return -1;
        }
        
        NSLog(@"output path:%@", targetIpaPath);
        NSLog(@"resign complete!");
    }
    return 0;
}



