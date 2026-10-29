# LumenBoard — fresh development baseline

LumenBoard is a new, independent rootless-jailbreak project intended to manage photo, video and `.tendies` sources for the native PosterBoard gallery on iOS 16. The source tree in this package was created independently; it does not import an old LumenBoard checkout, Git bundle, workspace or history.

## Status of this baseline

This is a **pre-integration development baseline**, not a finished wallpaper installer.

Implemented in this tree:

- A new Theos/rootless package skeleton for `arm64` and `arm64e`; the Debian package architecture is `iphoneos-arm64`.
- A Preferences pane that imports local image/video/`.tendies` files into a managed library and can remove those library items. File copies run off the UI thread; unknown media extensions are rejected rather than relabelled.
- A privileged daemon source prototype in `Daemon/main.m`, deliberately **not built or packaged** in this baseline. It is not needed for local source management, and enabling root would be premature before the IPC trust boundary is hardened and the native descriptor adapter is tested.
- A portable Python `.tendies` inspector that checks ZIP structure, path traversal, symlinks/special entries, duplicate paths, resource limits and descriptor-vs-container format. It can extract a structurally verified descriptor package into an empty destination. Its tests use synthetic packages, not a known-good wallpaper from a real iOS 16 device.
- A read-only descriptor consistency checker, an offline static-image template transformer, and a full offline static-image descriptor candidate generator. The generator creates the whole source-derived tree, validates IDs and file references, stages output and atomically publishes a new candidate. Without a verified real iOS 16 fixture, it is not evidence of PosterBoard compatibility.
- Documentation of the PosterForge implementation study and device validation plan.

Not yet implemented/claimed:

- Runtime validation of `.tendies` inside the iOS pane. The Python inspector is developer-only and is not invoked by the pane.
- Generated image/video CAML and PosterBoard descriptors in the app.
- Automatic native gallery installation/removal.
- Successful Theos compilation, DEB creation, installation or iPhone testing.

The native writer intentionally remains disabled. The daemon and its launchd/control scripts are stored as prototypes under `docs/prototypes/`; they are not installed or run by the current package. The existence of a descriptor schema in public code is not proof that a newly generated wallpaper will render on iOS 16.7.16 with the exact Dopamine/RootHide build installed on the device.

## Requirements for an actual iOS package build

- A supported Theos environment: macOS with Xcode/iOS SDK, or Linux with the official Theos cross-toolchain and a suitable iOS SDK (the public Theos SDK repository includes iOS 16.5),
- Theos configured in `THEOS`,
- the applicable rootless packaging tools and PreferenceLoader headers/framework.

The build attempt on 2026-10-29 is documented in [`docs/THEOS_BUILD_REPORT_2026-10-29.md`](docs/THEOS_BUILD_REPORT_2026-10-29.md). It was blocked because this container had no Theos/SDK and could not resolve external hosts; no `.deb` was produced.

Then run:

```sh
make clean package FINALPACKAGE=1
```

The DEB, if the build succeeds, should be emitted under `packages/`. The current package target is intentionally limited to the unprivileged Preferences bundle; the daemon prototype is not compiled or staged. The local environment used to prepare this baseline does not have Theos, an Apple SDK or `xcrun`; it cannot produce or validate the iOS package here.

## Portable validation tests

Python 3.11+ is sufficient; no third-party Python package is needed:

```sh
python3 -m unittest discover -s tests -v
python3 tools/tendies_inspect.py --help
python3 tools/static_wallpaper_builder.py --help
python3 tools/descriptor_consistency.py --help
python3 tools/static_descriptor_generator.py --help
```

Inspect a user-supplied archive without extracting it:

```sh
python3 tools/tendies_inspect.py path/to/wallpaper.tendies
```

Extract only a descriptor-format archive into a new/empty directory:

```sh
python3 tools/tendies_inspect.py path/to/wallpaper.tendies --extract /tmp/lb-inspected
```

The inspector is a development/test utility; the Preferences app does not shell out to Python. Do not interpret a successful ZIP inspection as proof that the wallpaper is compatible with PosterBoard.

## Repository/publication status

No GitHub repository was created and no push was made. This is a local fresh project tree for review first.

## Descriptor consistency checker

`tools/descriptor_consistency.py` performs a read-only structural check over an extracted descriptor-format tree. It cross-checks observed descriptor identifiers and provider user-info references, wallpaper bundle paths, `.ca` layer references, index plist targets, CAML XML syntax and referenced assets. It reports only structural consistency; it does not prove compatibility with PosterBoard or replace a real iOS 16 reference. See `docs/DESCRIPTOR_VALIDATOR.md`.

Example after extracting a verified reference archive:

```sh
python3 tools/descriptor_consistency.py /tmp/lb-reference/descriptors
```

## Experimental static-image template transformer

`tools/static_wallpaper_builder.py` is a conservative, developer-only prototype. It does **not** synthesize a new PosterBoard schema. It requires a `.wallpaper` bundle extracted from a known-good iOS 16 descriptor fixture, then replaces one existing PNG/JPEG asset that is referenced by `main.caml`, `assetManifest.caml`, or `index.xml`. The source and target extensions must match. It preserves the reference CAML and plist files, stages output beside the destination, and refuses to overwrite existing paths.

Example (only after obtaining and inspecting a lawful known-good iOS 16 fixture):

```sh
python3 tools/tendies_inspect.py /path/to/known-good-ios16-descriptor.tendies --extract /tmp/lb-reference
python3 tools/static_wallpaper_builder.py \
  --template-bundle /tmp/lb-reference/descriptors/UUID/versions/1/contents/NAME.wallpaper \
  --asset 'BACKGROUND.ca/assets/existing.png' \
  --image /path/to/replacement.png \
  --output /tmp/LumenBoard-Candidate.wallpaper
```

The example paths after `descriptors/UUID/...` are placeholders and must be replaced with the exact tree and asset path present in the supplied archive. The tool produces a sibling `.report.json` sidecar. It does not rewrite descriptor UUIDs, wallpaper IDs, `providerInfo.plist`, `Wallpaper.plist`, provider user-info, or references outside the `.wallpaper` bundle. Consequently, its output is an offline candidate for comparison only—not an installable wallpaper descriptor and not proof of iOS 16.7.16 compatibility.

Supported source formats are PNG and JPEG, with basic signature/dimension checks. Video, CAML generation, `.tendies` runtime import, native installation/removal, and PosterBoard refresh remain out of scope. No native PosterBoard writes are enabled.


## Experimental full static descriptor generator

`tools/static_descriptor_generator.py` generates a complete local descriptor candidate from a JPEG using the public MIT-licensed PosterForge implementation as a technical reference. It creates the root metadata, `providerInfo.plist`, provider user-info, `Wallpaper.plist`, background/floating `.ca` bundles, CAML, manifests and index plists; it checks for ID collisions and runs the descriptor validator before atomically publishing the output.

```sh
python3 tools/static_descriptor_generator.py /path/to/photo.jpg /tmp/lb-candidates --title "My Static Poster"
python3 tools/descriptor_consistency.py /tmp/lb-candidates
```

This is structural validation only. A public iOS 16 dump from an iPhone 12 was found as a research lead, but the exact build/native rendering on iOS 16.7.16 and redistribution rights for its Apple assets are not verified; no third-party fixture is included. The generated empty `assetManifest.caml` is an unverified schema choice and must be compared with a real reference. No native PosterBoard write, refresh, import, update or removal is enabled. See `docs/ENGINE_PHASE_REPORT.md` for the fixture search, source attribution and three validation levels.
