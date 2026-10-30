#import <XCTest/XCTest.h>
#import "../../Preferences/LBTendiesValidator.h"

@interface LBTendiesValidatorTests : XCTestCase
@end
@implementation LBTendiesValidatorTests
- (NSString *)temporaryArchive {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".tendies"]];
}
- (void)testRejectsNonZipInput {
    NSString *path=[self temporaryArchive];
    [@"not a ZIP archive" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSError *error=nil;
    NSDictionary *report=[LBTendiesValidator validateArchiveAtPath:path extractToPath:nil error:&error];
    XCTAssertNotNil(error);
    XCTAssertNotEqualObjects(report[@"status"],@"valid");
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}
- (void)testRejectsMissingFile {
    NSError *error=nil;
    NSDictionary *report=[LBTendiesValidator validateArchiveAtPath:[self temporaryArchive] extractToPath:nil error:&error];
    XCTAssertNotNil(error);
    XCTAssertEqualObjects(report[@"status"],@"invalid");
}
@end
