#import <XCTest/XCTest.h>
#import "../../Preferences/LBTendiesValidator.h"
#import <zlib.h>

static void Append16(NSMutableData *d,uint16_t v){uint8_t b[2]={(uint8_t)v,(uint8_t)(v>>8)};[d appendBytes:b length:2];}
static void Append32(NSMutableData *d,uint32_t v){uint8_t b[4]={(uint8_t)v,(uint8_t)(v>>8),(uint8_t)(v>>16),(uint8_t)(v>>24)};[d appendBytes:b length:4];}
static NSData *StoredZip(NSArray<NSDictionary *> *items, BOOL corruptCRC) {
    NSMutableData *out=[NSMutableData data]; NSMutableArray *records=[NSMutableArray array];
    for(NSDictionary *item in items){
        NSData *name=[item[@"name"] dataUsingEncoding:NSUTF8StringEncoding],*payload=item[@"data"];
        uLong crc=crc32(0L,Z_NULL,0);crc=crc32(crc,payload.bytes,(uInt)payload.length);if(corruptCRC)crc^=1;
        NSUInteger offset=out.length;
        Append32(out,0x04034b50);Append16(out,20);Append16(out,0);Append16(out,0);Append16(out,0);Append16(out,0);
        Append32(out,(uint32_t)crc);Append32(out,(uint32_t)payload.length);Append32(out,(uint32_t)payload.length);
        Append16(out,(uint16_t)name.length);Append16(out,0);[out appendData:name];[out appendData:payload];
        [records addObject:@{@"name":name,@"crc":@((uint32_t)crc),@"size":@(payload.length),@"offset":@(offset)}];
    }
    NSUInteger centralOffset=out.length;
    for(NSDictionary *r in records){
        NSData *name=r[@"name"];Append32(out,0x02014b50);Append16(out,20);Append16(out,20);Append16(out,0);Append16(out,0);Append16(out,0);Append16(out,0);
        Append32(out,[r[@"crc"] unsignedIntValue]);Append32(out,[r[@"size"] unsignedIntValue]);Append32(out,[r[@"size"] unsignedIntValue]);
        Append16(out,(uint16_t)name.length);Append16(out,0);Append16(out,0);Append16(out,0);Append16(out,0);Append32(out,0100644u<<16);Append32(out,[r[@"offset"] unsignedIntValue]);[out appendData:name];
    }
    NSUInteger centralSize=out.length-centralOffset;
    Append32(out,0x06054b50);Append16(out,0);Append16(out,0);Append16(out,(uint16_t)records.count);Append16(out,(uint16_t)records.count);Append32(out,(uint32_t)centralSize);Append32(out,(uint32_t)centralOffset);Append16(out,0);
    return out;
}
@interface LBTendiesValidatorTests : XCTestCase @end
@implementation LBTendiesValidatorTests
- (NSString *)writeZip:(NSData *)zip { NSString *p=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".tendies"]];[zip writeToFile:p atomically:YES];return p; }
- (void)testRejectsNonZip { NSString *p=[self writeZip:[@"not ZIP" dataUsingEncoding:NSUTF8StringEncoding]];NSError *e=nil;NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];XCTAssertNotNil(e);XCTAssertNotEqualObjects(r[@"status"],@"valid");[[NSFileManager defaultManager]removeItemAtPath:p error:nil]; }
- (void)testRejectsMissingFile { NSError *e=nil;NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:@"/missing/file.tendies" extractToPath:nil error:&e];XCTAssertNotNil(e);XCTAssertEqualObjects(r[@"status"],@"invalid"); }
- (void)testRejectsPathTraversal { NSString *p=[self writeZip:StoredZip(@[@{@"name":@"descriptors/../evil",@"data":[NSData data]}],NO)];NSError *e=nil;NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];XCTAssertNotNil(e);XCTAssertEqualObjects(r[@"status"],@"invalid");[[NSFileManager defaultManager]removeItemAtPath:p error:nil]; }
- (void)testRejectsCorruptCRC { NSString *p=[self writeZip:StoredZip(@[@{@"name":@"descriptors/a/file.bin",@"data":[@"abc" dataUsingEncoding:NSUTF8StringEncoding]}],YES)];NSError *e=nil;NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];XCTAssertNotNil(e);XCTAssertEqualObjects(r[@"status"],@"invalid");[[NSFileManager defaultManager]removeItemAtPath:p error:nil]; }
- (void)testAcceptsMinimalDescriptorFixtureAndExtracts { NSDictionary *wp=@{@"identifier":@1,@"name":@"Synthetic",@"assets":@{}};NSData *plist=[NSPropertyListSerialization dataWithPropertyList:wp format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];NSString *p=[self writeZip:StoredZip(@[@{@"name":@"descriptors/fixture/Wallpaper.plist",@"data":plist}],NO)];NSString *out=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError *e=nil;NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:out error:&e];XCTAssertNil(e);XCTAssertEqualObjects(r[@"status"],@"extracted");XCTAssertTrue([[NSFileManager defaultManager]fileExistsAtPath:[out stringByAppendingPathComponent:@"descriptors/fixture/Wallpaper.plist"]]);XCTAssertTrue([[NSFileManager defaultManager]fileExistsAtPath:p]);[[NSFileManager defaultManager]removeItemAtPath:p error:nil];[[NSFileManager defaultManager]removeItemAtPath:out error:nil]; }

- (void)testRejectsTruncatedArchive {
    NSData *zip=StoredZip(@[@{@"name":@"descriptors/a.bin",@"data":[@"abc" dataUsingEncoding:NSUTF8StringEncoding]}],NO);
    NSData *truncated=[zip subdataWithRange:NSMakeRange(0,zip.length-8)];
    NSString *p=[self writeZip:truncated]; NSError *e=nil;
    NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];
    XCTAssertNotNil(e); XCTAssertEqualObjects(r[@"status"],@"invalid");
    [[NSFileManager defaultManager]removeItemAtPath:p error:nil];
}
- (void)testRejectsMissingEOCD {
    NSString *p=[self writeZip:[@"PK\x03\x04" dataUsingEncoding:NSISOLatin1StringEncoding]];
    NSError *e=nil; NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];
    XCTAssertNotNil(e); XCTAssertEqualObjects(r[@"status"],@"invalid");
    [[NSFileManager defaultManager]removeItemAtPath:p error:nil];
}
- (void)testRejectsAbsolutePath {
    NSString *p=[self writeZip:StoredZip(@[@{@"name":@"/tmp/escape",@"data":[NSData data]}],NO)];
    NSError *e=nil; NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];
    XCTAssertNotNil(e); XCTAssertEqualObjects(r[@"status"],@"invalid");
    [[NSFileManager defaultManager]removeItemAtPath:p error:nil];
}
- (void)testRejectsBackslashPath {
    NSString *p=[self writeZip:StoredZip(@[@{@"name":@"descriptors\\escape",@"data":[NSData data]}],NO)];
    NSError *e=nil; NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];
    XCTAssertNotNil(e); XCTAssertEqualObjects(r[@"status"],@"invalid");
    [[NSFileManager defaultManager]removeItemAtPath:p error:nil];
}
- (void)testRejectsDuplicateNames {
    NSData *payload=[NSData data];
    NSString *p=[self writeZip:StoredZip(@[@{@"name":@"descriptors/a",@"data":payload},@{@"name":@"descriptors/a",@"data":payload}],NO)];
    NSError *e=nil; NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];
    XCTAssertNotNil(e); XCTAssertEqualObjects(r[@"status"],@"invalid");
    [[NSFileManager defaultManager]removeItemAtPath:p error:nil];
}
- (void)testRejectsEOCDCommentLengthMismatch {
    NSMutableData *zip=[StoredZip(@[@{@"name":@"descriptors/a",@"data":[NSData data]}],NO) mutableCopy];
    uint8_t bad[2]={5,0}; [zip replaceBytesInRange:NSMakeRange(zip.length-2,2) withBytes:bad];
    NSString *p=[self writeZip:zip]; NSError *e=nil;
    NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];
    XCTAssertNotNil(e); XCTAssertEqualObjects(r[@"status"],@"invalid");
    [[NSFileManager defaultManager]removeItemAtPath:p error:nil];
}
- (void)testRejectsEncryptedEntry {
    NSMutableData *zip=[StoredZip(@[@{@"name":@"descriptors/a",@"data":[NSData data]}],NO) mutableCopy];
    uint8_t encrypted[2]={1,0}; [zip replaceBytesInRange:NSMakeRange(6,2) withBytes:encrypted];
    const uint8_t *bytes=zip.bytes; NSUInteger cd=NSNotFound;
    for(NSUInteger i=0;i+4<=zip.length;i++){uint32_t sig=(uint32_t)bytes[i]|((uint32_t)bytes[i+1]<<8)|((uint32_t)bytes[i+2]<<16)|((uint32_t)bytes[i+3]<<24);if(sig==0x02014b50){cd=i;break;}}
    XCTAssertNotEqual(cd,NSNotFound); [zip replaceBytesInRange:NSMakeRange(cd+8,2) withBytes:encrypted];
    NSString *p=[self writeZip:zip]; NSError *e=nil;
    NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:nil error:&e];
    XCTAssertNotNil(e); XCTAssertEqualObjects(r[@"status"],@"unsupported");
    [[NSFileManager defaultManager]removeItemAtPath:p error:nil];
}
- (void)testRejectsExistingExtractionDestination {
    NSDictionary *wp=@{@"identifier":@1,@"name":@"Synthetic",@"assets":@{}};
    NSData *plist=[NSPropertyListSerialization dataWithPropertyList:wp format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    NSString *p=[self writeZip:StoredZip(@[@{@"name":@"descriptors/fixture/Wallpaper.plist",@"data":plist}],NO)];
    NSString *out=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [[NSFileManager defaultManager]createDirectoryAtPath:out withIntermediateDirectories:NO attributes:nil error:nil];
    NSError *e=nil; NSDictionary *r=[LBTendiesValidator validateArchiveAtPath:p extractToPath:out error:&e];
    XCTAssertNotNil(e); XCTAssertEqualObjects(r[@"status"],@"invalid");
    [[NSFileManager defaultManager]removeItemAtPath:p error:nil]; [[NSFileManager defaultManager]removeItemAtPath:out error:nil];
}
@end
