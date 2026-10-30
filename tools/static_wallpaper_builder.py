#!/usr/bin/env python3
"""Conservative static-image transformer for a known-good PosterBoard template.

This tool does NOT invent PosterBoard descriptors. It clones an existing .wallpaper
bundle supplied from a known-good descriptor fixture and replaces one already-present,
referenced raster asset with an image of the same format. The output is a candidate
bundle for offline inspection, not an installable wallpaper descriptor.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import struct
import sys
import tempfile
import zlib
from pathlib import Path, PurePosixPath
from typing import Any

MAX_IMAGE_BYTES = 100 * 1024 * 1024
MAX_TEMPLATE_FILES = 4096
MAX_TEMPLATE_BYTES = 1024 * 1024 * 1024
SUPPORTED_IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg"}


class BuildError(ValueError):
    """Input template or image is unsuitable for a safe template transformation."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _image_info(path: Path) -> dict[str, Any]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        raise BuildError(f"cannot stat source image: {exc}") from exc
    if not path.is_file() or path.is_symlink():
        raise BuildError("source image must be a regular, non-symlink file")
    if size <= 0 or size > MAX_IMAGE_BYTES:
        raise BuildError(f"source image size must be 1..{MAX_IMAGE_BYTES} bytes")
    suffix = path.suffix.lower()
    if suffix not in SUPPORTED_IMAGE_SUFFIXES:
        raise BuildError("only PNG and JPEG images are supported by this prototype")
    with path.open("rb") as stream:
        head = stream.read(min(size, 32))
    if suffix == ".png":
        width, height = _png_dimensions(path)
        image_format = "png"
    else:
        if len(head) < 3 or head[:3] != b"\xff\xd8\xff":
            raise BuildError("file extension says JPEG but JPEG signature is invalid")
        width, height = _jpeg_dimensions(path)
        image_format = "jpeg"
    if not width or not height or width > 100_000 or height > 100_000:
        raise BuildError("invalid or unreasonable image dimensions")
    return {"format": image_format, "width": width, "height": height, "bytes": size, "sha256": _sha256(path)}



def _png_dimensions(path: Path) -> tuple[int, int]:
    """Validate PNG chunk framing and CRCs, without decoding pixel data."""
    with path.open("rb") as stream:
        if stream.read(8) != b"\x89PNG\r\n\x1a\n":
            raise BuildError("file extension says PNG but PNG signature is invalid")
        width = height = 0
        saw_ihdr = saw_idat = saw_iend = False
        chunk_index = 0
        while True:
            header = stream.read(8)
            if len(header) != 8:
                raise BuildError("truncated PNG chunk header or missing IEND")
            length, kind = struct.unpack(">I4s", header)
            if length > MAX_IMAGE_BYTES or stream.tell() + length + 4 > path.stat().st_size:
                raise BuildError("PNG chunk length exceeds file bounds or safety limit")
            payload = stream.read(length)
            crc_bytes = stream.read(4)
            if len(payload) != length or len(crc_bytes) != 4:
                raise BuildError("truncated PNG chunk")
            expected_crc = struct.unpack(">I", crc_bytes)[0]
            actual_crc = zlib.crc32(kind + payload) & 0xffffffff
            if actual_crc != expected_crc:
                raise BuildError(f"PNG CRC mismatch in {kind.decode('ascii', 'replace')} chunk")
            if chunk_index == 0 and (kind != b"IHDR" or length != 13):
                raise BuildError("PNG must start with a 13-byte IHDR chunk")
            if kind == b"IHDR":
                if saw_ihdr or chunk_index != 0 or length != 13:
                    raise BuildError("invalid duplicate or misplaced PNG IHDR")
                width, height = struct.unpack(">II", payload[:8])
                bit_depth, color_type, compression, filtering, interlace = payload[8:]
                if bit_depth not in (1, 2, 4, 8, 16) or color_type not in (0, 2, 3, 4, 6) or compression != 0 or filtering != 0 or interlace not in (0, 1):
                    raise BuildError("unsupported or invalid PNG IHDR fields")
                saw_ihdr = True
            elif kind == b"IDAT":
                if not saw_ihdr or saw_iend:
                    raise BuildError("PNG IDAT is out of order")
                saw_idat = True
            elif kind == b"IEND":
                if length != 0 or not saw_ihdr or not saw_idat:
                    raise BuildError("invalid PNG IEND or missing image data")
                saw_iend = True
                if stream.read(1):
                    raise BuildError("trailing data after PNG IEND")
                break
            elif not (kind[0] & 0x20) and kind not in (b"IHDR", b"PLTE", b"IDAT", b"IEND"):
                # Unknown critical chunks before IDAT cannot be safely interpreted by this prototype.
                raise BuildError(f"unsupported critical PNG chunk: {kind.decode('ascii', 'replace')}")
            chunk_index += 1
        if not saw_iend:
            raise BuildError("PNG missing IEND")
        return width, height


def _jpeg_dimensions(path: Path) -> tuple[int, int]:
    # Walk JPEG markers and accept dimensions only from a Start Of Frame marker.
    sof_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    with path.open("rb") as stream:
        if stream.read(2) != b"\xff\xd8":
            raise BuildError("invalid JPEG header")
        while True:
            byte = stream.read(1)
            if not byte:
                break
            if byte != b"\xff":
                continue
            marker_byte = stream.read(1)
            while marker_byte == b"\xff":
                marker_byte = stream.read(1)
            if not marker_byte:
                break
            marker = marker_byte[0]
            if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7 or marker == 0x01:
                continue
            length_raw = stream.read(2)
            if len(length_raw) != 2:
                break
            length = struct.unpack(">H", length_raw)[0]
            if length < 2:
                raise BuildError("malformed JPEG segment length")
            if marker in sof_markers:
                data = stream.read(min(length - 2, 8))
                if len(data) < 5:
                    break
                height, width = struct.unpack(">HH", data[1:5])
                return width, height
            stream.seek(length - 2, os.SEEK_CUR)
    raise BuildError("JPEG dimensions not found in a supported Start Of Frame marker")


def _safe_relative(raw: str) -> PurePosixPath:
    if not raw or "\\" in raw or raw.startswith("/") or "\x00" in raw:
        raise BuildError(f"unsafe relative path: {raw!r}")
    raw_parts = raw.split("/")
    path = PurePosixPath(raw)
    if any(part in ("", ".", "..") for part in raw_parts) or ":" in raw:
        raise BuildError(f"unsafe relative path: {raw!r}")
    return path


def _validate_template(bundle: Path, asset_rel: PurePosixPath) -> tuple[Path, dict[str, Any]]:
    if bundle.is_symlink() or not bundle.is_dir() or bundle.suffix != ".wallpaper":
        raise BuildError("template must be a real directory whose name ends in .wallpaper")
    root = bundle.resolve(strict=True)
    files = 0
    total = 0
    target: Path | None = None
    references: list[str] = []
    for path in root.rglob("*"):
        if path.is_symlink():
            raise BuildError(f"template contains symlink: {path.relative_to(root)}")
        rel = path.relative_to(root)
        if path.is_dir():
            continue
        if not path.is_file():
            raise BuildError(f"template contains non-regular entry: {rel}")
        files += 1
        total += path.stat().st_size
        if files > MAX_TEMPLATE_FILES or total > MAX_TEMPLATE_BYTES:
            raise BuildError("template exceeds file-count or total-size safety limit")
        if rel.as_posix() == asset_rel.as_posix():
            target = path
        if path.name in {"main.caml", "assetManifest.caml", "index.xml"}:
            try:
                payload = path.read_bytes()
            except OSError as exc:
                raise BuildError(f"cannot read template reference {rel}: {exc}") from exc
            # A bounded scan: reference data is small, and binary plist strings are ASCII/UTF-8 too.
            if len(payload) <= 16 * 1024 * 1024 and (asset_rel.name.encode() in payload or asset_rel.as_posix().encode() in payload):
                references.append(rel.as_posix())
    if target is None:
        raise BuildError(f"target asset does not exist inside template: {asset_rel.as_posix()}")
    if not references:
        raise BuildError("target asset filename is not referenced by main.caml, assetManifest.caml, or index.xml")
    suffix = target.suffix.lower()
    if suffix not in SUPPORTED_IMAGE_SUFFIXES:
        raise BuildError("target template asset must be a PNG or JPEG raster image")
    return target, {"template_files": files, "template_bytes": total, "reference_files": sorted(references), "asset_relative_path": asset_rel.as_posix()}


def build_static_candidate(template_bundle: Path, asset_relative_path: str, source_image: Path, destination: Path) -> dict[str, Any]:
    """Clone a known-good bundle and replace one referenced raster asset atomically.

    Destination must not exist. The original fixture is never modified. If any step
    fails, the temporary output is removed and no destination is published.
    """
    asset_rel = _safe_relative(asset_relative_path)
    target, template_info = _validate_template(template_bundle, asset_rel)
    if source_image.suffix.lower() != target.suffix.lower():
        raise BuildError(f"source image extension {source_image.suffix!r} must match template asset extension {target.suffix!r}")
    template_asset_info = _image_info(target)
    source_info = _image_info(source_image)
    dest = destination.absolute()
    if dest.suffix != ".wallpaper":
        raise BuildError("destination name must end in .wallpaper")
    report_dest = dest.with_name(dest.name + ".report.json")
    if dest.exists() or dest.is_symlink() or report_dest.exists() or report_dest.is_symlink():
        raise BuildError("destination and report sidecar must not exist; refusing to overwrite an existing path")
    if not dest.parent.is_dir():
        raise BuildError("destination parent directory must already exist")
    source_resolved = source_image.resolve(strict=True)
    template_resolved = template_bundle.resolve(strict=True)
    if source_resolved == target.resolve(strict=True) or template_resolved == dest:
        raise BuildError("source, template and destination must be distinct")

    temp_path = Path(tempfile.mkdtemp(prefix=f".{dest.name}.staging-", dir=dest.parent))
    staging_bundle = temp_path / template_bundle.name
    try:
        shutil.copytree(template_bundle, staging_bundle, symlinks=False)
        staged_target = staging_bundle.joinpath(*asset_rel.parts)
        # Validate the staged destination before writing; it must remain inside staging.
        staging_root = staging_bundle.resolve(strict=True)
        if staging_root not in staged_target.resolve(strict=False).parents:
            raise BuildError("staged target escapes output directory")
        with source_image.open("rb") as src, staged_target.open("wb") as out:
            shutil.copyfileobj(src, out, length=1024 * 1024)
            out.flush()
            os.fsync(out.fileno())
        output_info = _image_info(staged_target)
        if output_info["sha256"] != source_info["sha256"]:
            raise BuildError("post-write source/output hash mismatch")
        # Recheck that the output still has the same descriptor/CAML tree and reference files.
        _staged_target, staged_info = _validate_template(staging_bundle, asset_rel)
        if staged_info["reference_files"] != template_info["reference_files"]:
            raise BuildError("descriptor references changed unexpectedly during build")
        manifest = {
            "schema": "lumenboard.static-candidate.v1",
            "status": "offline-template-transform-only-not-installable",
            "template_bundle_name": template_bundle.name,
            "asset": asset_rel.as_posix(),
            "template_asset": {k: v for k, v in template_asset_info.items() if k != "sha256"} | {"sha256": template_asset_info["sha256"]},
            "source_image": {k: v for k, v in source_info.items() if k != "sha256"} | {"sha256": source_info["sha256"]},
            "output_asset_sha256": output_info["sha256"],
            "template": template_info,
            "checks": ["template is a .wallpaper directory", "target asset exists", "target asset referenced by descriptor metadata", "PNG/JPEG signature and dimensions validated", "template symlinks/non-regular files rejected", "source and output SHA-256 match", "destination published by same-filesystem rename"],
            "compatibility_note": "No real iOS 16 fixture was bundled with this project. This candidate is not proof of PosterBoard compatibility and must not be installed.",
        }
        report_staged = temp_path / "candidate-report.json"
        report_staged.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        # Publish the candidate bundle and its sidecar; if either rename fails, roll back both.
        os.replace(staging_bundle, dest)
        try:
            os.replace(report_staged, report_dest)
        except Exception:
            shutil.rmtree(dest, ignore_errors=True)
            raise
        return manifest | {"destination": str(dest), "report": str(report_dest)}
    except Exception:
        raise
    finally:
        shutil.rmtree(temp_path, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template-bundle", type=Path, required=True, help="known-good extracted .wallpaper directory")
    parser.add_argument("--asset", required=True, help="existing image path relative to template bundle, e.g. assets/LockScreen.png")
    parser.add_argument("--image", type=Path, required=True, help="replacement PNG/JPEG image with the same extension as the template asset")
    parser.add_argument("--output", type=Path, required=True, help="new destination directory ending in .wallpaper; must not exist")
    args = parser.parse_args(argv)
    try:
        report = build_static_candidate(args.template_bundle, args.asset, args.image, args.output)
    except (BuildError, OSError, shutil.Error) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, indent=2), file=sys.stderr)
        return 2
    print(json.dumps({"ok": True, **report}, indent=2, ensure_ascii=False))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
