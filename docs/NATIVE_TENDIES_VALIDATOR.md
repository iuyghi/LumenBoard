# Native .tendies validation — first implementation

The Preferences bundle now compiles `LBTendiesValidator.m` into the app and links the iOS system zlib library (`-lz`). The validator does not invoke Python.

## Supported ZIP subset

- Single-disk classic ZIP only; ZIP64 and multi-disk archives are reported as unsupported.
- Stored and raw-DEFLATE members only.
- Limits: 300 MiB archive, 2,048 entries, 64 MiB/member, 128 MiB aggregate uncompressed, 500:1 compression ratio, 8 MiB plist.
- Validates central-directory records, local headers and filenames, CRC32, path traversal/absolute paths, duplicate and Unicode/case-folded names, Unix symlinks/special file modes, encryption flags, compression methods and plist syntax.
- Requires a descriptor/descriptors path and at least one Wallpaper.plist dictionary with identifier, name and assets fields.
- Container-format archives are refused.
- Optional extraction is performed only after all entries pass validation. It creates a previously nonexistent private output root, writes files with O_EXCL/O_NOFOLLOW, preserves the source archive, and removes the newly-created extraction root on failure.

SHA-256 is reported in the validation dictionary. A successful report explicitly sets compatibility to `not-tested`; it is not a PosterBoard compatibility assertion.

## App flow

After copying a .tendies file into the UUID library item, the import worker calls the native validator and requests extraction into a new `Extracted` child. The resulting status/report, SHA-256, validator version and installation-disabled marker are persisted in manifest.plist. PosterBoard installation, removal and system-store writes remain disabled.

## Limitations requiring follow-up

- The validator is a bounded first implementation, not a complete Apple descriptor schema validator. It does not yet validate providerInfo.plist semantics, provider user-info, CAML references, assetManifest/index semantics, or all required .wallpaper/.ca bundle relationships.
- The implementation currently retains bounded decompressed members in memory before extraction; the aggregate cap is 512 MiB and should be reduced or changed to streaming before release on memory-constrained devices.
- The native XCTest source is supplied but no Xcode project/test target exists in this repository snapshot; tests have not been run in an Apple XCTest environment.
- No real .tendies sample was available. No iOS SDK/Theos environment was available for an app build in this session.
- ZIP64, encrypted archives, multi-disk ZIPs and compression other than stored/DEFLATE are unsupported.
- The actual descriptor tree and rendering compatibility must be compared against a legally obtained known-good iOS 16.7.x sample and verified on the target device.

No code in this change writes to the PosterBoard container or enables the daemon.
