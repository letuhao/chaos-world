"""Shared helpers and data structures for Medieval Western 48-Category Scaffolding."""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game/assets/packs/medieval_western"
CATEGORIES_PATH = PACK_DIR / "categories.json"


def load_categories() -> list[dict]:
    with open(CATEGORIES_PATH, encoding="utf-8") as f:
        return json.load(f)


def get_category_by_id(cat_id: str) -> dict:
    cats = load_categories()
    for c in cats:
        if c["id"] == cat_id:
            return c
    raise ValueError(f"Category '{cat_id}' not found in categories.json")


def make_asset(
    cat_id: str,
    slug: str,
    name: str,
    vn_name: str,
    sub_cat: str,
    footprint: list[int],
    collision: str,
    blocks_proj: bool,
    vision: str,
    verb: str | None,
    role: str,
    destructible: bool,
    material: str,
    culture: str,
    prompt: str,
    asset_type: str = "prop",
    alpha: str = "cutout",
    pivot: str = "bottom_center",
    hooks: dict | None = None,
) -> dict:
    return {
        "id": f"medieval_western.{cat_id}.{slug}",
        "name": name,
        "vietnamese_name": vn_name,
        "category": cat_id,
        "sub_category": sub_cat,
        "type": asset_type,
        "alpha": alpha,
        "pivot": pivot,
        "footprint_cells": footprint,
        "canvas_px": [footprint[0] * 128, footprint[1] * 128],
        "collision_type": collision,
        "blocks_projectile": blocks_proj,
        "vision_mode": vision,
        "interactive_verb": verb,
        "gameplay_role": role,
        "destructible": destructible,
        "material": material,
        "feudal_culture": culture,
        "prompt_summary": prompt,
        "racial_faction": "western_human_kingdom",
        "environment_name": "Medieval Western Feudal World (Lãnh Địa Phong Kiến Tây Âu)",
        "environment_theme": (
            "2D Orthographic top-down, gouache hand-painted, ink contour lines (#263A35), "
            "grounded European medieval palette."
        ),
        "world_tier": "Western Feudal Realm (Trung Cổ Phương Tây)",
        "status": "planned",
        "reference_ids": ["docs/art-direction.md#top-down-world-map"],
        "source": (
            "ComfyUI local unet: krea2/raySemiReal_krea2TurboV1Nsfw.safetensors, "
            "lora: krea2/Scottie__Krea2.safetensors (1.0)"
        ),
        "license": "Generated locally; source checkpoint license terms apply",
        "gameplay_gap_hooks": hooks or {},
    }
