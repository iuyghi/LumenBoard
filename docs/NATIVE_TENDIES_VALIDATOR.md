# Native .tendies validation — hardened working branch

## Current implementation

The Preferences bundle compiles `LBTendiesValidator.m` and links the system zlib library. The validator does not invoke Python.

The archive is opened as an `NSDataReadingMappedIfSafe` mapping. ZIP structures are inspected through offsets into that mapping; the implementation no longer creates a copied `NSData` for each compressed member. This is memory-mapped access, not a fully `pread()`-based parser, and it is not claimed to provide a strict fixed resident-set bound for the mapped archive.

### ZIP checks implemented

- Classic single-disk ZIP only; ZIP64 and multi-disk archives are rejected.
- EOCD must terminate exactly at end-of-file, including its declared comment.
- Central directory length/count must match the parsed records and end immediately before EOCD.
- Stored and raw-DEFLATE members only; encrypted entries and unsupported methods are rejected.
- Local headers are checked against central-directory names, flags, methods, CRC and sizes.
- Data descriptor records are parsed with or without the optional signature and checked against central-directory CRC and sizes.
- Local record intervals include header, filename, extra field, payload and data descriptor; sorted intervals are checked for overlap and for collision with the central directory.
- Path traversal, absolute paths, backslashes, control characters, duplicate/case-folded/normalized paths, file-directory collisions, Unix symlinks and special-file modes are rejected.
- Limits: 300 MiB archive, 2,048 entries, 64 MiB/member, 128 MiB aggregate uncompressed, 500:1 ratio and 8 MiB captured plist.
- ZIP member data is processed with a 64 KiB output buffer. CRC and actual decompressed size are checked incrementally. Only plist members are captured in memory, subject to the 8 MiB cap.
- Extraction reprocesses members through the same bounded-buffer pipeline, writes to unique temporary files with `O_EXCL` and `O_NOFOLLOW` where available, flushes them, then publishes them with a no-overwrite hard link. The original archive is retained. A failed extraction removes only the newly created extraction root.

The archive mapping, Foundation metadata, path arrays and plist capture still consume memory. The 64 KiB buffer is the decompression working buffer, not a measured process-wide peak-memory guarantee.

## Manifest behavior

For `.tendies` imports, the source is copied into a UUID-named private library directory. The manifest is atomically written with `pending-validation` and the source SHA-256 before validation starts. The final validation result is written atomically afterward. If the final write fails, the source and pending manifest are retained instead of deleting the imported item. An interrupted import remains pending; automatic restart/revalidation recovery is not yet implemented.

## Native tests and CI

`Tests/Native/LBTendiesValidatorTests.m` contains XCTest fixture-based cases. `project.yml` generates a macOS XCTest project using XcodeGen. `.github/workflows/native-validator.yml` defines:
- macOS XCTest execution;
- Theos setup using the Xcode-provided iPhoneOS SDK;
- rootless package build and package metadata/content/architecture checks;
- SHA-256 and artifact upload.

The workflow configuration is committed, but its execution result must be checked in GitHub Actions. Creation of the workflow is not evidence that the test suite or package build passed. The current test source covers a subset of the full P27 matrix; ZIP64, multi-disk, signed/unsigned descriptor fixtures, overlap, bomb, simulated write failure, interruption/recovery, manifest concurrency and restart recovery are not all covered.

## Descriptor semantics and compatibility

The validator checks plist syntax and the existing minimum `Wallpaper.plist` fields (`identifier`, `name`, `assets`). It does not establish semantic compatibility for `providerInfo.plist`, provider user-info, CAML, `assetManifest.caml`, `index.xml`, asset references, or complete `.wallpaper`/`.ca` relationships. Unknown rules remain unverified. A structurally accepted archive is not a PosterBoard compatibility assertion.

## Safety boundary

PosterBoard installation, removal, system-store writes and descriptor mutation remain disabled. No device test or real `.tendies` sample test is claimed. iOS 16.7.16, Dopamine and RootHide compatibility remain unverified.
