# Static-image engine: full descriptor candidate

## Two separate tools

`tools/static_wallpaper_builder.py` is a template-preserving offline transformer: it replaces one existing referenced PNG/JPEG asset in an existing `.wallpaper` bundle. It remains useful when a known-good fixture is available.

`tools/static_descriptor_generator.py` now builds a **complete offline descriptor candidate** from a JPEG, including the descriptor root, root metadata, `providerInfo.plist`, provider user-info, `Wallpaper.plist`, `PF_Background.ca`, `PF_Floating.ca`, `main.caml`, `assetManifest.caml`, and binary-plist `index.xml` files. Its observed schema profile is derived from the public MIT-licensed `mubixbyte/PosterForge` source. It does not write to PosterBoard, does not install the descriptor, and does not call any refresh or process-kill command.

The generator requires JPEG input to match PosterForge's observed image path, which writes `assets/0.jpg`. It writes to a caller-selected local descriptors directory, generates a UUID descriptor directory and a separate numeric wallpaper ID, checks existing IDs before choosing new ones, builds in a temporary staging directory, validates the whole staged tree, and publishes by atomic rename. Failure removes the staging tree. Existing descriptors are never overwritten or removed.

## Usage

```sh
python3 tools/static_descriptor_generator.py /path/to/your-photo.jpg /tmp/lb-candidates --title "My Static Poster"
python3 tools/descriptor_consistency.py /tmp/lb-candidates
```

The generator prints a JSON report including IDs, input image SHA-256 and the internal validator result. A synthetic JPEG is provided only for automated tests at `tests/fixtures/synthetic.jpg`; it is not a wallpaper design or a real iOS reference.

## Fixture search and license decision

A public `C4ndyF1sh/Nugget-Wallpapers` release titled `iPadOS 17+iOS16` says its iOS 16 wallpaper was dumped from the author's iPhone 12. This is a useful provenance lead, but the release does not identify the exact iOS build, does not establish successful rendering on iOS 16.7.16, and does not provide an explicit license for redistribution of the wallpaper/Apple assets. The candidate archive was not downloaded in this environment because direct binary downloads from GitHub are unavailable here. It is not included in this project.

The `SerStars/Nugget-Wallpapers` repository lists an `iOS16.tendies` item and describes the software repository as GPL-3.0, but the software license alone does not grant redistribution rights to the Apple wallpaper assets. Its contribution guide also distinguishes Apple wallpaper submissions from user-created wallpapers. Therefore it is not treated as a license-cleared fixture. See the public release/catalog references in `docs/ENGINE_PHASE_REPORT.md`.

## Important schema uncertainty

The generator follows the observed PosterForge field names, path layout and CAML shape. One deliberate difference is that it writes an empty `assetManifest.caml` file because PosterForge's observed `writeIndexAt:width:height:error:` references that filename while its visible static-image/empty-layer writer does not create it. LumenBoard's empty CAML root closes the local file reference, but **this is an implementation hypothesis, not a verified Apple asset-manifest schema**. A structurally closed tree is not proof of native acceptance.

The generator currently uses the iPhone X logical class `375w-812h@3x~iphone`, observed in the PosterForge implementation, and fixed prominent colors from that implementation. It does not derive a color palette, crop or resize the source image, or implement Home Screen blur. The static asset is copied as JPEG and its dimensions are reflected in the CAML/index; the source file is checked for JPEG signature, dimensions and SOI/EOI markers, but is not fully decoded by a system image decoder.

## Three validation levels

1. **Structural validation:** automatic tests and `descriptor_consistency.py` validate file presence, plist parsing, identifier consistency, bundle references, CAML XML well-formedness, and asset paths. This level now passes for the generated synthetic candidate.
2. **Real iOS 16 reference comparison:** not completed. It requires a complete, license-cleared descriptor archive/tree known to render on the target iOS build. The public iOS 16 dump is a lead but is not verified for iOS 16.7.16 and could not be downloaded here.
3. **Native gallery/device test:** not completed. Requires iPhone X, iOS 16.7.16, Dopamine and RootHide. It must prove that the candidate appears and renders in native Collections and survives restart, while separately testing safe recovery.

## Safety and non-goals

- No code writes to `/var/jb`, the PosterBoard app container, system wallpaper locations or PosterBoard preferences.
- No install, refresh, import, update or remove action is wired into the app/daemon.
- Video, animation beyond the single static image, and `.tendies` generation/import remain separate future tasks.
- Before any native write is enabled, verify target path discovery, rootless permissions, a complete backup of only the intended LumenBoard-owned entries, atomic publish, rollback, and refusal to touch non-owned descriptors.
