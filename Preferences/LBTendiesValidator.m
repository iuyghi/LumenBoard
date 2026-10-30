#import "LBTendiesValidator.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <zlib.h>

static NSString * const LBTDomain = @"com.iuyghi.LumenBoard.Tendies";
static const uint64_t LBTMaxArchive = 300ULL * 1024ULL * 1024ULL;
static const uint64_t LBTMaxTotal = 128ULL * 1024ULL * 1024ULL;
static const uint64_t LBTMaxFile = 64ULL * 1024ULL * 1024ULL;
static const NSUInteger LBTMaxEntries = 2048, LBTMaxPlist = 8 * 1024 * 1024;
static NSError *LBTMakeError(NSInteger code, NSString *message) { return [NSError errorWithDomain:LBTDomain code:code userInfo:@{NSLocalizedDescriptionKey:message ?: @"Validation failed"}]; }
static uint16_t LBTU16(const uint8_t *p) { return (uint16_t)(p[0] | ((uint16_t)p[1] << 8)); }
static uint32_t LBTU32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static BOOL LBTRange(NSUInteger p, NSUInteger n, NSUInteger total) { return p <= total && n <= total-p; }
static NSString *LBTHash(NSData *d) { unsigned char h[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes,(CC_LONG)d.length,h); NSMutableString *s=[NSMutableString string]; for(NSUInteger i=0;i<sizeof(h);i++)[s appendFormat:@"%02x",h[i]]; return s; }

static BOOL LBTNormalizePath(NSString *raw, BOOL dir, NSString **key, NSError **error) {
    if (!raw.length || [raw containsString:@"\\"] || [raw rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) { if(error)*error=LBTMakeError(10,@"Invalid path or separator"); return NO; }
    if ([raw hasPrefix:@"/"] || [raw hasPrefix:@"~"] || (raw.length>1 && [raw characterAtIndex:1]==':')) { if(error)*error=LBTMakeError(11,@"Absolute path rejected"); return NO; }
    NSString *name=(dir&&[raw hasSuffix:@"/"])?[raw substringToIndex:raw.length-1]:raw;
    NSArray *parts=[name componentsSeparatedByString:@"/"];
    for(NSString *part in parts) if(!part.length||[part isEqualToString:@"."]||[part isEqualToString:@".."]||[part containsString:@":"]) { if(error)*error=LBTMakeError(12,@"Path traversal or ambiguous path rejected"); return NO; }
    if(key)*key=[[parts componentsJoinedByString:@"/"] precomposedStringWithCanonicalMapping].lowercaseString;
    return YES;
}
static NSData *LBTDecode(NSData *input, NSUInteger expected, uint16_t method, NSError **error) {
    if(expected>LBTMaxFile){if(error)*error=LBTMakeError(20,@"Member exceeds size limit");return nil;}
    if(method==0){if(input.length!=expected){if(error)*error=LBTMakeError(21,@"Stored member size mismatch");return nil;}return input;}
    if(method!=8){if(error)*error=LBTMakeError(22,@"Unsupported compression method");return nil;}
    NSMutableData *out=[NSMutableData dataWithLength:MAX((NSUInteger)1,expected)];
    z_stream z={0}; z.next_in=(Bytef *)input.bytes; z.avail_in=(uInt)input.length; z.next_out=out.mutableBytes; z.avail_out=(uInt)out.length;
    if(inflateInit2(&z,-MAX_WBITS)!=Z_OK){if(error)*error=LBTMakeError(23,@"Cannot initialize DEFLATE");return nil;}
    int rc=inflate(&z,Z_FINISH); NSUInteger produced=z.total_out; uInt remaining=z.avail_in; inflateEnd(&z);
    if(rc!=Z_STREAM_END||produced!=expected||remaining!=0){if(error)*error=LBTMakeError(24,@"Invalid or truncated DEFLATE stream");return nil;}
    out.length=produced; return out;
}
@interface LBTEntry:NSObject
@property(nonatomic,copy) NSString *name,*key;
@property(nonatomic) uint16_t flags,method;
@property(nonatomic) uint32_t crc,compressed,uncompressed,localOffset,external;
@property(nonatomic) BOOL directory;
@end
@implementation LBTEntry @end

@implementation LBTendiesValidator
+ (NSDictionary *)validateArchiveAtPath:(NSString *)path extractToPath:(NSString *)destination error:(NSError **)error {
    struct stat st;
    if(lstat(path.fileSystemRepresentation,&st)!=0||!S_ISREG(st.st_mode)||S_ISLNK(st.st_mode)||st.st_size<=0||(uint64_t)st.st_size>LBTMaxArchive){if(error)*error=LBTMakeError(1,@"Archive must be a regular non-empty file no larger than 300 MiB");return @{@"status":@"invalid",@"errors":@[@"Unsafe or oversized archive"]};}
    NSError *readError=nil; NSData *zip=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&readError];
    if(!zip){if(error)*error=readError;return @{@"status":@"incomplete",@"errors":@[readError.localizedDescription?:@"Read failed"]};}
    const uint8_t *b=zip.bytes; NSUInteger n=zip.length, eocd=NSNotFound, floor=n>65557?n-65557:0;
    if(n>=22){for(NSUInteger p=n-22;;p--){if(LBTRange(p,4,n)&&LBTU32(b+p)==0x06054b50){eocd=p;break;}if(p==floor)break;}}
    if(eocd==NSNotFound||!LBTRange(eocd,22,n)){if(error)*error=LBTMakeError(2,@"ZIP end record missing");return @{@"status":@"invalid",@"errors":@[@"Malformed ZIP"]};}
    uint16_t disk=LBTU16(b+eocd+4),cdDisk=LBTU16(b+eocd+6),onDisk=LBTU16(b+eocd+8),count=LBTU16(b+eocd+10),comment=LBTU16(b+eocd+20);
    uint32_t cdSize=LBTU32(b+eocd+12),cdOffset=LBTU32(b+eocd+16);
    if(disk||cdDisk||onDisk!=count){if(error)*error=LBTMakeError(3,@"Multi-disk ZIP unsupported");return @{@"status":@"unsupported",@"errors":@[@"Multi-disk ZIP"]};}
    if(count==0xffff||cdSize==0xffffffff||cdOffset==0xffffffff){if(error)*error=LBTMakeError(4,@"ZIP64 unsupported");return @{@"status":@"unsupported",@"errors":@[@"ZIP64"]};}
    if(!count||count>LBTMaxEntries||!LBTRange(eocd,22+comment,n)||(uint64_t)cdOffset+cdSize>eocd){if(error)*error=LBTMakeError(5,@"Invalid central directory");return @{@"status":@"invalid",@"errors":@[@"Invalid central directory"]};}
    NSMutableArray<LBTEntry *> *entries=[NSMutableArray array]; NSMutableSet *keys=[NSMutableSet set]; uint64_t total=0; NSUInteger cursor=cdOffset; BOOL descriptor=NO,container=NO;
    for(NSUInteger i=0;i<count;i++){
        if(!LBTRange(cursor,46,n)||LBTU32(b+cursor)!=0x02014b50){if(error)*error=LBTMakeError(6,@"Malformed central directory record");return @{@"status":@"invalid",@"errors":@[@"Malformed central directory"]};}
        const uint8_t *h=b+cursor; uint16_t flags=LBTU16(h+8),method=LBTU16(h+10),nl=LBTU16(h+28),xl=LBTU16(h+30),cl=LBTU16(h+32),diskStart=LBTU16(h+34);
        uint32_t crc=LBTU32(h+16),cs=LBTU32(h+20),us=LBTU32(h+24),ext=LBTU32(h+38),local=LBTU32(h+42); NSUInteger record=46+(NSUInteger)nl+xl+cl;
        if(!LBTRange(cursor,record,n)){if(error)*error=LBTMakeError(7,@"Truncated central directory");return @{@"status":@"invalid",@"errors":@[@"Truncated central directory"]};}
        if(diskStart==0xffff||cs==0xffffffff||us==0xffffffff||local==0xffffffff){if(error)*error=LBTMakeError(8,@"ZIP64 entry unsupported");return @{@"status":@"unsupported",@"errors":@[@"ZIP64 entry"]};}
        NSString *name=[[NSString alloc]initWithBytes:h+46 length:nl encoding:NSUTF8StringEncoding]; if(!name){if(error)*error=LBTMakeError(9,@"Invalid UTF-8 entry name");return @{@"status":@"invalid",@"errors":@[@"Invalid filename encoding"]};}
        BOOL dir=[name hasSuffix:@"/"]; NSString *key=nil; if(!LBTNormalizePath(name,dir,&key,error))return @{@"status":@"invalid",@"errors":@[@"Unsafe archive path"]};
        if([keys containsObject:key]){if(error)*error=LBTMakeError(13,@"Duplicate, Unicode or case-folded path collision");return @{@"status":@"invalid",@"errors":@[@"Duplicate path"]};}
        for(NSString *prior in keys) if(([prior hasPrefix:[key stringByAppendingString:@"/"]]&&!dir)||([key hasPrefix:[prior stringByAppendingString:@"/"]] )){if(error)*error=LBTMakeError(14,@"File/directory path collision");return @{@"status":@"invalid",@"errors":@[@"Path collision"]};}
        [keys addObject:key]; uint32_t mode=(ext>>16)&0xffff,kind=mode&0170000;
        if(kind==0120000||(kind&&kind!=0100000&&kind!=0040000)){if(error)*error=LBTMakeError(15,@"Symlink or special entry rejected");return @{@"status":@"invalid",@"errors":@[@"Symlink or special entry"]};}
        if(flags&1){if(error)*error=LBTMakeError(16,@"Encrypted entries unsupported");return @{@"status":@"unsupported",@"errors":@[@"Encrypted archive"]};}
        if(method!=0&&method!=8){if(error)*error=LBTMakeError(17,@"Unsupported compression method");return @{@"status":@"unsupported",@"errors":@[@"Unsupported compression"]};}
        if(us>LBTMaxFile||total+us>LBTMaxTotal||(us>0&&(cs==0||(uint64_t)us>(uint64_t)cs*500))){if(error)*error=LBTMakeError(18,@"ZIP bomb/resource bound exceeded");return @{@"status":@"invalid",@"errors":@[@"Decompression limit exceeded"]};}
        total+=us; NSArray *components=[name.lowercaseString componentsSeparatedByString:@"/"]; if([components containsObject:@"container"])container=YES;
        if([components containsObject:@"descriptor"]||[components containsObject:@"descriptors"])descriptor=YES;
        LBTEntry *e=[LBTEntry new];e.name=name;e.key=key;e.flags=flags;e.method=method;e.crc=crc;e.compressed=cs;e.uncompressed=us;e.localOffset=local;e.external=ext;e.directory=dir;[entries addObject:e];cursor+=record;
    }
    if(cursor!=cdOffset+cdSize){if(error)*error=LBTMakeError(19,@"Central directory size mismatch");return @{@"status":@"invalid",@"errors":@[@"Central directory mismatch"]};}
    if(container){if(error)*error=LBTMakeError(25,@"Whole-container archives are unsupported");return @{@"status":@"unsupported",@"errors":@[@"Container-format archive"]};}
    if(!descriptor){if(error)*error=LBTMakeError(26,@"Descriptor directory not found");return @{@"status":@"incomplete",@"errors":@[@"Descriptor directory missing"]};}
    NSMutableDictionary<NSString *,NSData *> *contents=[NSMutableDictionary dictionary]; NSMutableArray *plists=[NSMutableArray array],*wallpapers=[NSMutableArray array];
    for(LBTEntry *e in entries){
        if(e.directory)continue; NSUInteger p=e.localOffset;
        if(!LBTRange(p,30,n)||LBTU32(b+p)!=0x04034b50){if(error)*error=LBTMakeError(27,@"Invalid local file header");return @{@"status":@"invalid",@"errors":@[@"Invalid local header"]};}
        uint16_t localFlags=LBTU16(b+p+6),localMethod=LBTU16(b+p+8),ln=LBTU16(b+p+26),le=LBTU16(b+p+28);
        NSUInteger data=p+30+(NSUInteger)ln+le; if(localFlags!=e.flags||localMethod!=e.method||!LBTRange(data,e.compressed,n)){if(error)*error=LBTMakeError(28,@"Local and central ZIP headers disagree");return @{@"status":@"invalid",@"errors":@[@"Header mismatch or truncated member"]};}
        NSString *localName=[[NSString alloc]initWithBytes:b+p+30 length:ln encoding:NSUTF8StringEncoding]; if(![localName isEqualToString:e.name]){if(error)*error=LBTMakeError(29,@"Local and central entry names disagree");return @{@"status":@"invalid",@"errors":@[@"Filename mismatch"]};}
        NSData *packed=[zip subdataWithRange:NSMakeRange(data,e.compressed)]; NSError *decodeError=nil; NSData *plain=LBTDecode(packed,e.uncompressed,e.method,&decodeError);
        if(!plain){if(error)*error=decodeError;return @{@"status":@"invalid",@"errors":@[decodeError.localizedDescription]};}
        uLong crcValue=crc32(0L,Z_NULL,0);crcValue=crc32(crcValue,plain.bytes,(uInt)plain.length);
        if((uint32_t)crcValue!=e.crc){if(error)*error=LBTMakeError(30,@"CRC mismatch");return @{@"status":@"invalid",@"errors":@[@"CRC mismatch"]};}
        if([e.name.pathExtension.lowercaseString isEqualToString:@"plist"]){
            if(plain.length>LBTMaxPlist){if(error)*error=LBTMakeError(31,@"Plist too large");return @{@"status":@"invalid",@"errors":@[@"Oversized plist"]};}
            NSError *pe=nil; id object=[NSPropertyListSerialization propertyListWithData:plain options:NSPropertyListImmutable format:nil error:&pe];
            if(!object){if(error)*error=LBTMakeError(32,[NSString stringWithFormat:@"Malformed plist %@: %@",e.name,pe.localizedDescription]);return @{@"status":@"invalid",@"errors":@[@"Malformed plist"]};}
            [plists addObject:e.name];
            if([e.name.lastPathComponent.lowercaseString isEqualToString:@"wallpaper.plist"]){
                if(![object isKindOfClass:NSDictionary.class]||![object[@"identifier"] isKindOfClass:NSNumber.class]||![object[@"name"] isKindOfClass:NSString.class]||![object[@"assets"] isKindOfClass:NSDictionary.class]){if(error)*error=LBTMakeError(33,@"Wallpaper.plist missing identifier/name/assets");return @{@"status":@"incomplete",@"errors":@[@"Incomplete Wallpaper.plist"]};}
                [wallpapers addObject:e.name];
            }
        }
        contents[e.name]=plain;
    }
    if(!wallpapers.count){if(error)*error=LBTMakeError(34,@"No structurally complete Wallpaper.plist");return @{@"status":@"incomplete",@"errors":@[@"Wallpaper.plist missing"]};}
    NSMutableDictionary *report=[@{@"status":@"valid",@"format":@"descriptor",@"archiveBytes":@(zip.length),@"entryCount":@(entries.count),@"uncompressedBytes":@(total),@"sha256":LBTHash(zip),@"plistFiles":plists,@"wallpaperPlists":wallpapers,@"compatibility":@"not-tested",@"validatorVersion":@"1.0.0"} mutableCopy];
    if(destination.length){
        struct stat ds; if(lstat(destination.fileSystemRepresentation,&ds)==0){if(error)*error=LBTMakeError(35,@"Extraction destination already exists");return @{@"status":@"invalid",@"errors":@[@"Destination exists"]};}
        if(mkdir(destination.fileSystemRepresentation,0700)!=0){if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];return @{@"status":@"incomplete",@"errors":@[@"Cannot create extraction root"]};}
        BOOL success=YES; NSError *extractError=nil;
        for(LBTEntry *e in entries){
            NSString *target=[destination stringByAppendingPathComponent:e.name];
            if(e.directory){if(![[NSFileManager defaultManager] createDirectoryAtPath:target withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&extractError]){success=NO;break;}continue;}
            NSString *parent=target.stringByDeletingLastPathComponent;
            if(![[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&extractError]){success=NO;break;}
            int fd=open(target.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL
#ifdef O_NOFOLLOW
                |O_NOFOLLOW
#endif
                ,0600);
            if(fd<0){extractError=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];success=NO;break;}
            NSData *data=contents[e.name]; ssize_t wrote=write(fd,data.bytes,data.length); if(wrote!=(ssize_t)data.length||fsync(fd)!=0)success=NO; close(fd);
            if(!success){extractError=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];break;}
        }
        if(!success){[[NSFileManager defaultManager] removeItemAtPath:destination error:nil];if(error)*error=extractError;return @{@"status":@"incomplete",@"errors":@[extractError.localizedDescription?:@"Extraction failed"]};}
        report[@"status"]=@"extracted";report[@"extractedPath"]=destination;
    }
    return report;
}
@end
