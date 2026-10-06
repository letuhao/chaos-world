"""Red-path self-test for map source-image archive validation."""

from __future__ import annotations

from .selftest import case, expect
from .map_assets import _source_image_findings


@case("map-original-source-path-cannot-escape-archive")
def _source_path_cannot_escape_archive() -> None:
    findings = _source_image_findings(
        [
            {
                "path": "art-source/map-originals/../../outside.png",
                "size_px": [1, 1],
                "sha256": "0" * 64,
                "source": "test",
                "license": "test",
                "generated_on": "2026-10-06",
                "prompt_ref": "test",
                "prompt": "test",
            }
        ]
    )
    expect(
        any("escapes art-source/map-originals" in finding for finding in findings),
        "map index accepted a source image path outside its archive",
    )
