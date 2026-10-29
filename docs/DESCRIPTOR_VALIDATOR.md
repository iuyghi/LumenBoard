# Descriptor consistency validator

`tools/descriptor_consistency.py` performs a read-only check of an extracted descriptor-format tree. It checks required metadata, IDs and provider user-info consistency, the `.wallpaper` bundle, layer references, binary-plist `index.xml` targets, CAML XML well-formedness, asset references, duplicate IDs and unsafe filesystem entries.

The checker validates the project's source-derived structural profile. It does not emulate CoreAnimation/PosterBoard and cannot prove that the descriptor appears in the native gallery. Its current profile is informed by PosterForge's public MIT source and must be revised if a verified real iOS 16 fixture contradicts an assumption.

Run:

```sh
python3 tools/descriptor_consistency.py /path/to/extracted/descriptors
```

The full offline generator uses this validator before publishing each generated candidate:

```sh
python3 tools/static_descriptor_generator.py /path/to/photo.jpg /tmp/lb-candidates --title "Example"
python3 tools/descriptor_consistency.py /tmp/lb-candidates
```

The generator currently creates an empty `assetManifest.caml` to close a reference that PosterForge's visible image/empty-layer writer leaves dangling. This local consistency choice is not proof of Apple's expected manifest schema.

Status meanings:

- `passes-structural-checks`: the current profile's internal checks pass;
- `passes-with-warnings`: no hard errors, but unresolved links/assumptions remain;
- `invalid`: one or more structural or safety checks failed.

Even `passes-structural-checks` is only validation level 1. Validation level 2 requires comparison against a complete reference known to render on iOS 16.7.16. Validation level 3 requires an actual iPhone X test on iOS 16.7.16 with Dopamine and RootHide.
