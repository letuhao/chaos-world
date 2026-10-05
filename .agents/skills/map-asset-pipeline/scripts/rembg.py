# -*- coding: utf-8 -*-
"""
ComfyUI AI Background Removal Tool (RMBG-2.0 / WAS Suite)
Part of the Chaos World map-asset-pipeline skill.

Workflow:
1. Validates input image format (enforces PNG for game-ready transparency).
2. Checks if the input already contains a valid alpha channel (transparent background).
   If transparent pixels are present and valid, skips background removal.
3. If opaque (e.g. solid white or key color background), uploads to local ComfyUI instance
   (default http://127.0.0.1:8188) and executes RMBG-2.0 removal.
4. Normalizes canvas padding (16px), resizes to exact target runtime size, aligns pivot,
   and outputs a production-ready RGBA PNG.
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from PIL import Image

COMFY_URL = "http://127.0.0.1:8188"

def has_transparent_background(img: Image.Image, threshold: float = 0.05) -> bool:
    """
    Checks if an image already has an alpha channel with a meaningful amount of transparent pixels.
    threshold: minimum ratio of transparent pixels (alpha < 10) to total pixels.
    """
    if img.mode not in ("RGBA", "LA") and "transparency" not in img.info:
        return False
    
    alpha = img.convert("RGBA").split()[-1]
    his = alpha.histogram()
    transparent_px = sum(his[:10]) # pixels with alpha < 10
    total_px = img.width * img.height
    return (transparent_px / total_px) >= threshold

def upload_image_to_comfy(image_path: Path, comfy_url: str = COMFY_URL) -> str:
    """Uploads an image to ComfyUI's /upload/image endpoint via multipart/form-data."""
    boundary = "----WebKitFormBoundaryChaosWorldRembg"
    mime_type = "image/png" if image_path.suffix.lower() == ".png" else "image/jpeg"
    
    data = []
    data.append(f"--{boundary}".encode())
    data.append(f'Content-Disposition: form-data; name="image"; filename="{image_path.name}"'.encode())
    data.append(f"Content-Type: {mime_type}\r\n".encode())
    data.append(image_path.read_bytes())
    data.append(f"--{boundary}".encode())
    data.append(b'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue')
    data.append(f"--{boundary}--".encode())
    data.append(b"")

    body = b"\r\n".join(data)
    req = urllib.request.Request(
        f"{comfy_url}/upload/image",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
    )
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode())
        return res["name"]

def execute_comfy_rembg(image_path: Path, output_png_path: Path, model: str = "RMBG-2.0", comfy_url: str = COMFY_URL) -> bool:
    """Queues and executes background removal workflow via ComfyUI."""
    uploaded_name = upload_image_to_comfy(image_path, comfy_url)

    graph = {
        "1": {
            "inputs": {"image": uploaded_name, "upload": "image"},
            "class_type": "LoadImage"
        },
        "2": {
            "inputs": {
                "model": model,
                "sensitivity": 0.01,
                "process_res": 1024,
                "mask_blur": 0,
                "mask_offset": 0,
                "invert_output": False,
                "refine_foreground": True,
                "unload_model": False,
                "background": "Alpha",
                "background_color": "#ffffff",
                "image": ["1", 0]
            },
            "class_type": "RMBG"
        },
        "3": {
            "inputs": {
                "filename_prefix": "chaos_world_rembg",
                "images": ["2", 0]
            },
            "class_type": "SaveImage"
        }
    }

    req = urllib.request.Request(
        f"{comfy_url}/prompt",
        data=json.dumps({"prompt": graph}).encode(),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as resp:
        prompt_id = json.loads(resp.read().decode())["prompt_id"]

    for _ in range(60):
        time.sleep(1)
        with urllib.request.urlopen(f"{comfy_url}/history/{prompt_id}") as resp:
            hist = json.loads(resp.read().decode())
            if prompt_id in hist:
                outputs = hist[prompt_id].get("outputs", {})
                if "3" in outputs and "images" in outputs["3"]:
                    saved_img = outputs["3"]["images"][0]
                    subfolder = saved_img.get("subfolder", "")
                    filename = saved_img["filename"]
                    img_url = f"{comfy_url}/view?filename={filename}&subfolder={subfolder}&type=output"
                    with urllib.request.urlopen(img_url) as img_resp:
                        output_png_path.write_bytes(img_resp.read())
                    return True
    raise RuntimeError("ComfyUI RMBG task timed out after 60 seconds")

def normalize_and_save_png(input_rgba: Image.Image, output_path: Path, target_size: tuple[int, int], pivot: str = "bottom_center", margin: int = 16) -> dict:
    """Normalizes padding, scales sprite to target canvas, aligns according to pivot, and saves PNG."""
    bbox = input_rgba.getbbox()
    cropped = input_rgba.crop(bbox) if bbox else input_rgba

    target_w, target_h = target_size
    max_w = target_w - margin * 2
    max_h = target_h - margin * 2

    cw, ch = cropped.size
    scale = min(max_w / cw, max_h / ch)
    new_w = max(1, int(cw * scale))
    new_h = max(1, int(ch * scale))
    resized = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    pos_x = (target_w - new_w) // 2
    if pivot == "bottom_center":
        pos_y = target_h - new_h - margin
    else:  # center
        pos_y = (target_h - new_h) // 2

    canvas.paste(resized, (pos_x, pos_y), resized)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, "PNG", optimize=True)

    # Subcell coverage check (32px subcell on 128px reference tile)
    subcell_size = 32
    cols = target_w // subcell_size
    rows = target_h // subcell_size
    alpha = canvas.split()[-1]
    filled = 0
    total = cols * rows
    for r in range(rows):
        for c in range(cols):
            box = (c * subcell_size, r * subcell_size, (c + 1) * subcell_size, (r + 1) * subcell_size)
            his = alpha.crop(box).histogram()
            if sum(his[128:]) / (subcell_size * subcell_size) > 0.15:
                filled += 1

    return {
        "output_path": str(output_path),
        "canvas_size": list(target_size),
        "pivot": pivot,
        "bounding_box": list(canvas.getbbox()) if canvas.getbbox() else [0, 0, target_w, target_h],
        "subcells_covered": filled,
        "total_subcells": total,
        "coverage_ratio": round(filled / total, 3)
    }

def process_asset(input_path: Path, output_path: Path, target_size: tuple[int, int], pivot: str = "bottom_center", comfy_url: str = COMFY_URL) -> dict:
    """Main pipeline execution for an asset."""
    # Enforce PNG output
    if output_path.suffix.lower() != ".png":
        raise ValueError(f"Output must be a .png file for game-ready transparency! Got: {output_path.name}")

    img = Image.open(input_path)

    # Step 1: Check if already transparent
    if has_transparent_background(img):
        print(f"[{input_path.name}] Already has transparent background. Skipping RMBG.")
        rgba = img.convert("RGBA")
    else:
        print(f"[{input_path.name}] Opaque background detected. Invoking ComfyUI RMBG-2.0...")
        temp_cutout = output_path.parent / f"_temp_rembg_{output_path.stem}.png"
        execute_comfy_rembg(input_path, temp_cutout, comfy_url=comfy_url)
        rgba = Image.open(temp_cutout).convert("RGBA")
        if temp_cutout.exists():
            temp_cutout.unlink()

    # Step 2: Normalize and save
    metrics = normalize_and_save_png(rgba, output_path, target_size, pivot=pivot)
    print(f"[{output_path.name}] Saved PNG ({target_size[0]}x{target_size[1]}), subcells {metrics['subcells_covered']}/{metrics['total_subcells']}.")
    return metrics

def main():
    parser = argparse.ArgumentParser(description="ComfyUI Background Removal and Game Asset PNG Normalizer")
    parser.add_argument("--input", required=True, type=Path, help="Input image file")
    parser.add_argument("--output", required=True, type=Path, help="Target game-ready PNG output path")
    parser.add_argument("--size", nargs=2, type=int, default=[512, 512], help="Target canvas width and height in px (e.g. 512 512)")
    parser.add_argument("--pivot", choices=["center", "bottom_center"], default="bottom_center", help="Pivot alignment")
    parser.add_argument("--comfy-url", default=COMFY_URL, help="ComfyUI base URL")

    args = parser.parse_args()
    try:
        metrics = process_asset(args.input, args.output, tuple(args.size), pivot=args.pivot, comfy_url=args.comfy_url)
        print(json.dumps(metrics, indent=2))
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
