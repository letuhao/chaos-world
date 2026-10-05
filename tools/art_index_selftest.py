"""Red-path self-tests for `tools art_index`.

A guard shipped in Python is unreachable from the GDScript suite, so nothing asserts it still goes
RED unless its cases are loaded (INC-0016). Separate module beside `race_from_lore_selftest` and
`png_provenance_selftest`, because `tools/selftest_cases.py` is shared and an append there cannot be
committed without sweeping another session's in-flight cases (INC-0041).

## What each case proves

Not "the indexer agrees with today's tree" — `art_index plan` already prints that, and it proves
nothing. Each case builds a record with one deliberately wrong property and asserts the rule fires,
and each also asserts a correct case is NOT refused so the rule discriminates:

- a WITHDRAWN shot is refused even when its render exists, is the right size, and carries a full
  workflow — the exact combination that made 22 renders look indexable
- a canvas that does not match the slot's install geometry is refused, and `--allow-wrong-canvas`
  is what lifts it (a flag that is silently inert would make the refusal look like the only option)
- a shot whose file is present but byte-identical to the INSTALLED copy is indexable, not refused —
  the generator's original and the installed copy are one render at two paths, and calling that "a
  different file" reported all 22 already-indexed shots as conflicts
- a shot already naming a DIFFERENT render is refused rather than repointed
- a render with no ComfyUI workflow is refused, because `source` would have to be invented
- `_digest` is content, not identity: two byte-identical files at different paths agree

Every fixture is a plain dictionary plus files under a temp directory. No case reads or writes the
real catalog, the real art root, or any shard.
"""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import struct
import tempfile
import zlib
from pathlib import Path

from . import art_index
from . import character_bundle_sync as sync
from .selftest import case, expect

#: A minimal shot row: enough for `plan_index` to reach every branch it has.
SHOT_KEYS = ("id", "kind", "slot", "pose", "framing", "expression", "scene", "status", "canvas")


def _shot(shot_id: str, slot: str, canvas: tuple[int, int], **extra) -> dict:
    row = {
        "id": shot_id,
        "kind": "dialogue" if slot == "dialogue_portrait" else "concept",
        "slot": slot,
        "pose": "standing",
        "framing": "waist-up",
        "expression": "plain",
        "scene": "a bare room",
        "status": "planned",
        "canvas": [canvas[0], canvas[1]],
        "path": None,
    }
    row.update(extra)
    return row


def _record(shots: list[dict]) -> dict:
    return {
        "id": "selftest-0001",
        "name": "Selftest Renn",
        "status": "canon",
        "art": {"shots": shots},
    }


def _png_bytes(width: int, height: int) -> bytes:
    """A minimal valid PNG of the given size. 8-bit RGBA, filtered scanlines, deflate-compressed."""
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = b"\x00" + bytes([0, 0, 0, 0] * width) * height

    def chunk(ctype: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + ctype
            + payload
            + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


## Every fixture root lives UNDER `GAME_DIR`, because what this tool writes is a `res://` path and a
## root in `%TEMP%` makes every case report "outside the game tree" — a real refusal, and not the one
## any case here is testing. The directory is created under a name no shipped path uses and removed
## on exit, so a crashed case leaves a stray folder rather than a stray catalog row.
FIXTURE_DIR = "art_index_selftest_fixture"


def _res_of(root: Path, relative: str) -> str:
    """The `res://` path of a file under the fixture root, built the way the tool builds one."""
    return "res://" + (root / relative).relative_to(GAME_DIR).as_posix()


@contextlib.contextmanager
def _fixture_root(subdir: str, files: dict[str, bytes]):
    """A temp art root INSIDE the game tree, patched over `art_fidelity.art_root`."""
    from . import art_fidelity
    from .common import GAME_DIR

    root = GAME_DIR / FIXTURE_DIR / subdir
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    try:
        for name, blob in files.items():
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(blob)
        original = art_fidelity.art_root
        art_fidelity.art_root = lambda: root
        try:
            yield root
        finally:
            art_fidelity.art_root = original
    finally:
        shutil.rmtree(GAME_DIR / FIXTURE_DIR, ignore_errors=True)


def _canvas(slot: str) -> tuple[int, int]:
    return tuple(sync.CANVAS_BY_SLOT[slot])


@case("art_index: a WITHDRAWN shot is refused even when its render is perfect")
def _withdrawn_shot_is_refused() -> None:
    """The combination that made 22 renders look indexable.

    Each withdrawn shot has a real file, the right canvas for its slot, and a full workflow,
    so every property this tool measures says "index me". The shot's own `withdrawn` note
    every property this tool measures says "index me". The shot's own `withdrawn` note says the art
    fails visual audit: apparent age 18-35 against an authored 41, a styled bob rather than the
    authored blade crop, brass jewellery a faction grants none of. Indexing one would attach a
    `path` and a recovered `source` to a row asserting the art is wrong, which is the false-claim
    shape DEF-0293 was filed for.
    """
    shot = _shot("dialogue-portrait", "dialogue_portrait", _canvas("dialogue_portrait"))
    shot["withdrawn"] = "gate-green but non-conforming: apparent age reads 18-35 against 41"
    width, height = _canvas("dialogue_portrait")
    # A render with a genuine workflow, at the right size, so ONLY `withdrawn` can be the reason.
    good_png = _workflow_png(width, height)
    with _fixture_root("withdrawn", {"selftest_dialogue_portrait.png": good_png}):
        updates, refusals = art_index.plan_index(_record([shot]))
    expect(
        not updates,
        f"a withdrawn shot produced {len(updates)} indexable row(s)",
    )
    expect(
        any("withdrawn" in r for r in refusals),
        f"the refusal did not mention withdrawal; it said {refusals!r}",
    )
    expect(
        any("re-render" in r for r in refusals),
        f"the refusal did not say what would make it indexable; it said {refusals!r}",
    )

    # And the SAME shot without the marker is indexable, so the rule discriminates.
    shot.pop("withdrawn")
    with _fixture_root("not_withdrawn", {"selftest_dialogue_portrait.png": good_png}):
        updates, refusals = art_index.plan_index(_record([shot]))
    expect(
        len(updates) == 1,
        f"the identical shot without `withdrawn` was still refused: {refusals!r}",
    )


def _workflow_png(width: int, height: int) -> bytes:
    """A PNG carrying a minimal but VALID ComfyUI graph, so provenance is present."""
    graph = {
        "761": {"class_type": "UNETLoader", "inputs": {"unet_name": "krea2/test.safetensors"}},
        "851": {"class_type": "SeedNode", "inputs": {"seed": 7}},
        "627": {"class_type": "CLIPTextEncode", "inputs": {"text": "a plain figure"}},
        "760": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "image/2026-10-04/Krea2-000001"},
        },
    }
    base = _png_bytes(width, height)
    # Splice a tEXt chunk in before IEND, which is where a reader looks and the last chunk is.
    payload = b"prompt\x00" + json.dumps(graph).encode("utf-8")
    chunk = (
        struct.pack(">I", len(payload))
        + b"tEXt"
        + payload
        + struct.pack(">I", zlib.crc32(b"tEXt" + payload) & 0xFFFFFFFF)
    )
    iend = b"\x00\x00\x00\x00IEND\xae\x42\x60\x82"
    assert base.endswith(iend)
    return base[: -len(iend)] + chunk + iend


@case("art_index: a canvas mismatch is refused, and --allow-wrong-canvas lifts ONLY that")
def _canvas_mismatch_is_refused() -> None:
    """The 1248x1664-everything problem, in miniature.

    Every shipped render is 1248x1664. A `dialogue_portrait` installs at 384x512, so such
    a file is right for a set member and wrong for a portrait. The flag exists so an author
    is right for a set member and wrong for a portrait. The flag exists so an author can index
    deliberately; a flag that is silently inert would make the refusal look like the only option.
    """
    shot = _shot("dialogue-portrait", "dialogue_portrait", (1248, 1664))
    blob = _workflow_png(1248, 1664)
    with _fixture_root("canvas", {"selftest_dialogue_portrait.png": blob}):
        updates, refusals = art_index.plan_index(_record([shot]))
        allowed_updates, allowed_refusals = art_index.plan_index(
            _record([shot]), allow_wrong_canvas=True
        )
    expect(
        not updates,
        f"a 1248x1664 file indexed for a 384x512 slot; got {[u['shot_id'] for u in updates]}",
    )
    expect(
        any("installs at" in r for r in refusals),
        f"the refusal did not name the geometry the slot installs at; it said {refusals!r}",
    )
    expect(
        len(allowed_updates) == 1,
        f"--allow-wrong-canvas indexed {len(allowed_updates)} row(s), not 1",
    )


@case("art_index: the generator's original and the INSTALLED copy are ONE render, not a conflict")
def _installed_copy_is_the_same_render() -> None:
    """22 already-indexed shots were reported as "already names a different file".

    `os.path.samefile` is what produced that: the original is at `unique/outputs/` and
    the installed copy at `unique/unique-<id>/`, so the OS says two files while the
    installed copy at `unique/unique-<id>/`, so the OS correctly says two files while the question
    being asked is about the render. Byte identity is the right question, and this case pins it by
    writing the same bytes to both paths.
    """
    width, height = _canvas("dialogue_portrait")
    blob = _workflow_png(width, height)
    shot = _shot("dialogue-portrait", "dialogue_portrait", (width, height))
    # Two paths for ONE render, exactly as in the real tree: the generator's original under
    # `outputs/`, the installed copy beside the catalog's `unique-0001/` row.
    files = {
        "outputs/selftest_dialogue_portrait.png": blob,
        "unique-0001/selftest_dialogue_portrait.png": blob,
    }
    with _fixture_root("same_render", files) as root:
        installed = root / "unique-0001/selftest_dialogue_portrait.png"
        shot["path"] = _res_of(root, "unique-0001/selftest_dialogue_portrait.png")
        updates, refusals = art_index.plan_index(_record([shot]))

        expect(
            len(updates) == 1,
            f"a byte-identical installed copy was refused as a conflict: {refusals}",
        )
        expect(
            bool(updates) and updates[0]["path"] == shot["path"],
            "the row was repointed away from its installed copy",
        )
        expect(
            art_index._digest(root / "outputs/selftest_dialogue_portrait.png")
            == art_index._digest(installed),
            "_digest disagreed with itself on two byte-identical files",
        )

        expect(
            len(updates) == 1,
            f"a byte-identical installed copy was refused as a conflict; refusals {refusals!r}",
        )
        expect(
            updates and updates[0]["path"] == shot["path"],
            f"the row was repointed away from its installed copy: "
            f"{updates[0]['path'] if updates else None!r}",
        )
        expect(
            art_index._digest(installed)
            == art_index._digest(outputs / "selftest_dialogue_portrait.png"),
            "_digest disagreed with itself on two byte-identical files",
        )


@case("art_index: a shot naming a DIFFERENT render is refused, never repointed")
def _different_render_is_refused() -> None:
    """Repointing a working layer at another file looks like a no-op and is not one.

    The installed copy has a `.import` sibling and is what the game loads; the generator's original
    has neither. Silently swapping one for the other changes what renders.
    """
    width, height = _canvas("dialogue_portrait")
    shot = _shot("dialogue-portrait", "dialogue_portrait", (width, height))
    other = _workflow_png(width, height)
    files = {
        "outputs/selftest_dialogue_portrait.png": other,
        # Genuinely different bytes at the same size: same geometry, different render.
        "unique-0001/selftest_dialogue_portrait.png": _png_bytes(width, height),
    }
    with _fixture_root("different_render", files) as root:
        shot["path"] = _res_of(root, "unique-0001/selftest_dialogue_portrait.png")
        updates, refusals = art_index.plan_index(_record([shot]))

    expect(
        not updates,
        "a shot naming a different render was repointed anyway",
    )
    expect(
        any("different file" in r for r in refusals),
        f"the refusal did not say the render differs; it said {refusals!r}",
    )


@case("art_index: a render with NO workflow is refused, because source would be invented")
def _workflowless_render_is_refused() -> None:
    """The one field this tool will not fill in from memory.

    `source` is the claim that a file came from a named checkpoint. A PNG written by anything other
    than ComfyUI carries no such record, and a row asserting one is precisely the defect DEF-0293
    was filed for — so the row is refused and the reason says what is missing.
    """
    width, height = _canvas("dialogue_portrait")
    shot = _shot("dialogue-portrait", "dialogue_portrait", (width, height))
    # A correct-size PNG with NO tEXt chunk at all.
    with _fixture_root(
        "no_workflow", {"selftest_dialogue_portrait.png": _png_bytes(width, height)}
    ):
        updates, refusals = art_index.plan_index(_record([shot]))
    expect(
        not updates,
        f"a workflowless render was indexed; got {[u['shot_id'] for u in updates]}",
    )
    expect(
        any("workflow" in r for r in refusals),
        f"the refusal did not say the file carries no workflow; it said {refusals!r}",
    )


@case("art_index: `plan` writes nothing and says so")
def _plan_writes_nothing() -> None:
    """A dry run that writes is worse than no dry run: the author believes nothing changed.

    Asserted by reading the record back after `run`, not by trusting the return code, because the
    return code only says the command finished.
    """
    import argparse

    width, height = _canvas("dialogue_portrait")
    shot = _shot("dialogue-portrait", "dialogue_portrait", (width, height))
    record = _record([shot])

    written: list[tuple[list[dict], object]] = []
    from . import unique_characters

    original_read = unique_characters.readable_catalog
    original_write = art_index._atomic_write
    art_index._atomic_write = lambda records, cid: written.append((records, cid))
    unique_characters.readable_catalog = lambda: [record]
    try:
        args = argparse.Namespace(
            art_index_action="plan", character_id="selftest-0001", allow_wrong_canvas=True
        )
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
            art_index.run(args)
        output = buffer.getvalue()
    finally:
        art_index._atomic_write = original_write
        unique_characters.readable_catalog = original_read

    expect(
        not written,
        f"plan called the shard writer {len(written)} time(s); it must write nothing",
    )
    expect(
        shot.get("path") is None and shot.get("source") is None,
        f"plan mutated the record it was reading: {sorted(shot)}",
    )
    expect(
        "nothing written" in output,
        f"plan did not state that it wrote nothing; it printed {output[-160:]!r}",
    )
