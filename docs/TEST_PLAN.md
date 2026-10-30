# Verification plan

## Checks that run without iOS

- `python3 -m unittest discover -s tests -v` — archive-safety tests plus static package-contract guards.
- `python3 -m py_compile tools/tendies_inspect.py tests/test_tendies_inspect.py`.
- `python3 tools/tendies_inspect.py --help`.
- Lint `Preferences/Resources/Root.plist`, the Preferences Info plist, PreferenceLoader plist, and the daemon plist prototype with `plutil` on a compatible host.
- Shell syntax validation of `docs/prototypes/postinst` and `docs/prototypes/prerm`.
- `git diff --check`, tracked-file inventory, `git fsck --full --no-reflogs`, archive SHA-256, ZIP integrity and test-after-extraction.

These checks do not compile the Objective-C source or validate an actual `.tendies` package.

## iOS/PosterBoard tests that cannot be claimed here

On an iPhone X running iOS 16.7.16 with the exact Dopamine/RootHide variant/build, after building with compatible Theos + an iOS SDK:

1. Build and lint the unprivileged Preferences bundle, inspect the staged filesystem, and confirm that the package contains no daemon or active maintainer scripts.
2. Install on a backed-up/disposable test device and confirm the PreferenceLoader pane loads. The current package should not start any privileged service.
3. Import a small JPEG, HEIC and MOV/MP4; check preview/manage text, sizes, cancellation, repeated imports, malformed/unsupported extensions, responsiveness, and local removal.
4. Supply a known-good iOS 16 descriptor-format `.tendies` fixture plus iOS 17+, container-format, malformed ZIP, path traversal, symlink, duplicate, oversized and corrupt-CRC fixtures. Compare Python inspection results with expected results. Do not treat this tool as an on-device parser.
5. Before native integration, compare descriptor tree, `Wallpaper.plist`, provider metadata, `index.xml`, `main.caml` and assets against the fixture. Confirm the `59`/CollectionsPoster path and the iPhone X `logicalScreenClass` using the target device, not assumptions.
6. Only after an IPC threat model and request-path handling audit, build a privileged daemon in a separate change and test request validation, path traversal, symlink races, ownership, bounded queue work, rollback and failure recovery.
7. Once native integration is enabled, open the native Lock Screen wallpaper picker, verify appearance under Add New Wallpaper → Collections, select it, lock/unlock, reboot/respring and verify persistence.
8. Verify image frame timing, memory/CPU, optional blur behavior, and audio handling if those features are implemented.
9. Remove only a LumenBoard-owned descriptor; prove stock and third-party wallpapers remain untouched. Test uninstall/rollback and preserve logs plus before/after listings.

A successful compile or DEB creation is a packaging check only. It is not evidence that PosterBoard accepts or renders an installed descriptor.
