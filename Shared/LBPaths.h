#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *LBSupportRoot(void);
FOUNDATION_EXPORT NSString *LBLibraryPath(void);
FOUNDATION_EXPORT NSString *LBRequestsPath(void);
FOUNDATION_EXPORT NSString *LBCompletedPath(void);
FOUNDATION_EXPORT NSString *LBDarwinReloadNotification(void);
FOUNDATION_EXPORT BOOL LBEnsureUserDirectories(NSError **error);
FOUNDATION_EXPORT BOOL LBEnsureDaemonDirectories(NSError **error);

NS_ASSUME_NONNULL_END
