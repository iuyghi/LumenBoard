#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${THEOS:?Set THEOS to a verified Theos installation (with iOS SDK and Linux iOS toolchain)}"

if [[ ! -f "$THEOS/makefiles/common.mk" ]]; then
  echo "ERROR: missing $THEOS/makefiles/common.mk" >&2
  exit 2
fi
if [[ ! -x "$THEOS/toolchain/linux/iphone/bin/clang" ]]; then
  echo "ERROR: missing executable $THEOS/toolchain/linux/iphone/bin/clang; verify Linux iOS toolchain" >&2
  exit 3
fi
if ! find "$THEOS/sdks" -maxdepth 1 -type d -name 'iPhoneOS*.sdk' -print -quit 2>/dev/null | grep -q .; then
  echo "ERROR: no iPhoneOS SDK found under $THEOS/sdks" >&2
  exit 4
fi

cd "$PROJECT_DIR"
build_out="$(mktemp -d "${TMPDIR:-/tmp}/lumenboard-packages.XXXXXX")"
trap 'rm -rf "$stage" 2>/dev/null || true; rm -rf "$build_out"' EXIT
THEOS_PACKAGE_SCHEME=rootless THEOS_PACKAGE_DIR="$build_out" make clean package FINALPACKAGE=1

shopt -s nullglob
debs=("$build_out"/*.deb)
if [[ ${#debs[@]} -ne 1 ]]; then
  echo "ERROR: expected exactly one newly generated .deb, found ${#debs[@]}" >&2
  printf '  %s\n' "${debs[@]:-<none>}" >&2
  exit 5
fi
deb="${debs[0]}"
echo "=== dpkg-deb --info ==="
dpkg-deb --info "$deb"
arch="$(dpkg-deb -f "$deb" Architecture)"
pkg="$(dpkg-deb -f "$deb" Package)"
if [[ "$arch" != "iphoneos-arm64" ]]; then
  echo "ERROR: expected Architecture: iphoneos-arm64; got '$arch'" >&2
  exit 6
fi
if [[ "$pkg" != "com.iuyghi.lumenboard" ]]; then
  echo "ERROR: unexpected package name '$pkg'" >&2
  exit 7
fi

stage="$(mktemp -d "${TMPDIR:-/tmp}/lumenboard-stage.XXXXXX")"
dpkg-deb -x "$deb" "$stage"
plist="$stage/var/jb/Library/PreferenceLoader/Preferences/LumenBoard.plist"
bundle="$stage/var/jb/Library/PreferenceBundles/LumenBoardPrefs.bundle"
if [[ ! -f "$plist" ]]; then
  echo "ERROR: missing rootless PreferenceLoader entry: $plist" >&2
  exit 8
fi
if [[ ! -d "$bundle" ]]; then
  echo "ERROR: missing rootless preference bundle: $bundle" >&2
  exit 9
fi
if [[ ! -f "$bundle/LumenBoardPrefs" ]]; then
  echo "ERROR: missing compiled bundle executable: $bundle/LumenBoardPrefs" >&2
  exit 10
fi
if ! file "$bundle/LumenBoardPrefs" | grep -Eiq 'Mach-O.*arm64|Mach-O universal'; then
  echo "ERROR: bundle executable is not identified as an arm64 Mach-O binary" >&2
  file "$bundle/LumenBoardPrefs" >&2 || true
  exit 11
fi

echo "=== package fields ==="
printf 'Package: %s\nArchitecture: %s\nVersion: %s\nDepends: %s\n' \
  "$pkg" "$arch" "$(dpkg-deb -f "$deb" Version)" "$(dpkg-deb -f "$deb" Depends)"
echo "=== package contents ==="
dpkg-deb --contents "$deb"
echo "=== compiled executable ==="
file "$bundle/LumenBoardPrefs"
mkdir -p "$PROJECT_DIR/packages"
final_deb="$PROJECT_DIR/packages/$(basename "$deb")"
if [[ -e "$final_deb" ]]; then
  echo "ERROR: refusing to overwrite existing package: $final_deb" >&2
  exit 12
fi
cp -p "$deb" "$final_deb"
echo "=== SHA-256 ==="
sha256sum "$final_deb"
echo "=== Verified artifact ==="
printf '%s\n' "$final_deb"
echo "=== Verification result ==="
echo "PASS: Debian archive metadata, rootless preference paths, and Mach-O executable verified. This does not test installation or PosterBoard runtime compatibility."
