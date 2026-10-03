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

from PIL import Image, ImageDraw, ImageFont

from .common import REPO_ROOT, ToolError

DEFAULT_CHECKPOINT = "Flux1S/originByN0utis_originFluxAnimeV1.safetensors"
DEFAULT_LORA = "flux/gokaygokayFlux-2D-Game-Assets-LoRA.safetensors"
DEFAULT_NEGATIVE = (
    "text, letters, watermark, border, UI, extra objects, duplicate subject, "
    "isometric view, perspective, horizon, photorealism, 3D render, noisy texture"
)
REMBG_COMPARE_MODELS = ("u2netp", "u2net", "silueta", "isnet-general-use", "isnet-anime")
DEFAULT_REMBG_MODEL = "isnet-anime"

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
            "model": DEFAULT_REMBG_MODEL,
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
        f"Environment art signature: {record['environment_theme']} "
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
    if not 0.0 <= args.lora_strength <= 2.0:
        raise ToolError("--lora-strength must be between 0 and 2")
    if any(
        not 0 <= value <= 255
        for value in (
            args.alpha_foreground_threshold,
            args.alpha_background_threshold,
            args.alpha_erode_size,
        )
    ):
        raise ToolError("alpha thresholds and erosion size must be between 0 and 255")
    if args.compare_rembg and record["alpha"] != "transparent":
        raise ToolError("--compare-rembg only applies to transparent map assets")

    seed = args.seed if args.seed >= 0 else secrets.randbelow(2**31)
    prompt = _production_prompt(record, args.prompt)
    graph = copy.deepcopy(WORKFLOW)
    graph["1"]["inputs"]["ckpt_name"] = args.checkpoint
    if args.lora.strip():
        graph["10"] = {
            "inputs": {
                "model": ["1", 0],
                "clip": ["12", 0],
                "lora_name": args.lora.strip(),
                "strength_model": args.lora_strength,
                "strength_clip": args.lora_strength,
            },
            "class_type": "LoraLoader",
        }
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
        post_processing=args.rembg_post_processing,
        alpha_matting=args.alpha_matting,
        alpha_matting_foreground_threshold=args.alpha_foreground_threshold,
        alpha_matting_background_threshold=args.alpha_background_threshold,
        alpha_matting_erode_size=args.alpha_erode_size,
    )

    comparison_nodes: dict[str, str] = {}
    if args.compare_rembg:
        for index, model in enumerate(REMBG_COMPARE_MODELS):
            if model == args.rembg_model:
                continue
            rembg_node = str(16 + index * 2)
            save_node = str(int(rembg_node) + 1)
            inputs = copy.deepcopy(graph["15"]["inputs"])
            inputs["model"] = model
            graph[rembg_node] = {
                "inputs": inputs,
                "class_type": "Image Rembg (Remove Background)",
            }
            graph[save_node] = {
                "inputs": {
                    "filename_prefix": (
                        f"chaos_world_map_compare/{record['id'].replace('.', '_')}-{seed}-{model}"
                    ),
                    "images": [rembg_node, 0],
                },
                "class_type": "SaveImage",
            }
            comparison_nodes[save_node] = model

    model_slug = args.rembg_model.replace("/", "_").replace(" ", "_")
    lora_slug = args.lora.strip().replace("/", "_").replace(" ", "_") or "base"
    lora_slug = f"{lora_slug}-s{args.lora_strength:g}"
    output = (
        REPO_ROOT
        / "build"
        / "map-generated"
        / f"{record['id'].replace('.', '_')}-{seed}-{model_slug}-{lora_slug}.png"
    )
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

    image = _node_image(entry or {}, "7")
    data = _get_bytes(f"{comfy_url}/view?{urllib.parse.urlencode(image)}")
    _write_new_file(output, data)
    print(
        f"[map generate] saved source {output.relative_to(REPO_ROOT).as_posix()} ({len(data)} bytes)"
    )
    comparison_paths = {args.rembg_model: output}
    for node_id, model in comparison_nodes.items():
        image = _node_image(entry or {}, node_id)
        data = _get_bytes(f"{comfy_url}/view?{urllib.parse.urlencode(image)}")
        comparison = (
            REPO_ROOT
            / "build"
            / "map-rembg-comparisons"
            / f"{record['id'].replace('.', '_')}-{seed}-{model}-{lora_slug}.png"
        )
        comparison.parent.mkdir(parents=True, exist_ok=True)
        _write_new_file(comparison, data)
        comparison_paths[model] = comparison
        print(
            f"[map generate] saved {model} comparison "
            f"{comparison.relative_to(REPO_ROOT).as_posix()}"
        )
    if comparison_nodes:
        sheet = _write_comparison_sheet(record, seed, lora_slug, comparison_paths)
        print(
            f"[map generate] wrote remover comparison sheet {sheet.relative_to(REPO_ROOT).as_posix()}"
        )
    return output, prompt, seed


def _node_image(entry: dict, node_id: str) -> dict:
    node_output = (entry.get("outputs") or {}).get(node_id, {})
    for image in node_output.get("images") or []:
        if image.get("filename"):
            return {
                "filename": image["filename"],
                "subfolder": image.get("subfolder", ""),
                "type": image.get("type", "output"),
            }
    raise ToolError(f"ComfyUI completed without returning an image from node {node_id}")


def _write_comparison_sheet(
    record: dict, seed: int, lora_slug: str, images: dict[str, Path]
) -> Path:
    columns = 3
    cell_size = 320
    image_size = 288
    label_height = 24
    models = sorted(images)
    rows = (len(models) + columns - 1) // columns
    sheet = Image.new(
        "RGB", (columns * cell_size, rows * (image_size + label_height)), (36, 39, 43)
    )
    font = ImageFont.load_default()
    checker = Image.new("RGBA", (image_size, image_size), (228, 228, 228, 255))
    checker_draw = ImageDraw.Draw(checker)
    checker_size = 16
    for y in range(0, image_size, checker_size):
        for x in range(0, image_size, checker_size):
            if (x // checker_size + y // checker_size) % 2:
                checker_draw.rectangle(
                    (x, y, x + checker_size - 1, y + checker_size - 1),
                    fill=(190, 190, 190, 255),
                )

    for index, model in enumerate(models):
        with Image.open(images[model]) as opened:
            foreground = opened.convert("RGBA")
        foreground.thumbnail((image_size, image_size), Image.Resampling.LANCZOS)
        preview = checker.copy()
        preview.alpha_composite(
            foreground,
            ((image_size - foreground.width) // 2, (image_size - foreground.height) // 2),
        )
        x = (index % columns) * cell_size + (cell_size - image_size) // 2
        y = (index // columns) * (image_size + label_height)
        sheet.paste(preview.convert("RGB"), (x, y))
        ImageDraw.Draw(sheet).text(
            ((index % columns) * cell_size + 12, y + image_size + 4),
            model,
            fill="white",
            font=font,
        )

    output = (
        REPO_ROOT
        / "build"
        / "map-rembg-comparisons"
        / f"{record['id'].replace('.', '_')}-{seed}-{lora_slug}-contact-sheet.png"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, format="PNG", optimize=True)
    return output


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
