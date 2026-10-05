"""Isolated map geometry regressions. Every loop visits finite fixtures or image dimensions."""

from __future__ import annotations

import importlib
import io
import json
import sys
import tempfile
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from copy import deepcopy
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import patch

from PIL import Image

from .common import REPO_ROOT
from .selftest import case, expect

SCRIPTS = REPO_ROOT / ".agents/skills/map-asset-pipeline/scripts"
PACKAGE = "_chaos_map_geometry_selftest"


def _modules() -> SimpleNamespace:
    # Relative imports work without exposing generic names such as `audit` globally.
    if PACKAGE not in sys.modules:
        package = ModuleType(PACKAGE)
        package.__path__ = [str(SCRIPTS)]
        sys.modules[PACKAGE] = package
    return SimpleNamespace(
        **{
            name: importlib.import_module(f"{PACKAGE}.{name}")
            for name in ("geometry", "semantics", "derive", "subcell", "audit")
        }
    )


@contextmanager
def _fixture():
    build = REPO_ROOT / "build"
    build.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="map-geometry-", dir=build) as raw:
        root = Path(raw)
        game = root / "game"
        game.mkdir()
        (root / "pyproject.toml").write_text("[project]\nname='fixture'\n", encoding="utf-8")
        cells, sub = root / "cells.json", root / "subcell.json"
        modules = _modules()
        with (
            patch.multiple(
                modules.derive, ROOT=root, GAME=game, INDEX=root / "index.jsonl", OUT=cells
            ),
            patch.multiple(
                modules.subcell,
                ROOT=root,
                GAME=game,
                INDEX=root / "index.jsonl",
                CELLS=cells,
                OUT=sub,
            ),
            patch.multiple(modules.audit, CELLS=cells, SUBCELL=sub),
        ):
            yield root, modules


def _png(path: Path, size=(256, 256), boxes=(), faint=False) -> Path:
    with Image.new("RGBA", size, (0, 0, 0, 0)) as image:
        for box in boxes:
            image.paste((50, 100, 50, 255), box)
        if faint:
            image.putpixel((5, 5), (255, 255, 255, 3))
        image.save(path)
    return path


def _record(name: str, arch="flora.canopy_tree", alpha="transparent") -> dict:
    return {
        "id": name,
        "archetype": arch,
        "status": "generated",
        "environment": "fixture",
        "world_tier": 1,
        "type": "prop",
        "category": "flora",
        "name": name,
        "path": f"res://{name}.png",
        "alpha": alpha,
        "pivot": "bottom_center",
        "footprint_cells": list(_modules().semantics.FOOTPRINT[arch]),
    }


def _derive(root: Path, modules, records: list[dict]) -> dict:
    (root / "index.jsonl").write_text(
        "\n".join(json.dumps(record) for record in records), encoding="utf-8"
    )
    cells = modules.derive.build(None)
    (root / "cells.json").write_text(json.dumps(cells), encoding="utf-8")
    return cells


def _valid() -> tuple[dict, dict]:
    return (
        {
            "asset_count": 1,
            "assets": [
                {
                    "id": "fixture",
                    "archetype": "stone_and_ore.small_rock",
                    "grid": [1, 1],
                    "coverage": [[1.0]],
                    "blocks": [[True]],
                    "walk_surface": [[False]],
                    "block_cell_count": 1,
                    "sem": {"cov_gate": 0.2, "occluder_rule": "full_body", "walk_surface": False},
                }
            ],
        },
        {
            "asset_count": 1,
            "assets": [
                {
                    "id": "fixture",
                    "archetype": "stone_and_ore.small_rock",
                    "footprint": [1, 1],
                    "sub_grid": [1, 1],
                    "sub_fill": [[1.0]],
                    "block_rect": [0, 0, 0, 0],
                    "block_rect_px": [0, 0, 128, 128],
                    "blocked_by_scale": {"1.0": [0, 0, 0, 0]},
                }
            ],
        },
    )


def _finding(cells, sub, text: str) -> None:
    findings = _modules().audit.validate(cells, sub)
    expect(any(text in finding for finding in findings), f"missing {text!r}: {findings}")


@case("map-geometry-C1: translated solid art keeps complete coverage")
def _translated_art() -> None:
    with _fixture() as (root, modules):
        for i, box in enumerate(((0, 0, 100, 100), (120, 140, 220, 240))):
            image = _png(root / f"square{i}.png", boxes=(box,))
            for cols, rows in ((1, 1), (2, 3)):
                coverage = modules.derive.coverage_grid(image, cols, rows)[0]
                expect(coverage == [[1.0] * cols for _ in range(rows)], str(coverage))


@case("map-geometry-C3: faint stray alpha cannot shift bbox, fill, or contact")
def _faint_pixel() -> None:
    with _fixture() as (root, modules):
        boxes = ((39, 62, 217, 160), (113, 160, 143, 240))
        clean = _png(root / "clean.png", boxes=boxes)
        faint = _png(root / "faint.png", boxes=boxes, faint=True)
        expect(
            modules.derive.coverage_grid(clean, 2, 2)[0]
            == modules.derive.coverage_grid(faint, 2, 2)[0],
            "coverage shifted",
        )
        expect(
            modules.subcell.subcell_fill(clean) == modules.subcell.subcell_fill(faint),
            "subcell crop or fill shifted",
        )
        expect(
            modules.geometry.contact_run(clean)
            == modules.geometry.contact_run(faint)
            == (113, 143),
            "contact shifted",
        )


@case("map-geometry-C4: narrow poles and partial right/bottom subcells survive")
def _partial_subcells() -> None:
    with _fixture() as (root, modules):
        for width in (12, 31, 33, 178, 480):
            height = 201
            image = _png(
                root / f"pole{width}.png",
                (width + 32, height + 32),
                ((16, 16, width + 16, height + 16),),
            )
            fill, cols, rows, x, y, opaque = modules.subcell.subcell_fill(image)
            expect(
                (cols, rows, x, y, opaque) == ((width + 31) // 32, 7, 16, 16, False),
                f"wrong crop/grid for width {width}",
            )
            expect(fill == [[1.0] * cols for _ in range(rows)], "partial cell lost/diluted")
            expect(modules.subcell.trunk_columns(fill) == list(range(cols)), "pole lost")
            expect(modules.subcell.contact_px(image) == width, "wrong native contact width")


@case("map-geometry: canvas coverage retains partial reference cells")
def _canvas_coverage() -> None:
    with _fixture() as (root, modules):
        image = _png(root / "canvas.png", (129, 12), ((128, 0, 129, 12),))
        coverage, cols, rows, _ = modules.derive.coverage_grid(image)
        expect((cols, rows, coverage) == (2, 1, [[0.0, 1.0]]), str(coverage))
        image = _png(root / "tiny.png", (1, 1), ((0, 0, 1, 1),))
        expect(
            modules.derive.coverage_grid(image, 3, 2)[0] == [[1.0] * 3] * 2,
            "fine footprint sampling lost the solid pixel",
        )


@case("map-geometry-C7: walk surfaces preserve shape and handle empty art")
def _walk_shape() -> None:
    modules = _modules()
    coverage = [[0.9, 0.9, 0.9], [0.0, 0.5, 0.6]]
    ground = modules.derive.walk_surface_mask(coverage, "ground_contact", True)
    expect(ground == [[False] * 3, [False, True, True]], str(ground))
    expect(modules.derive.walk_surface_mask([], "ground_contact", True) == [], "empty failed")
    expect(
        modules.derive.walk_surface_mask(coverage, "full_body", False)
        == [[False] * 3 for _ in range(2)],
        "disabled surface enabled",
    )
    expect(
        modules.derive.walk_surface_mask(coverage, "full_body", True)
        == [[True] * 3, [False, True, True]],
        "full-body surface lost",
    )


@case("map-geometry-C9: reject empty/opaque cutouts while accepting sparse poles")
def _cutout_failures() -> None:
    with _fixture() as (root, modules):
        _png(root / "game/empty.png")
        _png(root / "game/opaque.png", boxes=((0, 0, 256, 256),))
        _png(root / "game/pole.png", (64, 256), ((26, 40, 38, 240),))
        records = [
            _record(name, "travel_and_wayfinding.signpost") for name in ("empty", "opaque", "pole")
        ]
        cells = _derive(root, modules, records)
        expect([asset["id"] for asset in cells["assets"]] == ["pole"], str(cells["failed"]))
        expect(len(cells["failed"]) == 2, "failed cutouts accepted")
        expect(cells["assets"][0]["canvas_px"] == [64, 256], "canvas dimensions fabricated")
        expect(
            modules.derive.coverage_grid(root / "game/empty.png", 2, 3)[0]
            == [[0.0] * 2 for _ in range(3)],
            "empty art changed matrix shape",
        )
        with redirect_stdout(io.StringIO()):
            expect(modules.derive.main([]) == 1, "derive CLI accepted failed cutouts")


@case("map-geometry-C5/C10: emitted base contact preserves position and source scale")
def _contact_projection() -> None:
    with _fixture() as (root, modules):
        left = _png(root / "game/left.png", boxes=((39, 62, 217, 160), (100, 160, 130, 240)))
        with Image.open(left) as image:
            image.resize((512, 512), Image.Resampling.NEAREST).save(root / "game/large.png")
        cells = _derive(root, modules, [_record("left"), _record("large")])
        expect(not cells["failed"] and not cells["issues"], str(cells))
        sub = modules.subcell.build()
        expect(not sub["failed"], str(sub["failed"]))
        for asset in sub["assets"]:
            expect(
                asset["block_rect"] == asset["blocked_by_scale"]["1.0"] == [0, 1, 0, 1],
                "left-side trunk was centered or disagreed with scale",
            )
            expect(asset["contact_reference_px"] == 30, "resolution changed world contact")
            expect(asset["contact_center_reference_px"] == 115, "resolution changed anchor")
            expect(asset["block_rect_px"] == [0, 128, 128, 256], "pixel bounds disagree")
        expect(
            sub["assets"][0]["blocked_by_scale"] == sub["assets"][1]["blocked_by_scale"],
            "source resolution changed scale projections",
        )
        expect(modules.audit.validate(cells, sub) == [], "producer output failed audit")


@case("map-geometry: absent contact never gains a minimum blocker")
def _no_phantom_contact() -> None:
    modules = _modules()
    expect(modules.subcell.rect_at_scale(0, 1.0, 2, 2) is None, "empty contact was floored")
    expect(modules.subcell.rect_at_scale(30, 1.0, 2, 2, 0) is None, "zero floor ignored")
    expect(modules.subcell.rect_at_scale(30, 1.0, 2, 2) == [1, 1, 1, 1], "tie changed")
    expect(
        modules.subcell.rect_at_scale(30, 1.0, 2, 2, center_px=-100) is None,
        "off-footprint contact created a blocker",
    )
    with _fixture() as (root, modules):
        _png(root / "game/flower.png", boxes=((40, 40, 200, 240),))
        cells = _derive(root, modules, [_record("flower", "flora.flower_cluster")])
        sub = modules.subcell.build()
        expect(
            all(rect is None for rect in sub["assets"][0]["blocked_by_scale"].values()),
            "decorative art gained contact",
        )
        expect(modules.audit.validate(cells, sub) == [], "nonblocking output failed audit")


@case("map-geometry-C2: valid serialized geometry passes")
def _audit_valid() -> None:
    expect(_modules().audit.validate(*_valid()) == [], "valid fixture rejected")


@case("map-geometry: threshold sweep reports authored footprint, not cropped resolution")
def _threshold_report() -> None:
    with _fixture() as (root, modules):
        _png(root / "game/tree.png", boxes=((39, 62, 217, 160), (113, 160, 143, 240)))
        _derive(root, modules, [_record("tree")])
        output = io.StringIO()
        with redirect_stdout(output):
            modules.subcell.measure([0.35])
        line = next(
            line for line in output.getvalue().splitlines() if line.startswith("flora.canopy_tree")
        )
        expect(line.split()[1:3] == ["1", "4"], f"wrong authored footprint: {line}")


@case("map-geometry-C2: phantom blockers, bad shapes, and missing records fail")
def _audit_broken_cells() -> None:
    for field, value, expected in (
        ("coverage", [[0.0]], "phantom blocker"),
        ("coverage", [[float("nan")]], "invalid coverage"),
        ("coverage", [[10**500]], "invalid coverage"),
        ("blocks", [[1]], "invalid blocks"),
        ("walk_surface", [[]], "invalid walk_surface"),
        ("block_cell_count", 0, "block_cell_count"),
        ("grid", [True, 1], "grid must"),
        ("sem", None, "missing semantics"),
        ("sem", {"cov_gate": 0.1, "occluder_rule": []}, "unknown occluder"),
    ):
        cells, sub = _valid()
        cells["assets"][0][field] = value
        _finding(cells, sub, expected)
    cells, sub = _valid()
    sub["assets"] = []
    _finding(cells, sub, "missing subcell asset")
    cells, sub = _valid()
    cells["assets"].append(deepcopy(cells["assets"][0]))
    _finding(cells, sub, "duplicate cell asset id")
    cells, sub = _valid()
    sub["assets"].append(deepcopy(sub["assets"][0]))
    _finding(cells, sub, "duplicate subcell asset id")


@case("map-geometry-C2b: tree width uses authored footprint, not cropped subgrid")
def _audit_tree_width() -> None:
    cells, sub = _valid()
    cells["assets"][0].update(
        archetype="flora.canopy_tree",
        grid=[2, 2],
        coverage=[[1.0] * 2] * 2,
        blocks=[[False] * 2, [True] * 2],
        walk_surface=[[False] * 2] * 2,
        block_cell_count=2,
        sem={"cov_gate": 0.01, "occluder_rule": "ground_contact"},
    )
    sub["assets"][0].update(
        archetype="flora.canopy_tree",
        footprint=[2, 2],
        sub_grid=[5, 5],
        sub_fill=[[1.0] * 5] * 5,
        block_rect=[0, 1, 1, 1],
        blocked_by_scale={"1.0": [0, 1, 1, 1]},
        block_rect_px=[0, 128, 256, 256],
    )
    _finding(cells, sub, "tree contact spans the full footprint width")


@case("map-geometry-C2: declared ground rows, walk surfaces, and openings are enforced")
def _audit_semantic_masks() -> None:
    cells, sub = _valid()
    cells["assets"][0]["walk_surface"] = [[True]]
    _finding(cells, sub, "unsupported walk surface")
    cells, sub = _valid()
    cells["assets"][0]["sem"]["walk_surface"] = True
    _finding(cells, sub, "declared walk surface is empty")
    cells, sub = _valid()
    cells["assets"][0]["sem"]["authored_open"] = "bottom_centre"
    _finding(cells, sub, "authored bottom opening is blocked")
    cells, sub = _valid()
    cells["assets"][0]["sem"]["occluder_rule"] = "none"
    _finding(cells, sub, "nonblocking archetype has a blocker")
    _finding(cells, sub, "nonblocking archetype has contact")
    cells, sub = _valid()
    cells["assets"][0].update(
        grid=[1, 2],
        coverage=[[1.0], [1.0]],
        blocks=[[True], [False]],
        walk_surface=[[True], [False]],
        block_cell_count=1,
        sem={"cov_gate": 0.1, "occluder_rule": "ground_contact", "walk_surface": True},
    )
    sub["assets"][0]["footprint"] = [1, 2]
    _finding(cells, sub, "ground contact blocks above bottom row")
    _finding(cells, sub, "ground-contact walk surface above bottom row")
    _finding(cells, sub, "ground-contact rectangle is above bottom row")


@case("map-geometry-C2: inconsistent subcell records and scale rectangles fail")
def _audit_broken_subcells() -> None:
    for field, value, expected in (
        ("footprint", [2, 1], "footprints disagree"),
        ("archetype", [], "archetypes disagree"),
        ("sub_fill", [], "invalid subcell fill"),
        ("block_rect", [0, 0, 1, 0], "outside its footprint"),
        ("blocked_by_scale", {}, "missing base-scale"),
        ("blocked_by_scale", {"1.0": None}, "disagrees with base scale"),
        ("blocked_by_scale", {"1.0": [0, 0, 0, 0], "1.6": [-1, 0, 0, 0]}, "invalid rectangle"),
        ("block_rect_px", [0, 0, 1, 1], "pixel bounds disagree"),
    ):
        cells, sub = _valid()
        sub["assets"][0][field] = value
        _finding(cells, sub, expected)
    for bad in (None, [], {}, {"assets": [None]}, {"assets": []}):
        expect(bool(_modules().audit.validate(bad, bad)), f"malformed input accepted: {bad}")


@case("map-geometry-C2: CLI exits 0 clean, 1 findings, 2 missing/unreadable input")
def _audit_exit_codes() -> None:
    with _fixture() as (root, modules), redirect_stdout(io.StringIO()):
        expect(modules.audit.main() == 2, "missing input accepted")
        cells, sub = _valid()
        (root / "cells.json").write_text(json.dumps(cells), encoding="utf-8")
        (root / "subcell.json").write_text(json.dumps(sub), encoding="utf-8")
        expect(modules.audit.main() == 0, "clean input failed")
        cells["assets"][0]["coverage"] = [[0.0]]
        (root / "cells.json").write_text(json.dumps(cells), encoding="utf-8")
        expect(modules.audit.main() == 1, "findings accepted")
        (root / "subcell.json").write_text("{", encoding="utf-8")
        expect(modules.audit.main() == 2, "malformed JSON accepted")


@case("map-geometry-H1/H3: missing root and malformed CLI arguments fail clearly")
def _invalid_inputs() -> None:
    modules = _modules()
    with tempfile.TemporaryDirectory(prefix="map-root-") as raw:
        try:
            modules.geometry.find_repo_root(Path(raw) / "geometry.py")
        except ValueError as exc:
            expect("no repository marker" in str(exc), str(exc))
        else:
            expect(False, "unrecognized repository was guessed")
    with redirect_stderr(io.StringIO()):
        try:
            modules.derive.main(["--env"])
        except SystemExit as exc:
            expect(exc.code == 2, "argparse did not reject missing environment")
        else:
            expect(False, "missing environment was accepted")
    for args in ((0, 1.0, 0, 1), (10, float("nan"), 1, 1), (-1, 1.0, 1, 1)):
        try:
            modules.subcell.rect_at_scale(*args)
        except ValueError:
            pass
        else:
            expect(False, f"invalid scale/contact accepted: {args}")


@case("map-geometry-D1/H7: footprints cover semantics and nested rows own their data")
def _semantic_ownership() -> None:
    semantics = _modules().semantics
    expect(set(semantics.SEMANTICS) == set(semantics.FOOTPRINT), "missing authored footprint")
    tree = semantics.SEMANTICS["flora.canopy_tree"]
    ancient = semantics.SEMANTICS["flora.ancient_tree"]
    for field in ("cultivation", "resource", "scale_profile"):
        expect(tree[field] is not ancient[field], f"shared {field} dictionary")
    template = {"supported_scales": [1.0, 1.6]}
    row = semantics._row("fixture", rule="none", scale_profile=template)
    row["scale_profile"]["supported_scales"].append(2.0)
    expect(template == {"supported_scales": [1.0, 1.6]}, "row mutates its template")
