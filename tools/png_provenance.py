"""Recover a render's provenance from the ComfyUI workflow its own PNG carries.

## Why this exists

DEF-0308 recorded that provenance for six renders was "unrecoverable", on the reasoning that the
generator's checkpoint is agent-chosen and never passed to the script, so not even a sidecar there
would know what produced a file. That reasoning looked at the WRITER and never at the ARTEFACT.

ComfyUI writes the whole graph it executed into a `prompt` `tEXt` chunk on every image it saves, so
the checkpoint, the LoRA stack, the seed, the aspect ratio, the output date and the verbatim
positive prompt are all inside the file. Verified on the six renders DEF-0308 called unrecoverable:
each carries a 10-14 KB `prompt` chunk, and `krea2/vxpKrea2Nsfw_beta4AnimeINT8.safetensors` is
recoverable from every one of them, exactly as from the nineteen renders indexed properly.

So the premise was stale, and re-measuring it is cheaper than defending it (BL-0619: a tracked
finding nothing re-checks decays silently).

## What is read, and what is deliberately not

Read: the base checkpoint, the LoRAs that were actually SWITCHED ON, the seed, the aspect ratio, the
output date and time prefix, the clip and VAE, and the positive prompt verbatim.

Not read, on purpose:

- **The negative prompt.** On this corpus it is the content-safety prompt ("explicit sexual content,
  sexual intercourse, ...") — a fixed guard string, not authoring. Copying it into a content row
  would put a sexual-content string in tracked metadata for no benefit.
- **LoRAs at strength 0.0.** Thirty-two are wired into the graph and all thirty-two are off. Listing
  them would make a render look like it drew on a style stack it did not draw on.

Every field is reported as VERIFIED (read out of the file) or absent. Nothing is inferred from a
sibling render, because a plausible guess about which checkpoint made a file is exactly the defect
this program exists to end.
"""

from __future__ import annotations

import json
import re
import struct
from dataclasses import dataclass, field
from pathlib import Path

from .common import ToolError, fail, ok

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

#: A ComfyUI graph links a downstream input with `["<node id>", <output index>]`. Bounded by the
#: node list, so resolving one is a dict lookup and not a walk.
_LINK = re.compile(r"^\[.*")

## The keyword ComfyUI saves the graph under. Read as a CONSTANT because a silent fallback to
## "the first tEXt chunk" would attribute provenance from an unrelated chunk on a PNG written by
## some other tool, which is the same fabrication in a different shape.
PROMPT_KEYWORD = "prompt"

## Classes that carry the values worth recording. Named rather than pattern-matched on input keys,
## because `text` appears on several node types and only one of them is the positive prompt.
CHECKPOINT_NODE = "UNETLoader"
CHECKPOINT_INPUT = "unet_name"
LORA_NODE = "LoraLoaderModelOnly"
POSITIVE_NODE = "CLIPTextEncode"
SAMPLER_NODE = "KSamplerAdvanced"
RESOLUTION_NODE = "ResolutionSelector"
SAVE_NODE = "SaveImage"
CLIP_NODE = "CLIPLoader"
VAE_NODE = "VAELoader"

## The safety guard this corpus used, matched only to be EXCLUDED from the positive prompt. A
## negative prompt that is a safety string is not authoring and must not reach a content row.
SAFETY_MARKER = "explicit sexual content"


@dataclass(frozen=True)
class Provenance:
    """Everything recoverable about how one PNG was made. `present` says the graph was there."""

    present: bool = False
    checkpoint: str = ""
    clip: str = ""
    vae: str = ""
    loras: tuple[str, ...] = ()
    seed: str = ""
    sampler: str = ""
    scheduler: str = ""
    steps: str = ""
    cfg: str = ""
    aspect_ratio: str = ""
    megapixels: str = ""
    background_removal: str = ""
    generated_on: str = ""
    filename_prefix: str = ""
    positive_prompt: str = ""
    negative_prompt: str = ""
    node_count: int = 0
    notes: list[str] = field(default_factory=list)

    @property
    def source(self) -> str:
        """The one-line `source` string a catalog row records.

        The checkpoint ALONE, with the active LoRAs named after it, because the graph wires 32 LoRA
        nodes and a reader given all 32 would believe the render drew on a style stack it did not.
        """
        if not self.checkpoint:
            return ""
        parts = [self.checkpoint]
        if self.loras:
            parts.append(f" + {len(self.loras)} active LoRA(s): {', '.join(self.loras)}")
        return f"ComfyUI (unet ({', '.join(parts)}))"

    def as_dict(self) -> dict[str, object]:
        return {
            "present": self.present,
            "checkpoint": self.checkpoint,
            "source": self.source,
            "clip": self.clip,
            "vae": self.vae,
            "loras": list(self.loras),
            "seed": self.seed,
            "sampler": self.sampler,
            "scheduler": self.scheduler,
            "steps": self.steps,
            "cfg": self.cfg,
            "aspect_ratio": self.aspect_ratio,
            "megapixels": self.megapixels,
            "background_removal": self.background_removal,
            "generated_on": self.generated_on,
            "filename_prefix": self.filename_prefix,
            "positive_prompt": self.positive_prompt,
            "negative_prompt_is_safety_guard": bool(self.negative_prompt)
            and SAFETY_MARKER in self.negative_prompt,
            "node_count": self.node_count,
            "notes": list(self.notes),
        }


def png_size(path: Path) -> tuple[int, int] | None:
    """`(width, height)` from IHDR, or None. Reads a fixed 24 bytes; never a scan."""
    try:
        with path.open("rb") as handle:
            head = handle.read(24)
    except OSError:
        return None
    if len(head) < 24 or head[:8] != PNG_MAGIC or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def _text_chunks(path: Path) -> dict[str, str]:
    """Every `tEXt` chunk, keyed by keyword. One sequential pass bounded by the file length."""
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ToolError(f"cannot read {path}: {error}") from error
    if data[:8] != PNG_MAGIC:
        raise ToolError(f"{path} is not a PNG")
    out: dict[str, str] = {}
    offset, total = 8, len(data)
    while offset + 8 <= total:
        (length,) = struct.unpack(">I", data[offset : offset + 4])
        ctype = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        if ctype == b"tEXt":
            keyword, _, text = payload.partition(b"\x00")
            out[keyword.decode("latin-1")] = text.decode("utf-8", "replace")
        offset += 12 + length
        if ctype == b"IEND":
            break
    return out


def _as_text(value: object) -> str:
    """ComfyUI wraps a scalar as `[value, control_after_generate]`; unwrap just that shape."""
    if isinstance(value, list) and value and not _LINK.match(str(value[0])):
        return str(value[0])
    if isinstance(value, list):
        return ""
    return str(value)


def _nodes(graph: dict, class_type: str) -> list[dict]:
    return [n for n in graph.values() if isinstance(n, dict) and n.get("class_type") == class_type]


def _first_input(graph: dict, class_type: str, key: str) -> str:
    for node in _nodes(graph, class_type):
        inputs = node.get("inputs") or {}
        if key in inputs:
            return _as_text(inputs[key])
    return ""


def _date_from_prefix(prefix: str) -> str:
    """`image/2026-10-04/Krea2-045855` -> `2026-10-04`.

    Taken from the OUTPUT PATH the graph saved to, which is the generator's own record of when the
    file was produced. Not from the filesystem mtime, which a copy or a checkout rewrites and would
    therefore date the render to whenever someone moved it.
    """
    found = re.search(r"(\d{4}-\d{2}-\d{2})", prefix)
    return found.group(1) if found else ""


def read_provenance(path: Path) -> Provenance:
    """Everything recoverable from one PNG. Never raises for a missing graph: `present` is False."""
    chunks = _text_chunks(path)
    raw = chunks.get(PROMPT_KEYWORD)
    if not raw:
        return Provenance(present=False, notes=[f"no {PROMPT_KEYWORD!r} tEXt chunk"])
    try:
        graph = json.loads(raw)
    except json.JSONDecodeError as error:
        return Provenance(present=False, notes=[f"{PROMPT_KEYWORD!r} chunk is not JSON: {error}"])
    if not isinstance(graph, dict):
        return Provenance(present=False, notes=[f"{PROMPT_KEYWORD!r} chunk is not a node graph"])

    notes: list[str] = []

    # Only LoRAs actually switched on. `strength_model` may be absent, in which case the node is
    # wired but unconfigured, so absence is reported as "not active" rather than guessed either way.
    active: list[tuple[str, float]] = []
    wired = 0
    for node in _nodes(graph, LORA_NODE):
        wired += 1
        inputs = node.get("inputs") or {}
        try:
            strength = float(inputs.get("strength_model", 0.0) or 0.0)
        except (TypeError, ValueError):
            strength = 0.0
        if strength != 0.0:
            active.append((str(inputs.get("lora_name") or ""), strength))
    if wired and not active:
        notes.append(
            f"{wired} LoRA node(s) wired, all at strength 0.0, so none affected the render"
        )

    positive, negative = "", ""
    for node in _nodes(graph, POSITIVE_NODE):
        text = str((node.get("inputs") or {}).get("text") or "")
        if SAFETY_MARKER in text:
            negative = text
        elif text and not positive:
            positive = text
    if negative and SAFETY_MARKER not in negative:
        notes.append("negative prompt is not the safety guard; it was not recorded")

    sampler_nodes = _nodes(graph, SAMPLER_NODE)
    sampler = sampler_nodes[0].get("inputs") or {} if sampler_nodes else {}
    # `SeedNode` is the generator's own control; the sampler's `noise_seed` is a second, unrelated
    # field on this corpus (851 against a SeedNode of 106), so the SeedNode is the one recorded.
    seed = _first_input(graph, "SeedNode", "seed") or _as_text(sampler.get("noise_seed", ""))

    prefix = _first_input(graph, SAVE_NODE, "filename_prefix")
    background = ""
    for node in _nodes(graph, "RMBG"):
        inputs = node.get("inputs") or {}
        background = f"RMBG {inputs.get('model', '')} (background={inputs.get('background', '')})"

    return Provenance(
        present=True,
        checkpoint=_first_input(graph, CHECKPOINT_NODE, CHECKPOINT_INPUT),
        clip=_first_input(graph, CLIP_NODE, "clip_name"),
        vae=_first_input(graph, VAE_NODE, "vae_name"),
        loras=tuple(f"{name} @{strength:g}" for name, strength in active),
        seed=seed,
        sampler=_as_text(sampler.get("sampler_name", "")),
        scheduler=_as_text(sampler.get("scheduler", "")),
        steps=_as_text(sampler.get("steps", "")),
        cfg=_as_text(sampler.get("cfg", "")),
        aspect_ratio=_first_input(graph, RESOLUTION_NODE, "aspect_ratio"),
        megapixels=_first_input(graph, RESOLUTION_NODE, "megapixels"),
        background_removal=background,
        generated_on=_date_from_prefix(prefix),
        filename_prefix=prefix,
        positive_prompt=positive,
        negative_prompt=negative,
        node_count=len(graph),
        notes=notes,
    )


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "png_provenance",
        help="recover a render's provenance from the ComfyUI workflow its own PNG carries",
    )
    actions = parser.add_subparsers(dest="png_provenance_action", required=True)
    report = actions.add_parser("report", help="print what each named PNG carries")
    report.add_argument("paths", nargs="+", help="PNG files to read")


def run(args) -> int:
    if args.png_provenance_action != "report":
        raise ToolError(f"unknown action {args.png_provenance_action}")
    missing = 0
    for raw in args.paths:
        path = Path(raw)
        if not path.is_file():
            fail(f"{raw}: no such file")
            missing += 1
            continue
        prov = read_provenance(path)
        size = png_size(path)
        print("=" * 78)
        print(f"{path.name}  {size[0]}x{size[1]}  {path.stat().st_size} bytes")
        if not prov.present:
            for note in prov.notes:
                fail(f"{path.name}: {note}")
            missing += 1
            continue
        print(f"   checkpoint      {prov.checkpoint}")
        print(f"   clip / vae      {prov.clip} / {prov.vae}")
        print(f"   active LoRAs    {', '.join(prov.loras) or 'none'}")
        print(f"   seed            {prov.seed}")
        print(
            f"   sampler         {prov.sampler} / {prov.scheduler}, "
            f"steps={prov.steps} cfg={prov.cfg}"
        )
        print(f"   aspect          {prov.aspect_ratio} at {prov.megapixels} MP")
        print(f"   background      {prov.background_removal}")
        print(f"   generated_on    {prov.generated_on}   (from {prov.filename_prefix})")
        print(
            f"   positive prompt {len(prov.positive_prompt)} chars, "
            f"starting: {prov.positive_prompt[:70]}"
        )
        for note in prov.notes:
            print(f"   note            {note}")
    if missing:
        fail(f"{missing} file(s) carried no recoverable provenance")
        return 1
    ok("every named PNG carries a ComfyUI workflow")
    return 0
