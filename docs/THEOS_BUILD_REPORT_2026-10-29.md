# LumenBoard Theos build attempt — 2026-10-29

## Result

**Blocked before compilation. No `.deb` was produced.** This report intentionally does not treat a source archive or a data-only Debian package as a compiled iOS package.

## Starting point and changes

- Starting Git commit: `1ae34bd` (`feat: generate full offline static wallpaper descriptors`).
- Host: Debian GNU/Linux 13 (trixie), x86_64, Linux kernel `6.18.55`.
- Available tools: Clang 17.0.0, GCC 14.2.0, GNU Make 4.4.1, `dpkg-deb` 1.22.22, Git, Python 3.13, `fakeroot`, and `dpkg-dev`.
- `THEOS` is unset; no `xcrun` command; filesystem search found no `iPhoneOS*.sdk`, `iPhoneSimulator*.sdk`, Theos installation, `ldid`, or standalone iOS toolchain.
- No Git remote is configured. No GitHub repository was created and no push was made.
- Makefile adjustment: `ARCHS` now targets `arm64` only. The iPhone X can execute arm64 binaries, and this avoids depending on the newer arm64e ABI toolchain path that Theos documents as problematic on non-macOS hosts. The package still uses `THEOS_PACKAGE_SCHEME = rootless`.

## Commands actually run

1. Environment inventory: `uname -a`, `/etc/os-release`, `uname -m`, `clang --version`, `gcc --version`, `make --version`, `dpkg-deb --version`, command discovery and filesystem search for iPhoneOS SDKs/Theos/toolchain.
2. Build command from the project root:

   ```sh
   make clean package FINALPACKAGE=1
   ```

   First attempt (before the Makefile architecture comment was added) failed at line 5; the repeat attempt after the edit failed at line 7. Both emitted the same error:

   ```text
   Makefile:7: /makefiles/common.mk: No such file or directory
   make: *** No rule to make target '/makefiles/common.mk'. Stop.
   ```

   Exit status: `2`. Since `THEOS` is unset, `$(THEOS)/makefiles/common.mk` resolves to `/makefiles/common.mk`.

3. Network check:

   ```sh
   curl -IL --max-time 12 https://github.com/theos/theos
   curl -I --max-time 8 https://theos.dev/docs/installation-linux
   ```

   Both failed with `curl: (6) Could not resolve host`.

4. Debian package-index refresh:

   ```sh
   apt-get -o Acquire::Retries=0 -o Acquire::http::Timeout=8 -o Acquire::https::Timeout=8 update
   ```

   It failed to resolve `deb.debian.org` for `trixie`, `trixie-updates`, and `trixie-security`. There were no usable package lists in `/var/lib/apt/lists`.

5. Existing portable test suite:

   ```sh
   python3 -m unittest discover -s tests -v
   ```

   Result: **68 tests passed**. These test Python utilities and structural/package contracts; they do not compile Objective-C, link an iOS bundle, or test native PosterBoard.

## Why a legitimate build cannot be completed in this session

The missing prerequisites are not just `xcrun`: there is no Theos makefile tree, no iOS SDK headers/frameworks, and no iOS cross-linker/toolchain. The official Theos Linux instructions require installing Theos and an iOS SDK/toolchain. The public `theos/sdks` repository provides an iOS 16.5 SDK release, which is a reasonable candidate for an iOS 16 deployment target, but the build container cannot resolve GitHub or Debian hosts to fetch it. No unknown mirror or unverified SDK archive was used.

References:

- Theos Linux installation: https://theos.dev/docs/installation-linux
- Theos rootless scheme: https://theos.dev/docs/rootless
- Theos package architecture/metadata: https://theos.dev/docs/packaging
- Public patched SDK repository and iOS 16.5 release: https://github.com/theos/sdks/releases

## Packaging and device validation status

| Check | Status | Evidence |
|---|---|---|
| Theos installed/configured | **Not done** | `THEOS` unset; no `makefiles/common.mk` |
| Objective-C compiled | **Not done** | Build stopped before compile |
| iOS preference bundle linked | **Not done** | No SDK/frameworks/toolchain |
| `.deb` generated | **No** | No package artifact exists from this run |
| Debian archive/control validated | **Not applicable** | No `.deb` to inspect |
| Installed on iPhone | **Not done** | No device installation attempted |
| PosterBoard tested on iOS 16.7.16 | **Not done** | No device/runtime test; native writer remains disabled |

## Next concrete step

Run the build in a network-enabled Linux/macOS environment with the official Theos installer, the official iOS 16.5 SDK from `theos/sdks`, the supported Linux toolchain (or macOS/Xcode), and the required Theos headers. On Linux, use the arm64 target already set in the Makefile, then execute `make clean package FINALPACKAGE=1`, inspect the generated package with `dpkg-deb --info` and `dpkg-deb --contents`, verify the staged Preference bundle contains a real Mach-O executable, and calculate SHA-256. Do not install it on the phone or enable native PosterBoard writes without explicit authorization and a separate device validation step.
