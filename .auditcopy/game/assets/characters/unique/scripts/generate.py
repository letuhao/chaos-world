#!/usr/bin/env python3
"""
Chaos World asset generation CLI — profile + free-style, agent-friendly.

Agents pick a profile, give a subject, optionally assign LoRAs to fixed slots
(order + weight) for style/expression/pose variation. No model/workflow knowledge needed.

Usage:
  python scripts/generate.py --list-profiles
  python scripts/generate.py --list-loras
  python scripts/generate.py --profile portrait --prompt "a cat girl" --output out.png
  python scripts/generate.py --profile portrait --prompt "a cat girl" \
      --lora style=0.8 --lora expression=0.6 --output out.png
  python scripts/generate.py --profile fullbody --prompt "a warrior" \
      --ratio "2:3" --no-bg --seed 42 --output out.png
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

# ── Configuration ──────────────────────────────────────────────────────────
# This repo is a CONSUMER — it has no models/workflows/LoRAs.
# All generation assets live in local-image-generator-service.

import os

REPO_ROOT = Path(__file__).resolve().parent.parent
COMFY_URL = "http://127.0.0.1:8188"

# Paths to the local-image-generator-service repo (models/workflows/LoRAs)
# Use env var CHAOS_WORLD_GEN_SERVICE or default to the known path
_GEN_SERVICE = Path(os.environ.get("CHAOS_WORLD_GEN_SERVICE", r"G:\Works\local-image-generator-service"))
LORAS_ROOT = _GEN_SERVICE / "models" / "loras" / "krea2"
WORKFLOW = _GEN_SERVICE / "workflows" / "moodyKrea2Minimal_v40_api_v2.json"
OUTPUTS_DIR = REPO_ROOT / "outputs"

# ── Profiles: ratio, background, default LoRA slots ────────────────────────
# Agents pick one — no model control. Add new profiles here to expose new
# asset classes without runtime code changes.

PROFILES = {
    "portrait": {
        "ratio": "3:4 (Portrait Standard)",
        "megapixels": 2,
        "bg": True,
        "description": "Bust-up character portrait, 3:4",
    },
    "fullbody": {
        "ratio": "3:4 (Portrait Standard)",
        "megapixels": 2,
        "bg": True,
        "description": "Full-body character sprite, 3:4",
    },
    "square": {
        "ratio": "3:4 (Portrait Standard)",
        "megapixels": 2,
        "bg": True,
        "description": "Square composition, 3:4",
    },
    "landscape": {
        "ratio": "3:4 (Portrait Standard)",
        "megapixels": 2,
        "bg": True,
        "description": "Landscape scene, 3:4",
    },
    # ── Game-ready canvases (HANDOFF W3) ─────────────────────────────────────
    # These override ResolutionSelector and set width/height on EmptyLatentImage
    # directly, so the PNG matches the game's declared canvas exactly.
    "map_sprite": {
        "canvas": (128, 192),          # tools/character_assets.py:256 proven spec
        "megapixels": 1,
        "bg": False,
        "description": "Small map token, 128x192, transparent",
    },
    "dialogue": {
        "canvas": (384, 512),          # tools/character_assets.py:268 proven spec
        "megapixels": 1,
        "bg": False,
        "description": "Dialogue portrait, 384x512, transparent",
    },
    "no-bg": {
        "ratio": "3:4 (Portrait Standard)",
        "megapixels": 2,
        "bg": False,
        "description": "Portrait with transparent background",
    },
}

# ── LoRA categories: style / expression / pose / control ──────────────────
# Agents assign LoRAs to slots by category. Order matters (first = outermost).

CATEGORY_INFO = {
    "style":      ("Art style / aesthetic", "--lora"),
    "expression": ("Facial expression / emotion", "--lora"),
    "pose":       ("Body pose / framing", "--lora"),
    "control":    ("ControlNet (pose/structure)", "--lora"),
}


def _scan_loras() -> dict[str, list[str]]:
    """Scan loras/ for .safetensors, grouped by subfolder."""
    groups: dict[str, list[str]] = {}
    if not LORAS_ROOT.exists():
        return groups
    for f in sorted(LORAS_ROOT.rglob("*.safetensors")):
        rel = f.relative_to(LORAS_ROOT)
        group = str(rel.parent) if str(rel.parent) != "." else "style"
        groups.setdefault(group, []).append(f.stem)
    return groups


def list_loras() -> None:
    """List available LoRAs by category."""
    for group, loras in _scan_loras().items():
        desc, _ = CATEGORY_INFO.get(group, (group, "--lora"))
        print(f"\n=== {group} ({len(loras)}) — {desc} ===")
        for name in loras:
            print(f"  {name}")


def list_profiles() -> None:
    """List available profiles."""
    for name, p in PROFILES.items():
        print(f"  {name}: {p['description']}")
        if p.get("canvas"):
            print(f"    canvas={p['canvas'][0]}x{p['canvas'][1]} (exact) bg={p['bg']}")
        else:
            print(f"    ratio={p['ratio']} megapixels={p['megapixels']} bg={p['bg']}")


def _get_slots(graph: dict) -> list[dict]:
    """Return the workflow's LoRA slots in chain order (traced from KSampler)."""
    ksampler = next(
        (n for n in graph.values() if n.get("class_type") == "KSamplerAdvanced"), None
    )
    if not ksampler:
        return []
    slots = []
    node_id = ksampler["inputs"]["model"][0]
    seen = set()
    while node_id and node_id not in seen:
        seen.add(node_id)
        node = graph.get(node_id)
        if not node:
            break
        if node.get("class_type") == "LoraLoaderModelOnly":
            slots.append(node)
        model_in = node.get("inputs", {}).get("model")
        node_id = model_in[0] if model_in else None
    return slots


def list_slots() -> None:
    """List the workflow's LoRA slots."""
    if not WORKFLOW.exists():
        print(f"Workflow not found: {WORKFLOW}")
        return
    graph = json.loads(WORKFLOW.read_text(encoding="utf-8"))
    slots = _get_slots(graph)
    print(f"Workflow has {len(slots)} LoRA slots (in load order):")
    for i, slot in enumerate(slots, 1):
        name = slot["inputs"].get("lora_name", "")
        strength = slot["inputs"].get("strength_model", 0)
        print(f"  slot {i}: {name} (strength {strength})")


def _assign_loras(graph: dict, selections: list[tuple[str, float]]) -> None:
    """Assign LoRAs to the fixed slots, in order. Extra LoRAs error out."""
    slots = _get_slots(graph)
    if len(selections) > len(slots):
        raise ValueError(
            f"Too many LoRAs ({len(selections)}). Workflow has {len(slots)} slots."
        )
    for slot, (name, strength) in zip(slots, selections):
        slot["inputs"]["lora_name"] = f"{name}.safetensors"
        slot["inputs"]["strength_model"] = strength


def _find_node(graph: dict, class_type: str) -> dict:
    """Find first node by class_type."""
    for node in graph.values():
        if node.get("class_type") == class_type:
            return node
    raise KeyError(class_type)


def _post(url: str, payload: dict) -> dict:
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def _get(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.load(resp)


def _get_bytes(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as resp:
        return resp.read()


def generate(
    *,
    profile: str,
    prompt: str,
    output: str,
    negative: str = "",
    loras: list[tuple[str, float]],
    ratio: str | None,
    bg: bool | None,
    seed: int,
    comfy_url: str,
) -> str:
    """Generate an image via ComfyUI and save to output path."""
    p = PROFILES[profile]
    if not WORKFLOW.exists():
        raise FileNotFoundError(
            f"Workflow not found: {WORKFLOW}\n"
            "Place a Krea2 Turbo API workflow at workflows/krea2_turbo.json"
        )
    graph = json.loads(WORKFLOW.read_text(encoding="utf-8"))

    # Inject prompt + ratio
    # Find ALL CLIPTextEncode nodes — first is positive, second is negative
    clip_nodes = [n for n in graph.values() if n.get("class_type") == "CLIPTextEncode"]
    if clip_nodes:
        clip_nodes[0]["inputs"]["text"] = prompt
    if negative and len(clip_nodes) > 1:
        clip_nodes[1]["inputs"]["text"] = negative

    # Canvas: a profile may declare an exact (width, height) the game requires,
    # which overrides ResolutionSelector so the PNG matches its declared canvas.
    canvas = p.get("canvas")
    latent = _find_node(graph, "EmptyLatentImage")
    if canvas:
        w, h = canvas
        latent["inputs"]["width"] = w
        latent["inputs"]["height"] = h
    else:
        _find_node(graph, "ResolutionSelector")["inputs"]["aspect_ratio"] = ratio or p["ratio"]
        _find_node(graph, "ResolutionSelector")["inputs"]["megapixels"] = p["megapixels"]

    # Background removal. The shipped workflow already has SaveImage pointing at the
    # RMBG node, so merely *not* touching the graph still strips the background — a
    # "keep the background" shot has to rewire SaveImage/PreviewImage back to the
    # raw VAEDecode explicitly. Both directions are therefore wired on purpose.
    use_bg = p["bg"] if bg is None else bg
    rmbg_id = next(
        (nid for nid, n in graph.items() if n.get("class_type") == "RMBG"), None
    )
    vae_id = next(
        (nid for nid, n in graph.items() if n.get("class_type") == "VAEDecode"), None
    )
    save = _find_node(graph, "SaveImage")
    prev = _find_node(graph, "PreviewImage")
    if not use_bg and rmbg_id:
        save["inputs"]["images"] = [rmbg_id, 0]
        prev["inputs"]["images"] = [rmbg_id, 0]
    elif use_bg and vae_id:
        # Keep the scene: bypass RMBG and write the decoded image straight out.
        save["inputs"]["images"] = [vae_id, 0]
        prev["inputs"]["images"] = [vae_id, 0]

    # LoRA assignment
    if loras:
        _assign_loras(graph, loras)

    # Seed
    seed_node = _find_node(graph, "SeedNode")
    if seed_node:
        seed_node["inputs"]["seed"] = seed

    # Submit to ComfyUI
    result = _post(f"{comfy_url}/prompt", {"prompt": graph, "client_id": "chaos-world-gen"})
    prompt_id = result["prompt_id"]
    print(f"[gen] submitted prompt_id={prompt_id}", file=sys.stderr)

    # Poll for completion
    deadline = time.monotonic() + 1800
    while True:
        hist = _get(f"{comfy_url}/history/{prompt_id}")
        if prompt_id in hist:
            entry = hist[prompt_id]
            status = entry.get("status", {})
            if status.get("completed"):
                if status.get("status_str") == "error":
                    raise RuntimeError(f"ComfyUI error: {status.get('messages')}")
                break
        if time.monotonic() > deadline:
            raise TimeoutError("generation did not finish in 30 min")
        time.sleep(2)

    # Download output
    for _nid, node_out in (entry.get("outputs") or {}).items():
        for key in ("images", "gifs", "videos"):
            for media in node_out.get(key) or []:
                params = urllib.parse.urlencode({
                    "filename": media.get("filename", "output"),
                    "subfolder": media.get("subfolder", ""),
                    "type": media.get("type", "output"),
                })
                data = _get_bytes(f"{comfy_url}/view?{params}")
                Path(output).parent.mkdir(parents=True, exist_ok=True)
                with open(output, "wb") as f:
                    f.write(data)
                print(f"[gen] saved {output} ({len(data)} bytes)")
                return output

    raise RuntimeError("no output produced")


def _parse_lora(spec: str) -> tuple[str, float]:
    """Parse 'name=strength' or just 'name' (default 0.8)."""
    if "=" in spec:
        name, strength = spec.rsplit("=", 1)
        return name, float(strength)
    return spec, 0.8


def main() -> None:
    ap = argparse.ArgumentParser(description="Chaos World asset generator")
    ap.add_argument("--list-profiles", action="store_true")
    ap.add_argument("--list-loras", action="store_true")
    ap.add_argument("--list-slots", action="store_true")
    ap.add_argument("--profile", default="portrait")
    ap.add_argument("--prompt")
    ap.add_argument("--output")
    ap.add_argument("--lora", action="append", default=[], help="name=strength (repeatable, in slot order)")
    ap.add_argument("--ratio")
    ap.add_argument("--no-bg", action="store_true")
    ap.add_argument("--bg", action="store_true")
    ap.add_argument("--seed", type=int, default=-1)
    ap.add_argument("--comfy-url", default=COMFY_URL)
    args = ap.parse_args()

    if args.list_profiles:
        list_profiles()
        return
    if args.list_loras:
        list_loras()
        return
    if args.list_slots:
        list_slots()
        return

    if not args.prompt or not args.output:
        ap.error("--prompt and --output are required (or use --list-* flags)")

    loras = [_parse_lora(s) for s in args.lora]
    bg = False if args.no_bg else (True if args.bg else None)
    seed = args.seed if args.seed >= 0 else int(time.time() * 1000) % (2**31)
    generate(
        profile=args.profile,
        prompt=args.prompt,
        output=args.output,
        loras=loras,
        ratio=args.ratio,
        bg=bg,
        seed=seed,
        comfy_url=args.comfy_url,
    )


if __name__ == "__main__":
    main()
