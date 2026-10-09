"""Red-path checks for the isolated Celadon Faultlands pack validator."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

from . import faultlands_pack
from .selftest import case, expect


@case("faultlands-runtime-path-cannot-escape-pack")
def _runtime_path_cannot_escape_pack() -> None:
    try:
        faultlands_pack._safe_pack_path(
            faultlands_pack.PACK_DIR,
            "res://assets/packs/spirit_world_celadon_faultlands/runtime/../../../../outside.png",
            "fixture.path",
        )
    except faultlands_pack.ToolError as exc:
        expect("escapes" in str(exc), str(exc))
    else:
        expect(False, "Faultlands runtime path escaped the pack")


@case("faultlands-production-prompt-locks-style-resolution-and-alpha")
def _production_prompt_locks_style_resolution_and_alpha() -> None:
    pack = faultlands_pack._load_pack(faultlands_pack.PACK_DIR)
    record = next(
        item for item in pack["assets"] if item["id"].endswith("terrain_texture.base_surface")
    )
    prompt = faultlands_pack._production_prompt(pack, record)
    expect("strict straight-down orthographic camera" in prompt, prompt)
    expect("1024x1024 high-quality PNG source" in prompt, prompt)
    expect("fully opaque PNG" in prompt, prompt)


@case("faultlands-variant-prompt-requires-generated-base-reference")
def _variant_prompt_requires_generated_base() -> None:
    try:
        faultlands_pack.run(
            argparse.Namespace(
                faultlands_action="prompt",
                asset_id="spirit_world_celadon_faultlands.stone_and_ore.jade_seam_cluster.depleted",
            )
        )
    except faultlands_pack.ToolError as exc:
        expect("generate and install base asset" in str(exc), str(exc))
    else:
        expect(False, "variant prompt was allowed without an installed base reference")


@case("faultlands-duplicate-asset-id-is-rejected")
def _duplicate_asset_id_is_rejected() -> None:
    pack = copy.deepcopy(faultlands_pack._load_pack(faultlands_pack.PACK_DIR))
    pack["assets"][1]["id"] = pack["assets"][0]["id"]
    findings = faultlands_pack._findings(pack, faultlands_pack.PACK_DIR, verify_data=False)
    expect(any("duplicate asset id" in finding for finding in findings), str(findings))


@case("faultlands-source-directory-must-be-excluded-from-godot-imports")
def _source_directory_must_be_excluded_from_imports() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        pack_dir = Path(temporary) / faultlands_pack.PACK_ID
        shutil.copytree(faultlands_pack.PACK_DIR, pack_dir)
        (pack_dir / "original" / ".gdignore").unlink()
        pack = faultlands_pack._load_pack(pack_dir)
        findings = faultlands_pack._findings(pack, pack_dir, verify_data=False)
        expect(
            any("original/.gdignore is required" in finding for finding in findings),
            str(findings),
        )


@case("faultlands-source-path-must-stay-in-original-archive")
def _source_path_must_stay_in_original_archive() -> None:
    findings = faultlands_pack._source_findings(
        {
            "path": "game/assets/packs/../../outside.png",
            "sha256": "0" * 64,
            "size_px": [1, 1],
        },
        "fixture.asset",
    )
    expect(any("escapes" in finding for finding in findings), str(findings))


@case("faultlands-corrupt-original-hash-is-rejected")
def _corrupt_original_hash_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        original_dir = root / "game" / "assets" / "packs" / faultlands_pack.PACK_ID / "original"
        image_path = original_dir / "fixture" / "asset.png"
        image_path.parent.mkdir(parents=True)
        Image.new("RGBA", (2, 2), (10, 20, 30, 255)).save(image_path)
        old_root = faultlands_pack.REPO_ROOT
        old_original = faultlands_pack.ORIGINAL_DIR
        faultlands_pack.REPO_ROOT = root
        faultlands_pack.ORIGINAL_DIR = original_dir
        try:
            source = {
                "path": image_path.relative_to(root).as_posix(),
                "sha256": "0" * 64,
                "size_px": [2, 2],
            }
            findings = faultlands_pack._source_findings(source, "fixture.asset")
            expect(any("SHA-256" in finding for finding in findings), str(findings))
            source["sha256"] = hashlib.sha256(image_path.read_bytes()).hexdigest()
            findings = faultlands_pack._source_findings(source, "fixture.asset")
            expect(
                any("1024px production minimum" in finding for finding in findings), str(findings)
            )
        finally:
            faultlands_pack.REPO_ROOT = old_root
            faultlands_pack.ORIGINAL_DIR = old_original


@case("faultlands-install-keeps-source-runtime-and-data-mapped")
def _install_keeps_source_runtime_and_data_mapped() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        pack_dir = root / "game" / "assets" / "packs" / faultlands_pack.PACK_ID
        shutil.copytree(faultlands_pack.PACK_DIR, pack_dir)
        source = root / "openai-source.png"
        source_image = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        ImageDraw.Draw(source_image).rounded_rectangle(
            (260, 220, 780, 880), radius=88, fill=(55, 90, 84, 255)
        )
        source_image.save(source)
        old_root = faultlands_pack.REPO_ROOT
        old_original = faultlands_pack.ORIGINAL_DIR
        faultlands_pack.REPO_ROOT = root
        faultlands_pack.ORIGINAL_DIR = pack_dir / "original"
        try:
            asset = next(
                item
                for item in faultlands_pack._load_pack(pack_dir)["assets"]
                if item["id"].endswith("stone_and_ore.veinstone_boulder")
            )
            args = argparse.Namespace(
                asset_id=asset["id"],
                source=str(source),
                source_name="OpenAI image_gen test fixture",
                license="Generated test fixture",
                generated_on="2026-10-08",
                prompt_ref="fixture:veinstone-boulder",
                prompt="Test fixture prompt",
                replace_generated=False,
            )
            faultlands_pack._install_locked(args, pack_dir, source, args.generated_on)
            installed_pack = faultlands_pack._load_pack(pack_dir)
            installed = next(item for item in installed_pack["assets"] if item["id"] == asset["id"])
            runtime_path = faultlands_pack._safe_pack_path(pack_dir, installed["path"], asset["id"])
            data_record = json.loads(faultlands_pack._data_path(pack_dir, installed).read_text())
            expect(installed["status"] == "generated", "status did not change to generated")
            expect(runtime_path.is_file(), "normalized runtime PNG was not written")
            expect(data_record == installed, "per-asset data did not match the manifest")
            expect(
                len(installed.get("source_images", [])) == 1, "original source mapping is missing"
            )
            expect(faultlands_pack._audit(pack_dir) == [], str(faultlands_pack._audit(pack_dir)))
        finally:
            faultlands_pack.REPO_ROOT = old_root
            faultlands_pack.ORIGINAL_DIR = old_original
