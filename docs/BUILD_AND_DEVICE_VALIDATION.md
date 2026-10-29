# Build blockers and validation record

Environment inspected while preparing the fresh baseline:

- Host: Linux container, Python 3.13.5, Git 2.47.3.
- `THEOS` is not configured.
- `xcrun` and an Apple iOS SDK are not available in this environment.
- Direct outbound network access from the build container failed DNS resolution; public research was performed with browser search instead.
- No physical iPhone or Dopamine/RootHide runtime is attached to this environment.

Consequences:

- Theos packaging was not run.
- The package metadata was corrected to `Architecture: iphoneos-arm64` for the rootless scheme. The privileged daemon and maintainer scripts are retained as prototypes and are not part of the current package.
- No DEB was built, installed or signed.
- No PosterBoard runtime behavior was exercised.
- No GitHub repository was created and nothing was pushed.

After Theos + an iOS SDK are available, run `make clean package FINALPACKAGE=1`; retain the full compiler log and package hash. Then perform the device test plan in `TEST_PLAN.md`. Do not enable native install merely because compilation succeeds.


## Current portable test results

The original suite of 18 tests passed when re-run at the start of the review. The original inspector/package-contract suite passes 29 tests: 25 archive-safety tests and 4 static package-contract checks. The subsequent static-image engine phase adds 16 tests; the combined current suite passes 45 tests. New cases cover malformed or absent Wallpaper.plist data, plist size limits, Unicode-normalized aliases, file/directory conflicts and CRC corruption. The archive fixtures are synthetic; no real `.tendies` archive was available, and the tests do not validate PosterBoard rendering.


## Static-image engine prototype

See `STATIC_IMAGE_ENGINE.md` and `ENGINE_PHASE_REPORT.md`. The current tool is a template-preserving replacement utility that requires a known-good `.wallpaper` bundle; it is not a descriptor synthesizer or installer. No real iOS 16 fixture is currently available, so only synthetic tests have been run.
