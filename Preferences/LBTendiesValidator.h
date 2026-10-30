#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface LBTendiesValidator : NSObject
+ (NSDictionary *)validateArchiveAtPath:(NSString *)archivePath extractToPath:(nullable NSString *)destinationPath error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
