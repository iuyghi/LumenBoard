#import "LBRootListController.h"
#import "../Shared/LBPaths.h"
#import "LBTendiesValidator.h"
#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString * const LBManifestName = @"manifest.plist";
static const unsigned long long LBMaxImportBytes = 300ULL * 1024ULL * 1024ULL;

static NSString *LBSHA256ForFile(NSString *path) {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    [stream open];
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    uint8_t buffer[64 * 1024]; NSInteger count = 0;
    while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0) CC_SHA256_Update(&context, buffer, (CC_LONG)count);
    NSError *streamError = stream.streamError; [stream close];
    if (count < 0 || streamError) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}


static NSDictionary *LBReadManagedManifest(NSString *entry) {
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:entry ?: @""];
    if (!uuid || [uuid.UUIDString.lowercaseString isEqualToString:entry.lowercaseString] == NO) return nil;
    NSString *folder = [LBLibraryPath() stringByAppendingPathComponent:entry];
    struct stat st;
    if (lstat(folder.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode)) return nil;
    NSString *manifestPath = [folder stringByAppendingPathComponent:LBManifestName];
    struct stat manifestStat;
    if (lstat(manifestPath.fileSystemRepresentation, &manifestStat) != 0 ||
        !S_ISREG(manifestStat.st_mode) || S_ISLNK(manifestStat.st_mode) ||
        manifestStat.st_size <= 0 || manifestStat.st_size > 1024 * 1024) return nil;
    id loaded = [NSDictionary dictionaryWithContentsOfFile:manifestPath];
    if (![loaded isKindOfClass:NSDictionary.class]) return nil;
    id identifier = loaded[@"identifier"];
    if (![identifier isKindOfClass:NSString.class] || [identifier caseInsensitiveCompare:entry] != NSOrderedSame) return nil;
    return (NSDictionary *)loaded;
}

@implementation LumenBoardRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"LumenBoard";
}

- (void)importMediaTapped {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importTendiesTapped {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.data"]] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)manageLibraryTapped {
    NSError *error = nil;
    if (!LBEnsureUserDirectories(&error)) {
        [self showMessage:@"Library error" message:error.localizedDescription ?: @"Could not access the local library."];
        return;
    }
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:LBLibraryPath() error:nil] ?: @[];
    for (NSString *entry in entries) {
        NSDictionary *manifest = LBReadManagedManifest(entry);
        if (manifest) {
            NSString *folder = [LBLibraryPath() stringByAppendingPathComponent:entry];
            NSString *name = [manifest[@"originalName"] isKindOfClass:NSString.class] ? manifest[@"originalName"] : entry;
            NSString *status = [manifest[@"status"] isKindOfClass:NSString.class] ? manifest[@"status"] : @"unknown";
            [items addObject:@{@"folder": folder, @"identifier": manifest[@"identifier"], @"name": name, @"status": status}];
        }
    }
    if (items.count == 0) {
        [self showMessage:@"Local library" message:@"No imported items."];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Manage local items" message:@"Select an item to remove it from LumenBoard's local library. This does not change PosterBoard." preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *item in items) {
        NSString *label = [NSString stringWithFormat:@"%@ — %@", item[@"name"], item[@"status"]];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            NSError *removeError = nil;
            NSString *folder = item[@"folder"];
            NSString *standardFolder = folder.stringByStandardizingPath;
            NSString *root = LBLibraryPath().stringByStandardizingPath;
            if (![standardFolder hasPrefix:[root stringByAppendingString:@"/"]] || [standardFolder isEqualToString:root]) {
                [self showMessage:@"Removal refused" message:@"The selected item path failed validation."];
                return;
            }
            struct stat st;
            if (lstat(standardFolder.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode)) {
                [self showMessage:@"Removal refused" message:@"The selected item is not a regular managed directory."];
                return;
            }
            if (![NSFileManager.defaultManager removeItemAtPath:standardFolder error:&removeError]) {
                [self showMessage:@"Removal failed" message:removeError.localizedDescription ?: @"Unknown error."];
            } else {
                [self showMessage:@"Removed" message:@"The source was removed from LumenBoard's local library. PosterBoard was not modified."];
            }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 1, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)refreshLibraryTapped {
    NSError *error = nil;
    if (!LBEnsureUserDirectories(&error)) {
        [self showMessage:@"Library error" message:error.localizedDescription ?: @"Could not access the local library."];
        return;
    }
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:LBLibraryPath() error:&error] ?: @[];
    NSUInteger count = 0;
    for (NSString *entry in entries) {
        if (LBReadManagedManifest(entry)) count++;
    }
    [self showMessage:@"Local library" message:[NSString stringWithFormat:@"%lu imported item(s). Native PosterBoard installation is disabled in this build.", (unsigned long)count]];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;
    NSItemProvider *provider = result.itemProvider;
    BOOL isMovie = [provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier];
    NSString *typeIdentifier = isMovie ? UTTypeMovie.identifier : UTTypeImage.identifier;
    [provider loadFileRepresentationForTypeIdentifier:typeIdentifier completionHandler:^(NSURL *url, NSError *error) {
        if (!url || error) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self showMessage:@"Import failed" message:error.localizedDescription ?: @"The selected media could not be read."]; });
            return;
        }
        NSString *resolved = url.pathExtension.lowercaseString;
        NSSet *allowed = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"heic", @"heif", @"tif", @"tiff", @"gif", @"mov", @"mp4", @"m4v"]];
        if (![allowed containsObject:resolved]) {
            UTType *selectedType = [UTType typeWithIdentifier:typeIdentifier];
            NSString *preferredExtension = selectedType.preferredFilenameExtension.lowercaseString;
            if ([allowed containsObject:preferredExtension]) resolved = preferredExtension;
        }
        if (![allowed containsObject:resolved]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:@"Unsupported media format" message:@"The selected media has no supported filename extension. Nothing was imported."];
            });
            return;
        }
        // PHPicker's file-representation URL is temporary and must be copied
        // before this completion handler returns. Stage it privately here, then
        // move the slower library/manifest work to the utility queue.
        struct stat pickedStat;
        BOOL pickedIsRegular = url.isFileURL &&
            (lstat(url.path.fileSystemRepresentation, &pickedStat) == 0 &&
             S_ISREG(pickedStat.st_mode) && !S_ISLNK(pickedStat.st_mode));
        if (!pickedIsRegular || pickedStat.st_size <= 0 || (unsigned long long)pickedStat.st_size > LBMaxImportBytes) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:@"Import failed" message:@"The selected media is not a regular file or exceeds the 300 MiB limit."];
            });
            return;
        }
        NSString *temporaryName = [NSString stringWithFormat:@"LumenBoard-%@.%@", NSUUID.UUID.UUIDString.lowercaseString, resolved];
        NSURL *stagedURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:temporaryName]];
        NSError *stagingError = nil;
        if (![NSFileManager.defaultManager copyItemAtURL:url toURL:stagedURL error:&stagingError] ||
            chmod(stagedURL.path.fileSystemRepresentation, 0600) != 0) {
            [NSFileManager.defaultManager removeItemAtURL:stagedURL error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:@"Import failed" message:stagingError.localizedDescription ?: @"Could not stage the selected media safely."];
            });
            return;
        }
        [self importURL:stagedURL forcedExtension:resolved type:isMovie ? @"video" : @"image" cleanupTemporarySource:YES];
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!url) return;
    if (![url.pathExtension.lowercaseString isEqualToString:@"tendies"]) {
        [self showMessage:@"Unsupported file" message:@"Choose a .tendies archive. Other file types are not imported by this action."];
        return;
    }
    [self importURL:url forcedExtension:@"tendies" type:@"tendies-unvalidated" cleanupTemporarySource:NO];
}

- (void)importURL:(NSURL *)url forcedExtension:(NSString *)forcedExtension type:(NSString *)type cleanupTemporarySource:(BOOL)cleanupTemporarySource {
    NSURL *sourceURL = [url copy];
    NSString *sourceExtension = [forcedExtension copy];
    NSString *sourceType = [type copy];
    __block NSString *finalImportStatus = nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        BOOL access = sourceURL.isFileURL && [sourceURL startAccessingSecurityScopedResource];
        NSError *error = nil;
        BOOL ok = NO;
        BOOL preserveItemDirectory = NO;
        @try {
            struct stat sourceStat;
            BOOL sourceIsRegular = sourceURL.isFileURL &&
                (lstat(sourceURL.path.fileSystemRepresentation, &sourceStat) == 0 &&
                 S_ISREG(sourceStat.st_mode) && !S_ISLNK(sourceStat.st_mode));
            NSDictionary *attributes = sourceIsRegular ?
                [NSFileManager.defaultManager attributesOfItemAtPath:sourceURL.path error:&error] : nil;
            unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
            if (!sourceIsRegular || !attributes || size == 0 || size > LBMaxImportBytes) {
                if (!error) error = [NSError errorWithDomain:@"LumenBoard" code:201 userInfo:@{
                    NSLocalizedDescriptionKey: @"File is not a regular file, is empty, or exceeds the 300 MiB import limit."
                }];
            } else if (LBEnsureUserDirectories(&error)) {
                NSString *identifier = NSUUID.UUID.UUIDString.lowercaseString;
                NSString *itemDirectory = [LBLibraryPath() stringByAppendingPathComponent:identifier];
                BOOL createdItemDirectory = [NSFileManager.defaultManager createDirectoryAtPath:itemDirectory
                    withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error];
                if (createdItemDirectory) {
                    NSString *destination = [itemDirectory stringByAppendingPathComponent:[@"source" stringByAppendingPathExtension:sourceExtension]];
                    NSURL *destinationURL = [NSURL fileURLWithPath:destination];
                    BOOL sourceStored = NO;
                    if (cleanupTemporarySource) {
                        NSError *moveError = nil;
                        sourceStored = [NSFileManager.defaultManager moveItemAtURL:sourceURL toURL:destinationURL error:&moveError];
                        if (!sourceStored) {
                            // A cross-volume move may fail; fall back to a bounded copy,
                            // then delete the private staging file in the @finally block.
                            error = nil;
                            sourceStored = [NSFileManager.defaultManager copyItemAtURL:sourceURL toURL:destinationURL error:&error];
                            if (!sourceStored && !error) error = moveError;
                        }
                    } else {
                        sourceStored = [NSFileManager.defaultManager copyItemAtURL:sourceURL toURL:destinationURL error:&error];
                    }
                    if (sourceStored) {
                        preserveItemDirectory = YES;
                        NSMutableDictionary *manifest = [@{
                            @"schemaVersion": @2,
                            @"identifier": identifier,
                            @"originalName": sourceURL.lastPathComponent ?: @"Imported item",
                            @"type": sourceType,
                            @"sourceFilename": destination.lastPathComponent,
                            @"sourceBytes": @(size),
                            @"importedAt": [NSDate date],
                            @"status": [sourceType isEqualToString:@"tendies-unvalidated"] ? @"pending-validation" : @"stored-only",
                            @"validatorVersion": @"1.0.0",
                            @"installationState": @"installation-disabled"
                        } mutableCopy];
                        if ([sourceType isEqualToString:@"tendies-unvalidated"]) {
                            // Persist a durable pending state before validation or extraction.
                            // If the process is interrupted, recovery can identify this item
                            // without ever mistaking a partially processed archive for valid.
                            manifest[@"sha256"] = LBSHA256ForFile(destination) ?: @"";
                            NSString *manifestPath = [itemDirectory stringByAppendingPathComponent:LBManifestName];
                            NSError *pendingError = nil;
                            NSData *pendingData = [NSPropertyListSerialization dataWithPropertyList:manifest
                                format:NSPropertyListBinaryFormat_v1_0 options:0 error:&pendingError];
                            BOOL pendingSaved = pendingData && [pendingData writeToFile:manifestPath
                                options:NSDataWritingAtomic error:&pendingError];
                            NSError *validationError = pendingError;
                            NSDictionary *validation = nil;
                            if (pendingSaved) {
                                NSString *extractionPath = [itemDirectory stringByAppendingPathComponent:@"Extracted"];
                                validation = [LBTendiesValidator validateArchiveAtPath:destination
                                    extractToPath:extractionPath error:&validationError];
                            } else {
                                validation = @{@@"status": @"incomplete", @@"errors": @[@"Could not persist pending-validation manifest"]};
                            }
                            NSMutableDictionary *validationReport = [validation mutableCopy] ?: [NSMutableDictionary dictionary];
                            NSString *validationStatus = [validationReport[@"status"] isKindOfClass:NSString.class] ? validationReport[@"status"] : @"incomplete";
                            if ([validationStatus isEqualToString:@"extracted"]) {
                                validationReport[@"extractionStatus"] = @"extracted";
                                validationReport[@"status"] = @"valid";
                                manifest[@"status"] = @"extracted";
                                manifest[@"extractionPath"] = @"Extracted";
                                finalImportStatus = @"extracted";
                            } else if ([validationStatus isEqualToString:@"valid"]) {
                                manifest[@"status"] = @"extraction-ready";
                                finalImportStatus = @"extraction-ready";
                            } else {
                                manifest[@"status"] = validationStatus;
                                finalImportStatus = validationStatus;
                            }
                            manifest[@"validationStatus"] = validationReport[@"status"] ?: @"incomplete";
                            manifest[@"validationReport"] = validationReport;
                            if (validationError) manifest[@"validationError"] = validationError.localizedDescription;
                        }
                        NSData *data = [NSPropertyListSerialization dataWithPropertyList:manifest
                            format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
                        if (data && [data writeToFile:[itemDirectory stringByAppendingPathComponent:LBManifestName]
                            options:NSDataWritingAtomic error:&error] &&
                            chmod(itemDirectory.fileSystemRepresentation, 0700) == 0) {
                            ok = YES;
                        } else if (!error) {
                            error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                        }
                    }
                }
                if (createdItemDirectory && !ok && !preserveItemDirectory) [NSFileManager.defaultManager removeItemAtPath:itemDirectory error:nil];
            }
        } @catch (NSException *exception) {
            error = [NSError errorWithDomain:@"LumenBoard" code:202 userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: @"Import failed."
            }];
        } @finally {
            if (access) [sourceURL stopAccessingSecurityScopedResource];
            if (cleanupTemporarySource) [NSFileManager.defaultManager removeItemAtURL:sourceURL error:nil];
        }
        NSString *title = ok ? @"Import complete" : @"Import failed";
        NSString *message = ok ? @"The source is stored locally. It has not been installed into PosterBoard." : (error.localizedDescription ?: @"Unknown import error.");
        if ((ok || preserveItemDirectory) && [sourceType isEqualToString:@"tendies-unvalidated"]) {
            message = [NSString stringWithFormat:@".tendies result: %@. Structural validation does not prove PosterBoard compatibility. Native installation remains disabled.", finalImportStatus ?: @"pending-validation"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMessage:title message:message];
        });
    });
}
- (void)showMessage:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
