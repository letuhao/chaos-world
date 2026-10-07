# -*- coding: utf-8 -*-
"""Generator for Medieval Western Pack README.md documenting all 48 categories."""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game/assets/packs/medieval_western"
CATEGORIES_PATH = PACK_DIR / "categories.json"
README_PATH = PACK_DIR / "README.md"


def main():
    with open(CATEGORIES_PATH, "r", encoding="utf-8") as f:
        categories = json.load(f)

    total_assets = sum(c["planned_count"] for c in categories)
    all_subs = [s for c in categories for s in c["sub_categories"]]

    lines = []
    lines.append("# Medieval Western Living World Pack (Lãnh Địa Phong Kiến & Thế Giới Sống Phương Tây)")
    lines.append("*Comprehensive 2D Top-Down World Map Asset Specification for High & Late Medieval European Civilization, Feudal Crossroads, Manorial Supply Chains, Domestic Traces, and Gothic Architecture*")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 1. Overview & Vision: What Makes a Western World Truly 'Living'?")
    lines.append("To transcend a static video-game backdrop and construct an authentic **Living World (Thế Giới Sống Động)**, this pack models the complete physical, social, and ecological reality of Medieval Europe across **7 Life Spheres** and **48 Specialized Categories** totaling **5,600 assets**.")
    lines.append("")
    lines.append("### The 5 Pillars of Medieval Living World Design")
    lines.append("1. **Cultural Crossroads (Giao Lộ Văn Hóa)**: Europe was never a monolithic monoculture. A living world reflects the porous friction of frontiers: Anglo-Norman feudal heartlands, red-brick Hanseatic burgher towns, turf-roofed Nordic coastal havens, Moorish arcaded patios in Al-Andalus, Slavic taiga logcraft, Celtic highland crannogs, and Byzantine/Crusader outposts.")
    lines.append("2. **Complete Supply Chains (Chuỗi Cung Ứng Khép Kín)**: Every loaf of rye bread and iron horseshoe has an origin. The world contains full physical infrastructure: strip-farmed fields, scythes, ox-plows, threshing barns, water/wind mills, miller hoppers, bakeries, sheep folds, wool shears, dye vats, weavers' looms, bloomery iron furnaces, charcoal hearths, and blacksmith anvils.")
    lines.append("3. **Intimate Traces of Daily Domesticity (Dấu Vết Đời Sống Thường Nhật)**: True life is found in what people leave behind: steaming manure middens behind pigsties, linen washing lines drying in breezes, hearth ash heaps, chopping blocks with lodged iron axes, puddle ruts carved by wooden cartwheels, and herb gardens drying sprigs of thyme.")
    lines.append("4. **Micro-Fauna, Pests & Ecological Sub-layers (Hệ Sinh Thái & Sinh Vật Vi Mô)**: Pigeons roosting on cathedral spires, rats rummaging grain sacks, magpies perched on gallows, barn swallow nests beneath timber eaves, frogs in fen bogs, and rooting semi-wild swine in beech woods.")
    lines.append("5. **Feudal & Spiritual Social Tensions (Xung Đột Xã Hội & Đức Tin)**: The visual dialogue between serf hovels of wattle-and-daub huddled beneath monumental limestone cathedrals; tithe barns taking grain from hungry peasants; gibbets outside city gates; plague quarantine crosses; and rogue forest outlaws hiding beyond the sheriff's reach.")
    lines.append("")
    lines.append("### Technical Specifications")
    lines.append(f"* **Total Categories**: **{len(categories)} Categories** across **7 Life Spheres**")
    lines.append(f"* **Total Asset Target**: **{total_assets:,} assets**")
    lines.append(f"* **Total Subcategories**: **{len(all_subs)} distinct subcategories**")
    lines.append("* **Standard Reference Tile**: 128x128 px")
    lines.append("* **Sub-cell Collision Unit**: 32x32 px (4x4 subcells per tile)")
    lines.append("* **Camera & Viewport**: Orthographic top-down (~45° projection for vertical buildings, foliage, and props; 90° overhead plan for terrain surfaces, pavements, and ground decals).")
    lines.append("* **Art Style**: Gouache hand-painted anime style with dark ink contour lines (`#263A35`), grounded historical medieval European palette, upper-left directional daylight (315°).")
    lines.append("* **Color Palette**:")
    lines.append("  * *Stone & Masonry*: Ashlar limestone grey (`#8A8D8F`), aged mortar cream (`#DFD7C6`), dark Welsh slate (`#4A5568`), river cobblestone (`#5A6065`), Hanseatic red brick (`#8A3324`).")
    lines.append("  * *Timber & Thatch*: Aged English oak timber (`#5C4033`), weathered chestnut (`#785338`), golden thatch straw (`#C7A75C`), whitewashed wattle-and-daub (`#EFE6D5`).")
    lines.append("  * *Heraldic & Court*: Royal heraldic vermilion (`#9B2C2C`), French royal azure (`#2B6CB0`), knightly lion gold (`#D69E2E`), liturgical bishop purple (`#553C9A`), iron soot black (`#2D3748`).")
    lines.append("  * *Nature & Ecology*: Primeval oak moss green (`#4A5D3E`), damp peat bog brown (`#3D3028`), highland heather purple (`#6B4668`), autumn beech leaf russet (`#A0522D`).")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 2. Category Architecture by Life Sphere")
    lines.append("")

    spheres = {}
    for c in categories:
        spheres.setdefault(c["sphere"], []).append(c)

    sphere_numerals = {
        "Cultural Crossroads": "I",
        "Built Architecture": "II",
        "Faith & Mortality": "III",
        "Manorial Supply Chains": "IV",
        "Commerce & Urban Life": "V",
        "War & Underworld": "VI",
        "Ecology & Living Traces": "VII"
    }

    sphere_vns = {
        "Cultural Crossroads": "Giao Lộ Văn Hóa Phương Tây",
        "Built Architecture": "Kiến Trúc Định Cư & Công Sự",
        "Faith & Mortality": "Đức Tin, Tu Viện, Sinh Tử & Huyền Thuật",
        "Manorial Supply Chains": "Chuỗi Cung Ứng Điền Trang & Phường Hội",
        "Commerce & Urban Life": "Thương Nghiệp, Đô Thị & Cảng Biển",
        "War & Underworld": "Chiến Tranh, Công Thành, Tội Phạm & Ngục Tối",
        "Ecology & Living Traces": "Tự Nhiên, Dấu Vết Sống, Sinh Thái & Cư Dân"
    }

    cat_idx = 1
    for s_name, cats in spheres.items():
        s_num = sphere_numerals.get(s_name, "")
        s_vn = sphere_vns.get(s_name, "")
        s_total = sum(c["planned_count"] for c in cats)
        lines.append(f"### Sphere {s_num}: {s_name} ({s_vn}) — {len(cats)} Categories, {s_total} Assets")
        lines.append("")
        lines.append("| # | Category ID | Name (English / Vietnamese) | Budget | Sub-categories | Gameplay & Culture Hooks |")
        lines.append("|---|---|---|:---:|---|---|")

        for c in cats:
            cid = c["id"]
            name = c["name"]
            vn = c["vietnamese_name"]
            budget = c["planned_count"]
            subs = "<br>• ".join(["• " + s.replace("_", " ").title() for s in c["sub_categories"]])
            hooks = "<br>".join([f"**{k}**: {v}" for k, v in c.get("gameplay_gap_hooks", {}).items() if not isinstance(v, dict)])
            if not hooks:
                hooks = "Standard simulation hook"
            lines.append(f"| **{cat_idx}** | `{cid}` | **{name}**<br>*{vn}* | **{budget}** | {subs} | {hooks} |")
            cat_idx += 1

        lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("## 3. Comprehensive Category Summary Matrix")
    lines.append("")
    lines.append("| Life Sphere | Category Count | Asset Target | Key Physical & Gameplay Focus |")
    lines.append("|---|:---:|:---:|---|")
    for s_name, cats in spheres.items():
        s_num = sphere_numerals.get(s_name, "")
        s_vn = sphere_vns.get(s_name, "")
        s_total = sum(c["planned_count"] for c in cats)
        lines.append(f"| **Sphere {s_num}: {s_name}** (*{s_vn}*) | **{len(cats)}** | **{s_total}** | {cats[0]['name']}, {cats[1]['name']} et al. |")
    lines.append(f"| **TOTAL LIVING WORLD MATRIX** | **{len(categories)}** | **{total_assets:,}** | **Complete Medieval Western Feudal & Chivalric Simulation Matrix** |")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 4. Modular Construction Kits")
    lines.append("")
    lines.append("### 4.1 Concentric Stone Castle Kit (`castles_curtain_walls_and_bastions`: 180 Assets)")
    lines.append("* **Foundation & Talus Batter**: Sloped ashlar limestone bases preventing siege sapping; 128 px unit modularity.")
    lines.append("* **Curtain Walls**: Straight wall bays (1x1, 2x1, 3x1), crenellated wall walks with murder-hole corbels and timber hoardings.")
    lines.append("* **Defensive Towers**: Round drum towers (2x2), D-shaped mural bastions (2x2), square Norman keeps (3x3, 4x4), corbelled bartizans (1x1).")
    lines.append("* **Gatehouses & Portcullises**: Heavy double-drum barbicans, iron-banded drawbridge pivot mechanisms, and murder holes.")
    lines.append("")
    lines.append("### 4.2 Modular Timber-Frame Fachwerk Kit (`modular_timber_frame_fachwerk`: 160 Assets)")
    lines.append("* **Dwarf Stone Footings**: Rubble masonry plinths elevating load-bearing cruck timber timbers above mud.")
    lines.append("* **Cruck Timber Framing**: Heavy oak posts, mortise-and-tenon joints, St. Andrew's cross bracings, and cantilevered upper-storey jetties.")
    lines.append("* **Wall Infills**: Whitewashed wattle-and-daub, herringbone red brick nogging, and diamond leaded glass windows.")
    lines.append("* **Roof Systems**: Thatch bundles, terracotta plain tiles, and blue Welsh slates with carved dragon/gargoyle bargeboards.")
    lines.append("")
    lines.append("### 4.3 Gothic Cathedral & Cloister Kit (`gothic_cathedrals_and_monumental_abbeys`: 140 Assets)")
    lines.append("* **Skeletal Stonework**: Flying buttresses, ribbed quadripartite vault piers, pointed lancet windows, and high rose tracery.")
    lines.append("* **Monastic Cloister Arcades**: Quadrangle open-arcaded walks with central garth well, lavatorium stone basins, and stone scriptorium desks.")
    lines.append("")
    lines.append("### 4.4 Manorial Supply Chain Kit (`grain_agriculture_and_harvesting` + `pastoralism_livestock_and_dairy`: 260 Assets)")
    lines.append("* **Arable Strips & Harvesting**: Ridge-and-furrow wheat strips, heavy wheeled moldboard plows, scythes, stooks of grain, and thatched threshing barns.")
    lines.append("* **Pastoralism & Dairy**: Wattle hurdle sheep pens, shearing trestles, milk pails, butter churns, and aging cheese wheel racks.")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 5. Technical Generation Pipeline & Verification")
    lines.append("* **Approved Checkpoint**: `krea2/raySemiReal_krea2TurboV1Nsfw.safetensors`")
    lines.append("* **LoRA**: `krea2/Scottie__Krea2.safetensors` (Weight 1.0, Node 917)")
    lines.append("* **Sampler**: `euler_ancestral`, Scheduler: `beta`, Steps: 8, CFG: 1.0")
    lines.append("* **Alpha Cutout**: `RMBG-2.0` high-precision semantic background removal ensuring clean ink contours without halos.")
    lines.append("* **Asset Directory Architecture**:")
    lines.append("  * `runtime/<category_id>/`: Game-ready `.png` textures and Godot `.import` cache files.")
    lines.append("  * `data/<category_id>/`: Individual asset metadata (`.json`) with collision subcells, footprints, and interaction hooks.")
    lines.append("  * `original/<category_id>/`: Uncompressed raw generation outputs before alpha extraction.")
    lines.append("")

    with open(README_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"Successfully generated {README_PATH} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
