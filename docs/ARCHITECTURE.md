# LumenBoard architecture (reviewed baseline 0.1.0-1)

```text
PreferenceLoader pane (mobile user; the only component in the package)
  ├─ PHPicker: image/video source selection
  ├─ UIDocumentPicker: .tendies source selection
  ├─ local source directory + manifest.plist
  └─ list/remove items from the local source library only

Developer-only Python utility
  └─ inspects/extracts descriptor-format ZIP packages with bounded resources

Not packaged or running yet:
  └─ Daemon/main.m + launchd/control-script prototypes
     retained for review, not launched while native PosterBoard writes are disabled
```

## Local storage schema

`/var/mobile/Library/Application Support/LumenBoard/`

- `Library/<UUID>/source.<ext>` — original imported media or `.tendies` file.
- `Library/<UUID>/manifest.plist` — schema version, generated item ID, source filename/type/size, import timestamp and status.
- `Requests/<request UUID>.plist` — reserved for a future daemon IPC implementation; no request producer exists in the current pane.
- `Completed/<request UUID>.plist` — reserved for a future daemon IPC implementation.

## Privilege model

The shipped baseline has no privileged daemon. All currently exposed operations are local source import, listing, and removal under the mobile user's library. A future native adapter may need privilege to modify PosterBoard's app-container descriptor store, but that necessity alone is not sufficient justification to ship a root service before its trust boundary and behavior are verified.

`Daemon/main.m` and the corresponding launchd/control scripts are prototypes under `docs/prototypes/` (except `Daemon/main.m`, which remains a source-only prototype). They are not built, staged, or run. The earlier daemon scaffold accepted a mobile-writable queue and used path-based directory operations; before shipping it, replace these with hardened directory/file-descriptor operations or otherwise eliminate symlink/TOCTOU exposure, validate request ownership/schema/size, bound queue work, and test the IPC protocol.

A future IPC contract must validate request IDs, staged files, item ownership and supported actions. No generic `write(path, data)` or arbitrary destination-path IPC is acceptable.

## Required integration steps

1. Obtain a known-good iOS 16 descriptor-format `.tendies` fixture and document its complete tree and plist schema.
2. Add an on-device-safe archive parser/extractor equivalent in safety to the developer Python utility; the pane does not call Python.
3. Implement an internal descriptor builder against that fixture, including CAML and binary plist generation.
4. Randomize descriptor UUIDs and numeric wallpaper IDs, updating linked plist/text references atomically.
5. Stage all generated files outside the live descriptor root, verify the output tree, then install into the discovered `59/.../descriptors` target.
6. Track exactly which descriptor IDs LumenBoard created so removal cannot delete stock or third-party wallpapers.
7. Only add a privileged daemon after auditing the IPC protocol and path handling. Refresh/relaunch PosterBoard only after successful atomic installation and only with a rollback plan.
8. Enable the UI apply/remove action only after real-device tests pass.
