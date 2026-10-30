import json
import os
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import static_wallpaper_builder as builder


def png_bytes(width=3, height=2, color=(20, 40, 60)):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    raw = b"".join(b"\x00" + bytes(color) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class StaticWallpaperBuilderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.template = self.root / "reference.wallpaper"
        (self.template / "assets").mkdir(parents=True)
        (self.template / "assets" / "base.png").write_bytes(png_bytes(2, 2))
        (self.template / "main.caml").write_text('<document image="assets/base.png"/>', encoding="utf-8")
        (self.template / "Wallpaper.plist").write_bytes(b"<?xml version='1.0'?><plist><dict><key>assets</key><dict><key>base.png</key><true/></dict></dict></plist>")
        self.source = self.root / "replacement.png"
        self.source.write_bytes(png_bytes(5, 4, (90, 80, 70)))
        self.output = self.root / "generated.wallpaper"

    def tearDown(self):
        self.temp.cleanup()

    def test_builds_candidate_from_existing_template_and_writes_sidecar(self):
        report = builder.build_static_candidate(self.template, "assets/base.png", self.source, self.output)
        self.assertTrue(self.output.is_dir())
        self.assertEqual((self.output / "assets" / "base.png").read_bytes(), self.source.read_bytes())
        self.assertEqual((self.output / "main.caml").read_text(), (self.template / "main.caml").read_text())
        self.assertFalse((self.output / "LumenBoard-Candidate-Report.json").exists())
        self.assertTrue(Path(report["report"]).is_file())
        sidecar = json.loads(Path(report["report"]).read_text())
        self.assertEqual(sidecar["status"], "offline-template-transform-only-not-installable")
        self.assertEqual((self.template / "assets" / "base.png").read_bytes(), png_bytes(2, 2))

    def test_rejects_missing_target_asset(self):
        with self.assertRaisesRegex(builder.BuildError, "does not exist"):
            builder.build_static_candidate(self.template, "assets/missing.png", self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_unreferenced_asset(self):
        (self.template / "main.caml").write_text("<document/>")
        with self.assertRaisesRegex(builder.BuildError, "not referenced"):
            builder.build_static_candidate(self.template, "assets/base.png", self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_rejects_path_traversal(self):
        with self.assertRaisesRegex(builder.BuildError, "unsafe relative path"):
            builder.build_static_candidate(self.template, "../outside.png", self.source, self.output)

    def test_rejects_empty_path_component(self):
        with self.assertRaisesRegex(builder.BuildError, "unsafe relative path"):
            builder.build_static_candidate(self.template, "assets//base.png", self.source, self.output)

    def test_rejects_invalid_existing_template_asset(self):
        (self.template / "assets" / "base.png").write_bytes(b"invalid")
        with self.assertRaisesRegex(builder.BuildError, "PNG signature"):
            builder.build_static_candidate(self.template, "assets/base.png", self.source, self.output)

    def test_rejects_extension_mismatch(self):
        jpg = self.root / "replacement.jpg"
        jpg.write_bytes(b"\xff\xd8\xff\xd9")
        with self.assertRaisesRegex(builder.BuildError, "must match"):
            builder.build_static_candidate(self.template, "assets/base.png", jpg, self.output)

    def test_rejects_invalid_png_magic(self):
        bad = self.root / "bad.png"
        bad.write_bytes(b"not a png")
        with self.assertRaisesRegex(builder.BuildError, "PNG signature"):
            builder.build_static_candidate(self.template, "assets/base.png", bad, self.output)

    def test_rejects_png_chunk_crc_corruption(self):
        bad = self.root / "crc-bad.png"
        payload = bytearray(png_bytes())
        payload[29] ^= 0x01
        bad.write_bytes(payload)
        with self.assertRaisesRegex(builder.BuildError, "CRC mismatch"):
            builder.build_static_candidate(self.template, "assets/base.png", bad, self.output)

    def test_rejects_existing_destination(self):
        self.output.mkdir()
        with self.assertRaisesRegex(builder.BuildError, "must not exist"):
            builder.build_static_candidate(self.template, "assets/base.png", self.source, self.output)

    def test_rejects_existing_report_sidecar(self):
        self.output.with_name(self.output.name + ".report.json").write_text("existing")
        with self.assertRaisesRegex(builder.BuildError, "sidecar must not exist"):
            builder.build_static_candidate(self.template, "assets/base.png", self.source, self.output)

    def test_rejects_template_symlink(self):
        (self.template / "assets" / "evil.png").symlink_to(self.source)
        with self.assertRaisesRegex(builder.BuildError, "symlink"):
            builder.build_static_candidate(self.template, "assets/base.png", self.source, self.output)

    def test_rejects_non_wallpaper_template(self):
        wrong = self.root / "not-a-wallpaper"
        wrong.mkdir()
        with self.assertRaisesRegex(builder.BuildError, "ends in .wallpaper"):
            builder.build_static_candidate(wrong, "assets/base.png", self.source, self.output)

    def test_rejects_non_wallpaper_output_name(self):
        with self.assertRaisesRegex(builder.BuildError, "destination name"):
            builder.build_static_candidate(self.template, "assets/base.png", self.source, self.root / "output")

    def test_no_output_on_prepublication_failure(self):
        (self.template / "main.caml").write_text("no image reference")
        with self.assertRaises(builder.BuildError):
            builder.build_static_candidate(self.template, "assets/base.png", self.source, self.output)
        self.assertFalse(self.output.exists())
        self.assertFalse(self.output.with_name(self.output.name + ".report.json").exists())

    def test_rejects_oversized_source(self):
        huge = self.root / "huge.png"
        with huge.open("wb") as stream:
            stream.truncate(builder.MAX_IMAGE_BYTES + 1)
        with self.assertRaisesRegex(builder.BuildError, "source image size"):
            builder.build_static_candidate(self.template, "assets/base.png", huge, self.output)

if __name__ == "__main__":
    unittest.main()
