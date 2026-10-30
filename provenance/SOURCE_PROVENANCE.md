# LumenBoard source provenance

## Immutable source material

- Original Git bundle: `LumenBoard-Development-Fresh-chatgpt-replit-audit.bundle`
- Git bundle SHA-256: `3c35135f43dc91ef92edd0e6b34df8e741656389ef4d5a4b74a32d6d38c272b1`
- Original bundle size: 83,589 bytes
- Original Git source HEAD: `5c9bfd516d93243d3bd7625839b39e0e68f6c9fb`
- Original source archive: `LumenBoard-Development-Fresh-source-immutable-2026-10-29.zip`
- Source archive SHA-256: `bab4191bffc8d458b4d94d94852d0c04e4271c060437e0bf268fae760df35962`
- Source archive size: 156,546 bytes

## Reconstruction and forensic correction

The original bundle was recovered independently from the ChatGPT conversation uploads. Two copies of both the bundle and source ZIP were byte-identical and matched the checksums above.

The original remote staging directory contained 46 Base64 fragments. Lexicographic concatenation was invalid. The forensic offset map found two duplicate intervals: offsets 62,000-64,000 (the segment named `part-06ab.b64`, already covered by `part-06b.b64`) and one duplicated character at offset 111,434 (the segment named `part-11bb1b2a3.b64`, already present in `part-12a-14.b64`). Missing source intervals were offsets 58,000-60,000 (2,000 characters) and 102,874-102,875 (one character). The Base64 character `z` occurs at both offsets 102,874 and 111,434; the first occurrence was restored, while the second is already present inside `part-12a-14.b64`. Equal one-byte content at two different offsets is not itself evidence of an overlapping segment.

A 51-entry, non-overlapping manifest was used. Its SHA-256 was `fb12d3cc3081d7551a744ae76876c3faca1f8093a9d2e308a308efe8075648fb`. The workflow checked every segment's declared byte length, ASCII Base64 alphabet, uniqueness, contiguous start/end offsets and total size (111,452 characters), decoded with strict Base64 validation, and verified the resulting 83,589-byte bundle against the original SHA-256 before running any Git import command.

## ZIP-to-Git source comparison

The immutable ZIP contained 52 regular files, including eight Python cache files; its 44 non-cache files all matched the corresponding files in the original Git commit byte-for-byte. The original Git commit contained 49 tracked files. There were zero ZIP-only files, zero byte differences, and five Git-only documentation/audit/log files:

- `docs/CHATGPT_REPLIT_ENVIRONMENT_AUDIT_2026-10-29.md`
- `logs/CHATGPT_REPLIT_ENV_AUDIT_MAKE_2026-10-29.log`
- `logs/CHATGPT_REPLIT_ENV_AUDIT_NETWORK_2026-10-29.log`
- `logs/CHATGPT_REPLIT_ENV_AUDIT_TESTS_2026-10-29.log`
- `logs/SOURCE_ARCHIVE_SHA256_2026-10-29.txt`

## Import into this repository

- Destination repository: `iuyghi/LumenBoard` (private)
- Destination branch: `main`
- Destination main SHA immediately before import: `4b9a5e1f0473e6918283bc6afa065e3f25b4e66a`
- Import merge commit: `65562f4b1c6b372085570eba95de59d0f246ec8c`
- Source commit remains unchanged and is an ancestor of `main`.
- The pre-existing destination main commit remains an ancestor of `main`.
- Import used a normal merge and a normal, non-force push. No force-push or history rewrite was used.

Temporary staging fragments and the reconstruction manifest were removed only after the bundle checksum, Git bundle validation, source commit, object integrity and remote import were verified. The complete original source history remains in Git.


## Reproducible build adjustments (2026-10-30)

The original source commit remains unchanged. The two build-environment corrections below are separate commits on `main` and are documented as post-import build compatibility changes:

1. **Document picker API.** The first real Theos compile on Ubuntu 24.04 with the installed iPhoneOS 16.5 SDK failed because `UIDocumentPickerViewController.initWithDocumentTypes:inMode:` and `UIDocumentPickerModeImport` were deprecated beginning with iOS 14 and the target build treats deprecation warnings as errors. `Preferences/LBRootListController.m` now imports UniformTypeIdentifiers and uses `initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.data"]] asCopy:YES`. The SDK exposes this Objective-C form through the `UTType` class; the Swift convenience property `UTType.data` is not an Objective-C property. This preserves the original generic-data file type and copy/import semantics while using the API supported by the project's iOS 16 deployment target. The Preferences Makefile already links UniformTypeIdentifiers.
2. **Subproject architecture.** The first build log showed Theos compiling the Preferences bundle for both `arm64e` and `arm64`, despite `ARCHS = arm64` in the aggregate root Makefile. The aggregate sub-make does not reliably inherit an ordinary parent Makefile variable. `Preferences/Makefile` now explicitly declares `ARCHS = arm64` and `TARGET = iphone:clang:latest:16.0`, keeping the built subproject aligned with the intended arm64/iOS 16 target. This avoids producing an arm64e slice not requested by the project's target configuration.

These changes affect only the Preferences picker initializer and the Preferences build target settings. They do not enable or package the daemon, change privileged file operations, alter the rootless install prefix, or enable native PosterBoard installation. The build log and post-change test result are required before treating the package as verified. No installation or runtime test on a device has been performed.


## Additional packaging runtime dependency

The first successful compile/link exposed a missing shared-library prerequisite during Theos `make package`: the Theos `plistutil` executable could not load `libplist-2.0.so.4`. On Ubuntu 24.04 this runtime is packaged as `libplist-2.0-4`; the CI dependency list now installs it explicitly alongside `libplist-utils`. This is a runner dependency only and does not change the application source or the produced package dependencies.
