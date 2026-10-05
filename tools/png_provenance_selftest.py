"""Red-path self-tests for `tools png_provenance`.

A guard shipped in Python is unreachable from the GDScript suite, so nothing asserts it still goes
RED unless its cases are loaded (INC-0016). Separate module beside `race_from_lore_selftest` and
`adr_cite_selftest`, because `tools/selftest_cases.py` is shared and an append there cannot be
committed without sweeping another session's in-flight cases (INC-0041).

## What each case proves

Not "the extractor reads today's corpus" — that is what `png_provenance report` already does, and it
proves nothing. Each case writes a PNG carrying a DELIBERATELY WRONG graph and asserts the extractor
reports it, or refuses to invent it:

- a graph with no `prompt` chunk at all yields `present: False`, never a partial answer
- a `prompt` chunk that is not JSON is refused and the reason is reported
- the checkpoint is read from `UNETLoader`, and a graph with NO `UNETLoader` yields no checkpoint
  rather than borrowing one from a sibling node
- a LoRA at strength 0.0 is NOT listed as active, and one at a non-zero strength IS
- the content-safety negative prompt is recognised as a guard and never returned as the positive one
- the date comes from the graph's own output path, NOT the filesystem mtime
- a graph naming none of these nodes reports absence for each, so a caller can tell "absent" from
  "empty because the graph was unreadable"

Every fixture is written to a temp directory and deleted; no case touches the repository.
"""

from __future__ import annotations

import contextlib
import io
import json
import struct
import tempfile
import zlib
from collections.abc import Iterator
from pathlib import Path

from . import png_provenance as pp
from .selftest import case, expect

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


@contextlib.contextmanager
def _png_with_chunks(path: Path, chunks: dict[str, str]) -> Iterator[Path]:
    """A real PNG carrying the given `tEXt` chunks. Temp dir only; the repo is never touched."""
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / path.name
        # IHDR: 1x1, 8-bit RGBA. Only the header is structurally required by the reader.
        ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)

        def chunk(ctype: bytes, payload: bytes) -> bytes:
            return (
                struct.pack(">I", len(payload))
                + ctype
                + payload
                + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF)
            )

        body = PNG_MAGIC + chunk(b"IHDR", ihdr)
        for keyword, text in chunks.items():
            body += chunk(b"tEXt", keyword.encode("latin-1") + b"\x00" + text.encode("utf-8"))
        body += chunk(b"IEND", b"")
        target.write_bytes(body)
        yield target


def _graph(**overrides) -> dict:
    """A minimal graph carrying every field this corpus actually uses."""
    base = {
        "761": {"class_type": "UNETLoader", "inputs": {"unet_name": "krea2/test.safetensors"}},
        "755": {
            "class_type": "CLIPLoader",
            "inputs": {"clip_name": "qwen3vl_4b_fp8_scaled.safetensors"},
        },
        "757": {"class_type": "VAELoader", "inputs": {"vae_name": "qwen_image_vae.safetensors"}},
        "851": {"class_type": "SeedNode", "inputs": {"seed": 401}},
        "857": {
            "class_type": "ResolutionSelector",
            "inputs": {
                "aspect_ratio": "3:4 (Portrait Standard)",
                "megapixels": 2.0,
                "multiple": 32,
            },
        },
        "599": {
            "class_type": "KSamplerAdvanced",
            "inputs": {
                "noise_seed": ["851", 0],
                "steps": 8,
                "cfg": 1.0,
                "sampler_name": "euler_ancestral",
                "scheduler": "beta",
            },
        },
        "627": {"class_type": "CLIPTextEncode", "inputs": {"text": "a plain unremarkable figure"}},
        "940": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": "explicit sexual content, sexual intercourse, genitalia"},
        },
        "760": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "image/2026-10-04/Krea2-045855"},
        },
    }
    base.update(overrides)
    return base


@case("png_provenance: a PNG with NO prompt chunk reports absence, not a partial answer")
def _no_prompt_chunk_is_absent() -> None:
    """The failure mode is inventing provenance, so absence must be an answer in its own right.

    A PNG written by any tool other than ComfyUI has no `prompt` chunk. Reporting an empty
    checkpoint and an empty prompt with `present: True` would let a caller record a row claiming the
    render came from nothing in particular — which is the same defect as recording a checkpoint that
    was never read, only quieter.
    """
    with _png_with_chunks(Path("bare.png"), {"Software": "some other tool"}) as path:
        prov = pp.read_provenance(path)
    expect(
        not prov.present,
        f"a PNG with no {pp.PROMPT_KEYWORD!r} chunk reported present={prov.present}",
    )
    expect(
        prov.source == "",
        f"an absent graph still produced a source string: {prov.source!r}",
    )
    expect(
        bool(prov.notes),
        "absence was reported without saying why, so a caller cannot distinguish it from a bug",
    )


@case("png_provenance: a prompt chunk that is NOT JSON is refused with the reason")
def _non_json_chunk_is_refused() -> None:
    """A truncated or foreign `prompt` chunk must not be half-parsed into a plausible answer."""
    with _png_with_chunks(Path("bad.png"), {pp.PROMPT_KEYWORD: "{not json at all"}) as path:
        prov = pp.read_provenance(path)
    expect(not prov.present, f"unparseable graph reported present={prov.present}")
    expect(
        any("JSON" in note for note in prov.notes),
        f"the refusal did not say the chunk was not JSON: {prov.notes!r}",
    )


@case("png_provenance: the checkpoint is read from UNETLoader and NEVER borrowed")
def _checkpoint_comes_from_the_graph() -> None:
    """A graph with no `UNETLoader` has no checkpoint, and must not acquire one by inference.

    The inference this forbids is the plausible one: this render sits beside nineteen others from
    the same session, so it "obviously" used the same checkpoint. That is how a provenance row
    starts asserting something no file supports.
    """
    graph = _graph()
    del graph["761"]
    with _png_with_chunks(Path("no_unet.png"), {pp.PROMPT_KEYWORD: json.dumps(graph)}) as path:
        prov = pp.read_provenance(path)
    expect(prov.present, "a well-formed graph without a UNETLoader reported absent")
    expect(
        prov.checkpoint == "",
        f"a graph naming no checkpoint reported {prov.checkpoint!r}",
    )
    expect(
        prov.source == "",
        f"a graph with no checkpoint still produced a source string: {prov.source!r}",
    )
    # And the control: with the node present, it IS read.
    with _png_with_chunks(Path("unet.png"), {pp.PROMPT_KEYWORD: json.dumps(_graph())}) as path:
        control = pp.read_provenance(path)
    expect(
        control.checkpoint == "krea2/test.safetensors",
        f"the checkpoint was not read from the graph; got {control.checkpoint!r}",
    )


@case("png_provenance: a LoRA at strength 0.0 is NOT active; a non-zero one IS")
def _only_strong_loras_count() -> None:
    """The corpus wires 32 LoRAs and switches all 32 OFF.

    Listing them as active would make a render look like it drew on a style stack it did not, and a
    reader has no way to tell a 0.0 entry from a real one unless the reader is the tool.
    """
    graph = _graph(
        **{
            "883": {
                "class_type": "LoraLoaderModelOnly",
                "inputs": {"lora_name": "krea2/off.safetensors", "strength_model": 0.0},
            },
            "884": {
                "class_type": "LoraLoaderModelOnly",
                "inputs": {"lora_name": "krea2/on.safetensors", "strength_model": 0.8},
            },
        }
    )
    with _png_with_chunks(Path("loras.png"), {pp.PROMPT_KEYWORD: json.dumps(graph)}) as path:
        prov = pp.read_provenance(path)
    joined = " | ".join(prov.loras)
    expect(
        any("on.safetensors" in lora for lora in prov.loras),
        f"the active LoRA was not reported; it reported {joined!r}",
    )
    expect(
        not any("off.safetensors" in lora for lora in prov.loras),
        f"a LoRA at strength 0.0 was reported as active; it reported {joined!r}",
    )
    expect(
        "1 active LoRA" in prov.source,
        f"the source string did not name the active LoRA count: {prov.source!r}",
    )


@case("png_provenance: the SAFETY negative prompt is never returned as the positive prompt")
def _safety_guard_is_not_the_prompt() -> None:
    """The corpus's negative prompt is a content guard, not authoring.

    Returning it would put a sexual-content string into tracked catalog metadata as if it were this
    render's prompt — a content-safety failure created by a provenance tool, in the one place the
    repo promises its art prompts are clean.
    """
    with _png_with_chunks(Path("safe.png"), {pp.PROMPT_KEYWORD: json.dumps(_graph())}) as path:
        prov = pp.read_provenance(path)
    expect(
        pp.SAFETY_MARKER not in prov.positive_prompt,
        f"the safety guard was returned as the positive prompt: {prov.positive_prompt[:80]!r}",
    )
    expect(
        prov.positive_prompt == "a plain unremarkable figure",
        f"the wrong CLIPTextEncode was taken as positive; got {prov.positive_prompt!r}",
    )
    expect(
        prov.as_dict()["negative_prompt_is_safety_guard"] is True,
        "the report did not record that the negative prompt was the safety guard",
    )


@case("png_provenance: generated_on comes from the GRAPH's output path, not the file mtime")
def _date_comes_from_the_graph() -> None:
    """A filesystem mtime dates the render to whenever someone moved it.

    A copy, a checkout, or a `git clone` rewrites it. The generator recorded where it saved the
    file, and that path is the only date here that describes the render rather than the file.
    """
    with _png_with_chunks(Path("dated.png"), {pp.PROMPT_KEYWORD: json.dumps(_graph())}) as path:
        prov = pp.read_provenance(path)
    expect(
        prov.generated_on == "2026-10-04",
        f"generated_on was {prov.generated_on!r}, not the date in the graph's own output path",
    )
    expect(
        "2026-10-04" in prov.filename_prefix,
        f"the output path was not recorded for audit: {prov.filename_prefix!r}",
    )
    # A prefix with no date in it yields no date, rather than today's or the file's.
    graph = _graph(
        **{"760": {"class_type": "SaveImage", "inputs": {"filename_prefix": "image/out"}}}
    )
    with _png_with_chunks(Path("undated.png"), {pp.PROMPT_KEYWORD: json.dumps(graph)}) as path:
        undated = pp.read_provenance(path)
    expect(
        undated.generated_on == "",
        f"an undated output path produced the date {undated.generated_on!r}",
    )


@case("png_provenance: the `report` action NAMES a file it cannot read, and exits non-zero")
def _report_fails_loudly_on_an_unreadable_file() -> None:
    """A report that prints a plausible table for a file it could not read is worse than no report.

    `tools` returns non-zero on failure because CI gates on the exit code, so a missing file has to
    move that code rather than produce an empty section somebody reads as "nothing to report".
    """
    import argparse

    args = argparse.Namespace(
        png_provenance_action="report",
        paths=["definitely-not-a-real-file-for-the-selftest.png"],
    )
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
        code = pp.run(args)
    output = buffer.getvalue()
    expect(code == 1, f"an unreadable file left the exit code at {code}")
    expect(
        "no such file" in output,
        f"the failure did not name the missing file; it printed {output[:160]!r}",
    )
