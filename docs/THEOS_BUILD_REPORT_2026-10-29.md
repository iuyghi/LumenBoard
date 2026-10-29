# LumenBoard — Theos build investigation (2026-10-29)

## Verdict

**No real `.deb` was produced. Compilation is blocked before the first Objective-C compile step.** No package was fabricated, no iPhone installation was attempted, and PosterBoard native writes remain disabled.

## Starting artifact and Git provenance

The supplied starting artifact was `LumenBoard-Development-Fresh-theos-build-attempt.zip`, described in the preceding handoff as commit `a11e76c`. The ZIP contains the project files but **does not contain a `.git` directory**, and no other LumenBoard Git repository or object database was found in the accessible filesystem. Therefore this environment cannot independently verify that `a11e76c` is an ancestor or preserve its original Git history. A recovered local snapshot commit is recorded for the new diagnostic changes; it is not represented as a verified descendant of `a11e76c`. To preserve the original ancestry, supply a repository bundle or archive that includes Git objects (for example, `git bundle create lumenboard.bundle --all` from the original clone).

## Environment inventory

- OS: Debian GNU/Linux 13 (trixie), architecture `amd64` / `x86_64`.
- Kernel: Linux `6.18.55`.
- Available: Swift-distributed Clang/Clang++ 17, GCC/G++ 14, GNU Make 4.4.1, `dpkg-deb` 1.22.22, `dpkg-buildpackage`, `fakeroot`, `git`, `curl`, `wget`, `tar`, `xz`, `rsync`, `unzip`, `perl`, `file`.
- Debian packages already installed include `libtinfo6`, `libxml2`, `rsync`, `unzip`, `perl`, `fakeroot`, and `dpkg-dev`; no package installation was attempted.
- Not found: `THEOS` variable, `$THEOS/makefiles/common.mk`, any Theos tree, any `iPhoneOS*.sdk`, `iPhoneSimulator*.sdk`, `ldid`, or an iOS cross-toolchain under the searched filesystem roots.
- APT lists contain no usable package index files; `/var/cache/apt/archives` contains no cached `.deb` dependencies.
- Proxy variables are empty; `/etc/resolv.conf` specifies DNS server `168.63.129.16`; default route is via `172.26.36.1` on `eth0`.

## Network diagnostics

The failures were tested separately rather than inferred from a single `curl` error:

- `getent ahosts github.com`, `raw.githubusercontent.com`, `deb.debian.org`: no addresses returned.
- Python `socket.getaddrinfo` for those hosts: `gaierror(-3, 'Temporary failure in name resolution')`.
- TCP connect to `168.63.129.16:53`: `ConnectionRefusedError(111, 'Connection refused')`.
- TCP connect to public HTTPS endpoints (including direct known IPs for GitHub and Debian): `ConnectionRefusedError(111, 'Connection refused')` after approximately one second.
- `curl -IL https://github.com/theos/theos`, `curl -IL https://raw.githubusercontent.com/theos/sdks/master/README.md`, and `curl -IL https://deb.debian.org/debian/`: `curl: (6) Could not resolve host`.
- Direct-IP HTTPS attempts with `curl --resolve` also failed to connect. TLS certificate verification was not disabled.
- `apt-get update` was not repeated because the previous attempt and current empty APT lists already show repository access is unavailable; no system network configuration was changed.

These results show that this execution container cannot access the external network using its configured route/DNS. The network restriction is not fixed by changing the project Makefile. No unverified mirror, hardcoded DNS modification, or TLS bypass was used.

## Build configuration review

Root `Makefile` currently specifies:

```make
ARCHS = arm64
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME = rootless
```

It builds only the `Preferences` subproject. The daemon in `Daemon/main.m` remains an unbuilt prototype and is not installed. `control` declares `Architecture: iphoneos-arm64`; `Preferences/Makefile` requests UIKit, PhotosUI, Photos, UniformTypeIdentifiers and the private Preferences framework. The PreferenceLoader entry and bundle metadata are present in the source archive.

The `arm64` choice is plausible for an iPhone X and avoids claiming that this Linux toolchain can emit the newer arm64e ABI. However, the target, framework imports, link flags, bundle staging paths and package architecture are **not validated by a real build**. The Makefile was not changed during this diagnostic pass because no toolchain was available to test a speculative edit.

## Commands and exact results

Build command executed from the extracted project root:

```sh
make clean package FINALPACKAGE=1
```

Output:

```text
Makefile:7: /makefiles/common.mk: No such file or directory
make: *** No rule to make target '/makefiles/common.mk'.  Stop.
```

Exit code: `2`. With `THEOS` unset, `$(THEOS)/makefiles/common.mk` resolves to `/makefiles/common.mk`. The failure occurs before compilation, so there is no compiler diagnostic about Objective-C or SDK compatibility yet.

Tests:

```sh
python3 -m unittest discover -s tests -v
```

Result: **68 tests passed** (`Ran 68 tests in 0.118s`, `OK`). These cover the Python utilities and structural validation, not Objective-C compilation, native rendering or iPhone behavior.

The full command/output record is in [`logs/THEOS_BUILD_ATTEMPT_2026-10-29.log`](../logs/THEOS_BUILD_ATTEMPT_2026-10-29.log).

## Free, official dependency path

The official Theos Linux installer is documented at <https://theos.dev/docs/installation-linux> and installs the Theos tree, Linux iOS toolchain and SDKs. Its current installer sources the x86-64 non-Swift toolchain from the `L1ghtmann/llvm-project` release and downloads patched SDKs via Theos' own `install-sdk` script. The official `theos/sdks` repository publishes `iPhoneOS16.5.sdk`; this is a reasonable candidate for this project's iOS 16.0 deployment target, subject to compilation checks.

On a network-enabled Debian/Ubuntu x86-64 machine, use a normal (non-root) user and the official installer:

```sh
sudo apt-get update
sudo apt-get install -y bash curl sudo build-essential fakeroot rsync curl perl git libxml2 libtinfo6 unzip xz-utils file
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

When prompted, choose the **non-Swift** toolchain. After the installer completes, verify the actual paths rather than trusting its success message:

```sh
export THEOS="$HOME/theos"
test -f "$THEOS/makefiles/common.mk"
test -x "$THEOS/toolchain/linux/iphone/bin/clang"
find "$THEOS/sdks" -maxdepth 1 -type d -name 'iPhoneOS*.sdk' -print
"$THEOS/toolchain/linux/iphone/bin/clang" --version
```

For offline transfer to this environment, archive the complete `$THEOS` directory, preserving symlinks and permissions:

```sh
tar -C "$HOME" -cJf theos-linux-x86_64.tar.xz theos
sha256sum theos-linux-x86_64.tar.xz
```

Transfer `theos-linux-x86_64.tar.xz` and its SHA-256 through the chat upload. Do not download an SDK from an unknown mirror. If a full Theos directory is too large to upload, transfer at minimum the complete Theos source tree **including submodules/vendor files**, `toolchain/linux/iphone/`, and `sdks/iPhoneOS16.5.sdk/`, preserving file modes and symlinks; also include the official installer/toolchain provenance and hashes. A standalone SDK by itself is insufficient.

Official references:

- Theos Linux installation: <https://theos.dev/docs/installation-linux>
- Theos rootless scheme: <https://theos.dev/docs/rootless>
- Theos variables/package scheme: <https://theos.dev/docs/variables>
- Official patched SDK repository: <https://github.com/theos/sdks>
- Official SDK releases: <https://github.com/theos/sdks/releases>

## Reproducible build and package checks

A helper script [`tools/build_and_verify_deb.sh`](../tools/build_and_verify_deb.sh) is included. Once Theos is available, it:

1. requires a valid Theos tree and iOS SDK/toolchain;
2. runs `make clean package FINALPACKAGE=1` with `THEOS_PACKAGE_SCHEME=rootless`;
3. requires exactly one `.deb` under `packages/`;
4. checks the Debian control metadata and `iphoneos-arm64` architecture;
5. extracts the package into a temporary directory (does not install it);
6. checks the rootless PreferenceLoader and PreferenceBundle paths;
7. requires a real arm64 Mach-O binary in the preference bundle;
8. records package metadata, contents and SHA-256.

No `.deb` exists from the current attempt, so package metadata, binary architecture and SHA-256 of a `.deb` cannot be reported.

## Validation levels

| Level | Result |
|---|---|
| 1. Objective-C compilation | **Not completed** |
| 2. `.deb` structure/content | **Not applicable — no `.deb`** |
| 3. Installation on iPhone | **Not performed** |
| 4. PosterBoard compatibility on iOS 16.7.16 | **Not tested** |

No install, respring, daemon activation, native PosterBoard write, or GitHub push was performed.
