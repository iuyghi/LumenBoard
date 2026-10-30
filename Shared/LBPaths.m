#import "LBPaths.h"
#import <sys/stat.h>
#import <unistd.h>
#import <pwd.h>
#import <errno.h>

NSString *LBSupportRoot(void) {
    return @"/var/mobile/Library/Application Support/LumenBoard";
}
NSString *LBLibraryPath(void) { return [LBSupportRoot() stringByAppendingPathComponent:@"Library"]; }
NSString *LBRequestsPath(void) { return [LBSupportRoot() stringByAppendingPathComponent:@"Requests"]; }
NSString *LBCompletedPath(void) { return [LBSupportRoot() stringByAppendingPathComponent:@"Completed"]; }
NSString *LBDarwinReloadNotification(void) { return @"com.iuyghi.lumenboard.reload"; }

static BOOL LBMakeUserDirectory(NSString *path, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDirectory]) {
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode)) {
            if (error) *error = [NSError errorWithDomain:@"LumenBoard" code:101 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Refusing non-directory path: %@", path]}];
            return NO;
        }
    } else {
        if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:error]) return NO;
    }
    if (geteuid() == 0) {
        struct passwd *mobile = getpwnam("mobile");
        if (!mobile) {
            if (error) *error = [NSError errorWithDomain:@"LumenBoard" code:102 userInfo:@{NSLocalizedDescriptionKey:@"The mobile account could not be resolved."}];
            return NO;
        }
        if (chown(path.fileSystemRepresentation, mobile->pw_uid, mobile->pw_gid) != 0) {
            if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            return NO;
        }
    }
    if (chmod(path.fileSystemRepresentation, 0700) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    return YES;
}

BOOL LBEnsureUserDirectories(NSError **error) {
    // The unprivileged pane has no reason to create IPC endpoints.
    return LBMakeUserDirectory(LBSupportRoot(), error) &&
           LBMakeUserDirectory(LBLibraryPath(), error);
}

BOOL LBEnsureDaemonDirectories(NSError **error) {
    return LBEnsureUserDirectories(error) &&
           LBMakeUserDirectory(LBRequestsPath(), error) &&
           LBMakeUserDirectory(LBCompletedPath(), error);
}
