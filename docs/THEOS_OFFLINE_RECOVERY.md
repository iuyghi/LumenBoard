# Offline recovery procedure for Theos

This procedure is for the current network-isolated build container. It does not require creating a GitHub repository, pushing source code, using paid services, or using Codespaces.

## Preferred route: prepare a Theos bundle on a network-enabled Linux x86-64 machine

Use Debian/Ubuntu x86-64 with internet access. The official Theos instructions are at https://theos.dev/docs/installation-linux. Do not run Theos as root.

```sh
sudo apt-get update
sudo apt-get install -y bash curl sudo build-essential fakeroot rsync perl git libxml2 libtinfo6 unzip xz-utils file
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
```

When prompted, select the non-Swift toolchain. The installer clones Theos recursively, installs the Linux iOS cross-toolchain and retrieves patched SDKs through Theos' own SDK installer. Check the installation:

```sh
export THEOS="$HOME/theos"
test -f "$THEOS/makefiles/common.mk"
test -x "$THEOS/toolchain/linux/iphone/bin/clang"
find "$THEOS/sdks" -maxdepth 1 -type d -name 'iPhoneOS*.sdk' -print
"$THEOS/toolchain/linux/iphone/bin/clang" --version
```

The public official `theos/sdks` releases include `iPhoneOS16.5.sdk`, a reasonable candidate for this project's iOS 16.0 deployment target. The build still needs to confirm all required frameworks and headers exist and link correctly.

Package the complete install for transfer. Preserve symlinks and permissions:

```sh
tar -C "$HOME" -cJf theos-linux-x86_64.tar.xz theos
sha256sum theos-linux-x86_64.tar.xz
```

Upload both `theos-linux-x86_64.tar.xz` and the text output of `sha256sum` to the conversation. This is the most reliable transfer because the complete Theos source tree includes its vendor/submodule content. Do not substitute a source-code ZIP that omits submodules.

## Alternative: transfer only required components

If the full archive cannot be uploaded, transfer all of the following from a verified official Theos installation:

- the complete Theos source tree, including `makefiles/`, `vendor/`, `mod/`, `include/`, and the submodule contents;
- `$THEOS/toolchain/linux/iphone/` including its `bin/` tools;
- `$THEOS/sdks/iPhoneOS16.5.sdk/`;
- the installer provenance, exact toolchain/SDK versions and SHA-256 hashes.

A SDK-only archive is insufficient: it does not provide the iOS compiler/linker or Theos' makefiles. A compiler-only archive is also insufficient without the SDK and Theos vendor files.

## Build and verify in the restored environment

Extract the archive into a user-owned location, then:

```sh
export THEOS="$HOME/theos"
cd LumenBoard-Development-Fresh
./tools/build_and_verify_deb.sh 2>&1 | tee logs/THEOS_BUILD_REAL.log
```

The script only compiles, packages, extracts and inspects the `.deb`; it does not install it on a device and does not write to PosterBoard. If compilation fails, preserve the entire log and correct the first actual compiler/linker error before retrying. Do not change `ARCHS` to `arm64e` unless the selected toolchain can produce the required ABI and the build verifies it.

## No free hosted build was initiated

A hosted runner such as GitHub Actions can be free within account quotas, but the project would have to be made available to a repository/workflow. This task explicitly forbids creating a repository or pushing source, so no hosted workflow was initiated. A separate existing network-enabled Linux machine plus a file transfer is the immediate free path that respects that restriction.
