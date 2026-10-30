#import <Foundation/Foundation.h>
#import <notify.h>
#import <sys/stat.h>
#import <unistd.h>
#import <pwd.h>
#import <stdio.h>
#import "../Shared/LBPaths.h"

static BOOL LBValidUUID(NSString *value) {
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value ?: @""];
    return uuid != nil && [uuid.UUIDString caseInsensitiveCompare:value] == NSOrderedSame;
}

static void LBWriteCompletion(NSString *requestID, NSDictionary *payload) {
    if (!LBValidUUID(requestID)) return;
    NSString *destination = [LBCompletedPath() stringByAppendingPathComponent:[requestID stringByAppendingPathExtension:@"plist"]];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (data.length == 0) return;
    NSString *temporary = [destination stringByAppendingFormat:@".%@.tmp", NSUUID.UUID.UUIDString];
    if (![data writeToFile:temporary options:NSDataWritingAtomic error:nil]) return;
    chmod(temporary.fileSystemRepresentation, 0600);
    rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation);
    struct passwd *mobile = getpwnam("mobile");
    if (mobile) chown(destination.fileSystemRepresentation, mobile->pw_uid, mobile->pw_gid);
    chmod(destination.fileSystemRepresentation, 0600);
}

static void LBProcessRequests(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *directoryError = nil;
    if (!LBEnsureDaemonDirectories(&directoryError)) return;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:LBRequestsPath() error:nil];
    for (NSString *entry in entries) {
        if (![entry.pathExtension.lowercaseString isEqualToString:@"plist"]) continue;
        NSString *requestID = entry.stringByDeletingPathExtension;
        if (!LBValidUUID(requestID)) continue;
        NSString *path = [LBRequestsPath() stringByAppendingPathComponent:entry];
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode) || S_ISLNK(st.st_mode)) continue;
        if (st.st_size <= 0 || st.st_size > 1024 * 1024) { [fm removeItemAtPath:path error:nil]; continue; }
        // Requests are untrusted data from the mobile user. Never accept a filesystem destination path.
        NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:path];
        NSString *action = [request[@"action"] isKindOfClass:NSString.class] ? request[@"action"] : @"";
        NSDictionary *result = @{
            @"requestID": requestID,
            @"finished": @YES,
            @"success": @NO,
            @"errorCode": @"native_integration_disabled",
            @"error": @"Native PosterBoard installation/removal is intentionally disabled in this baseline until the descriptor generator is validated on the target device.",
            @"action": action
        };
        LBWriteCompletion(requestID, result);
        [fm removeItemAtPath:path error:nil];
    }
}

static void LBNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    @autoreleasepool { LBProcessRequests(); }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        (void)argc; (void)argv;
        NSError *error = nil;
        if (!LBEnsureDaemonDirectories(&error)) {
            NSLog(@"[LumenBoard] Cannot initialize support directories: %@", error);
            return 1;
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LBNotificationCallback,
                                        (__bridge CFStringRef)LBDarwinReloadNotification(), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        LBProcessRequests();
        [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(__unused NSTimer *timer) { @autoreleasepool { LBProcessRequests(); } }];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
