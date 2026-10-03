"""Generate indexed world-map sprites through the local ComfyUI API."""

from __future__ import annotations

import copy
import json
import os
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from .common import REPO_ROOT, ToolError

DEFAULT_CHECKPOINT = "Flux1S/originByN0utis_originFluxAnimeV1.safetensors"
DEFAULT_NEGATIVE = (
    "text, letters, watermark, border, UI, extra objects, duplicate subject, "
    "isometric view, perspective, horizon, photorealism, 3D render, noisy texture"
)

# Adapted from the supplied standalone ComfyUI workflow. Model, prompt, size,
# sampler, steps, guidance, seed, and background-removal model are CLI inputs.
WORKFLOW = {
    "1": {
        "inputs": {"ckpt_name": DEFAULT_CHECKPOINT},
        "class_type": "CheckpointLoaderSimple",
    },
    "2": {
        "inputs": {
            "clip_l": "\n",
            "t5xxl": "POSITIVE_PLACEHOLDER",
            "guidance": 3.5,
            "clip": ["11", 0],
        },
        "class_type": "CLIPTextEncodeFlux",
    },
    "3": {
        "inputs": {
            "clip_l": "NEGATIVE_PLACEHOLDER",
            "t5xxl": "\n",
            "guidance": 3.5,
            "clip": ["11", 0],
        },
        "class_type": "CLIPTextEncodeFlux",
    },
    "4": {
        "inputs": {"width": 1024, "height": 1024, "batch_size": 1},
        "class_type": "EmptyLatentImage",
    },
    "6": {"inputs": {"samples": ["8", 0], "vae": ["13", 0]}, "class_type": "VAEDecode"},
    "7": {
        "inputs": {"filename_prefix": "chaos_world_map", "images": ["15", 0]},
        "class_type": "SaveImage",
    },
    "8": {
        "inputs": {
            "add_noise": "enable",
            "noise_seed": 0,
            "steps": 32,
            "cfg": 1.0,
            "sampler_name": "euler",
            "scheduler": "normal",
            "start_at_step": 0,
            "end_at_step": 10000,
            "return_with_leftover_noise": "disable",
            "model": ["10", 0],
            "positive": ["2", 0],
            "negative": ["3", 0],
            "latent_image": ["4", 0],
        },
        "class_type": "KSamplerAdvanced",
    },
    "10": {
        "inputs": {
            "PowerLoraLoaderHeaderWidget": {"type": "PowerLoraLoaderHeaderWidget"},
            "➕ Add Lora": "",
            "model": ["1", 0],
            "clip": ["12", 0],
        },
        "class_type": "Power Lora Loader (rgthree)",
    },
    "11": {
        "inputs": {"stop_at_clip_layer": -1, "clip": ["10", 1]},
        "class_type": "CLIPSetLastLayer",
    },
    "12": {
        "inputs": {
            "clip_name1": "clip_l.safetensors",
            "clip_name2": "t5xxl_fp8_e4m3fn.safetensors",
            "type": "flux",
            "device": "default",
        },
        "class_type": "DualCLIPLoader",
    },
    "13": {"inputs": {"vae_name": "ae.safetensors"}, "class_type": "VAELoader"},
    "15": {
        "inputs": {
            "transparency": True,
            "model": "u2netp",
            "post_processing": False,
            "only_mask": False,
            "alpha_matting": False,
            "alpha_matting_foreground_threshold": 240,
            "alpha_matting_background_threshold": 10,
            "alpha_matting_erode_size": 10,
            "background_color": "none",
            "images": ["6", 0],
        },
        "class_type": "Image Rembg (Remove Background)",
    },
}


def _production_prompt(record: dict, subject: str) -> str:
    framing = ""
    if record["type"] == "tile":
        framing = "Show a complete square tile viewed straight down. "
        if record["alpha"] == "opaque":
            framing += "Fill the canvas edge to edge and keep it seamlessly repeatable. "
        else:
            framing += "Keep unused areas transparent and make tile edges join cleanly. "
    else:
        framing = "Show one complete isolated object viewed straight down. "
        framing += "Leave clear padding and honor the " + record["pivot"] + " ground pivot. "
        framing += "Use a transparent background. "
    if record["alpha"] == "opaque":
        transparency = "The final image must be fully opaque. "
    else:
        transparency = "The final image must have transparent pixels outside the art. "
    return (
        f"{subject.strip()}\n\n"
        f"Production sprite for Chaos World, a 2D top-down cultivation action RPG. "
        f"Asset: {record['name']} ({record['id']}); environment: "
        f"{record['environment_name']} in the {record['world_tier']}. "
        f"{framing}{transparency}"
        "Straight-down orthographic camera, with no horizon or isometric projection. "
        "Hand-painted gouache, fine dark #263A35 ink contours, broad readable value "
        "planes, material-led colors, restrained surface detail, soft upper-left light. "
        "Keep the silhouette and identifying detail legible at the indexed game size. "
        "No text, labels, UI, frame, watermark, or unrelated objects."
    )


def generate(record: dict, args) -> tuple[Path, str, int]:
    if not 256 <= args.size <= 2048 or args.size % 16:
        raise ToolError("--size must be a multiple of 16 between 256 and 2048")
    if not 1 <= args.steps <= 64:
        raise ToolError("--steps must be between 1 and 64")
    if args.cfg < 0 or args.guidance < 0:
        raise ToolError("--cfg and --guidance must be non-negative")
    if not 1 <= args.timeout <= 900:
        raise ToolError("--timeout must be between 1 and 900 seconds")
    if not args.prompt.strip() or not args.checkpoint.strip() or not args.rembg_model.strip():
        raise ToolError("prompt, checkpoint, and background-removal model must be non-empty")

    seed = args.seed if args.seed >= 0 else secrets.randbelow(2**31)
    prompt = _production_prompt(record, args.prompt)
    graph = copy.deepcopy(WORKFLOW)
    graph["1"]["inputs"]["ckpt_name"] = args.checkpoint
    graph["2"]["inputs"]["t5xxl"] = prompt
    graph["2"]["inputs"]["guidance"] = args.guidance
    graph["3"]["inputs"]["clip_l"] = args.negative
    graph["3"]["inputs"]["guidance"] = args.guidance
    graph["4"]["inputs"].update(width=args.size, height=args.size)
    graph["8"]["inputs"].update(
        noise_seed=seed,
        steps=args.steps,
        cfg=args.cfg,
        sampler_name=args.sampler,
        scheduler=args.scheduler,
    )
    graph["15"]["inputs"].update(
        model=args.rembg_model,
        transparency=record["alpha"] == "transparent",
    )

    output = REPO_ROOT / "build" / "map-generated" / f"{record['id'].replace('.', '_')}-{seed}.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ToolError(f"refusing to overwrite generated source: {output}")

    comfy_url = args.comfy_url.rstrip("/")
    response = _post(f"{comfy_url}/prompt", {"prompt": graph, "client_id": "chaos-world-map"})
    prompt_id = response.get("prompt_id")
    if not prompt_id:
        raise ToolError(f"ComfyUI did not return a prompt_id: {response}")
    print(f"[map generate] submitted prompt_id={prompt_id}")

    deadline = time.monotonic() + args.timeout
    entry = None
    while time.monotonic() < deadline:
        history = _get(f"{comfy_url}/history/{urllib.parse.quote(prompt_id)}")
        entry = history.get(prompt_id)
        if entry:
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise ToolError(f"ComfyUI generation failed: {status.get('messages', status)}")
            if status.get("completed"):
                break
        time.sleep(min(2, max(0, deadline - time.monotonic())))
    else:
        raise ToolError(f"ComfyUI generation exceeded {args.timeout} seconds")

    image = _first_image(entry or {})
    data = _get_bytes(f"{comfy_url}/view?{urllib.parse.urlencode(image)}")
    _write_new_file(output, data)
    print(
        f"[map generate] saved source {output.relative_to(REPO_ROOT).as_posix()} ({len(data)} bytes)"
    )
    return output, prompt, seed


def _first_image(entry: dict) -> dict:
    for node_output in (entry.get("outputs") or {}).values():
        for image in node_output.get("images") or []:
            if image.get("filename"):
                return {
                    "filename": image["filename"],
                    "subfolder": image.get("subfolder", ""),
                    "type": image.get("type", "output"),
                }
    raise ToolError("ComfyUI completed without returning an image")


def _post(url: str, payload: dict) -> dict:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise ToolError(f"ComfyUI HTTP {exc.code}: {details[:1000]}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise ToolError(f"could not reach ComfyUI at {url}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ToolError(f"ComfyUI returned invalid JSON from {url}") from exc


def _get(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise ToolError(f"ComfyUI HTTP {exc.code}: {details[:1000]}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise ToolError(f"could not reach ComfyUI at {url}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ToolError(f"ComfyUI returned invalid JSON from {url}") from exc


def _get_bytes(url: str) -> bytes:
    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        raise ToolError(
            f"ComfyUI image fetch failed with HTTP {exc.code}: {details[:1000]}"
        ) from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise ToolError(f"could not fetch generated image from ComfyUI: {exc}") from exc


def _write_new_file(path: Path, data: bytes) -> None:
    descriptor = None
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            descriptor = None
            output.write(data)
    except FileExistsError as exc:
        raise ToolError(f"refusing to overwrite generated source: {path}") from exc
    except OSError as exc:
        path.unlink(missing_ok=True)
        raise ToolError(f"could not save generated source: {path}: {exc}") from exc
    finally:
        if descriptor is not None:
            os.close(descriptor)
