# -*- coding: utf-8 -*-
"""Scaffolding script to generate Ancient Chinese Low-Realm Cultivation pack.

Parses the 344-category master taxonomy from low_realm_cultivation_taxonomy.md,
covers the full 9 Mortal Realms ladder (Qi Refining -> Tribulation Crossing),
creates pack structure, categories.json, ancient_china_low_cultivation_pack.json,
and registers the pack in game/assets/packs/index.json.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
MD_PATH = Path(
    r"C:\Users\NeneScarlet\.gemini\antigravity-ide\brain\7a8e638b-79b7-4ad0-9075-e3c4c3594f07\low_realm_cultivation_taxonomy.md"
)
PACK_DIR = REPO_ROOT / "game/assets/packs/ancient_china_low_cultivation"
PACK_PATH = PACK_DIR / "ancient_china_low_cultivation_pack.json"
CATEGORIES_PATH = PACK_DIR / "categories.json"
INDEX_PATH = REPO_ROOT / "game/assets/packs/index.json"

DOMAIN_MAP = {
    "Domain 1": ("terrain_and_geology", "Terrains & Geological Formations", "Địa Hình & Thổ Nhưỡng"),
    "Domain 2": ("flora_and_spirit_plants", "Natural Flora & Spiritual Plants", "Linh Thảo & Tiên Mộc"),
    "Domain 3": ("water_and_springs", "Water Systems & Spiritual Springs", "Thủy Hệ & Linh Tuyền"),
    "Domain 4": ("hazards_and_phenomena", "Environmental Hazards & Phenomena", "Khí Hậu & Dị Tượng"),
    "Domain 5": ("mortal_and_jianghu", "Mortal Settlements & Jianghu", "Phàm Nhân Thôn Trấn & Giang Hồ"),
    "Domain 6": ("sect_facilities_and_dwellings", "Cultivation Sect Facilities & Dwellings", "Tông Môn Cơ Sở & Động Phủ"),
    "Domain 7": ("religious_sanctuaries", "Daoist, Buddhist & Folk Religious Sites", "Đạo Quán, Phật Tự & Dân Gian Miếu"),
    "Domain 8": ("crypts_tombs_and_ruins", "Crypts, Tombs & Ancient Ruins", "Cổ Mộ & Di Tích"),
    "Domain 9": ("fauna_and_spirit_beasts", "Low-Realm Fauna & Spirit Beasts", "Yêu Thú, Linh Thú & Sơn Hải Kinh"),
    "Domain 10": ("artifacts_and_paraphernalia", "Cultivation Artifacts & Paraphernalia", "Pháp Bảo, Trận Pháp & Khí Cụ"),
    "Domain 11": ("evil_sects_and_demonic", "Evil Sects & Demonic Cultivation", "Ma Đạo Tông Môn & Tà Tu"),
    "Domain 12": ("mining_and_metallurgy", "Mining, Metallurgy & Mineral Extraction", "Khai Khoáng & Luyện Kim"),
    "Domain 13": ("races_and_tribal_enclaves", "Non-Human Races, Bloodlines & Enclaves", "Dị Tộc, Yêu Tộc & Huyết Mạch"),
    "Domain 14": ("floating_terrains_and_sky_crags", "Floating Terrains & Celestial Sky Crags", "Huyền Không Phù Đảo"),
    "Domain 15": ("underwater_and_abyssal_realms", "Underwater Realms & Dragon Palaces", "Thủy Hạ Thế Giới & Thủy Cung"),
    "Domain 16": ("underground_abyss_and_caverns", "Underground Abyss & Subterranean Depths", "Địa Hạ Thế Giới & Cửu U"),
    "Domain 17": ("peak_mortal_and_tribulation", "Peak Mortal Sects & Tribulation Platforms", "Đỉnh Phong Tông Môn & Độ Kiếp Đài"),
}


def slugify(text: str) -> str:
    cleaned = re.sub(r"[^\w\s-]", "", text.lower())
    return re.sub(r"[-\s]+", "_", cleaned).strip("_")


def parse_taxonomy() -> list[dict]:
    content = MD_PATH.read_text(encoding="utf-8")
    lines = content.splitlines()

    categories = []
    current_domain_id = ""
    current_domain_name = ""
    current_domain_vn = ""

    domain_header_re = re.compile(r"^##\s+(Domain\s+\d+):\s+(.*?)\s+—\s+(\d+)\s+Categories")

    for line in lines:
        dom_match = domain_header_re.match(line)
        if dom_match:
            dom_key = dom_match.group(1)
            if dom_key in DOMAIN_MAP:
                current_domain_id, current_domain_name, current_domain_vn = DOMAIN_MAP[dom_key]
            continue

        if line.startswith("|") and not line.startswith("| ID") and not line.startswith("|---"):
            parts = [p.strip() for p in line.split("|")[1:-1]]
            if len(parts) >= 6:
                cat_id, eng_name, hanzi, vn_name, desc, gameplay_type = parts[:6]
                if not cat_id or cat_id.startswith("---") or cat_id == "ID":
                    continue

                slug = f"{slugify(cat_id.replace('-', '_'))}_{slugify(eng_name)}"

                categories.append({
                    "id": slug,
                    "code": cat_id,
                    "domain_id": current_domain_id,
                    "domain_name": current_domain_name,
                    "domain_vietnamese_name": current_domain_vn,
                    "name": eng_name,
                    "hanzi": hanzi,
                    "vietnamese_name": vn_name,
                    "description": desc,
                    "gameplay_and_asset_type": gameplay_type,
                    "planned_count": 10,
                })

    return categories


def main():
    print(f"Reading taxonomy from {MD_PATH}...")
    categories = parse_taxonomy()
    print(f"Parsed {len(categories)} categories across 17 domains.")

    PACK_DIR.mkdir(parents=True, exist_ok=True)
    (PACK_DIR / "data").mkdir(parents=True, exist_ok=True)
    (PACK_DIR / "original").mkdir(parents=True, exist_ok=True)
    (PACK_DIR / "runtime").mkdir(parents=True, exist_ok=True)

    # 1. Save categories.json
    with open(CATEGORIES_PATH, "w", encoding="utf-8") as f:
        json.dump(categories, f, ensure_ascii=False, indent=2)
    print(f"Saved {CATEGORIES_PATH}")

    # 2. Save pack manifest ancient_china_low_cultivation_pack.json
    pack_manifest = {
        "pack_id": "ancient_china_low_cultivation",
        "pack_name": "Ancient Chinese Mortal World Cultivation: Cửu Châu Tiên Lộ (9 Phàm Giới)",
        "vietnamese_title": "Gói Tài Nguyên Thế Giới: Phàm Giới Tu Tiên Cửu Cảnh (Luyện Khí -> Độ Kiếp)",
        "hanzi_title": "九州凡界·九重天阶修真资源包 (练气至渡劫)",
        "version": "1.1.0",
        "world_tier": "Mortal World (Phàm Nhân Giới / Cửu Châu — 9 Realms)",
        "mortal_ladder_coverage": [
            "1. Qi Refining (Luyện Khí / 练气)",
            "2. Foundation Establishment (Trúc Cơ / 筑基)",
            "3. Core Formation (Kết Đan / 结丹)",
            "4. Nascent Soul (Nguyên Anh / 元婴)",
            "5. Spirit Transformation (Hóa Thần / 化神)",
            "6. Void Refinement (Luyện Hư / 炼虚)",
            "7. Body Integration (Hợp Thể / 合体)",
            "8. Great Ascension (Đại Thừa / 大乘)",
            "9. Tribulation Crossing (Độ Kiếp / 渡劫)",
        ],
        "reference_unit_px": 128,
        "subcell_unit_px": 32,
        "art_style": "2D Orthographic top-down (~45 degrees), gouache hand-painted, ink contour lines (#263A35), spiritual misty palette (celadon jade #7A9A8B, spirit spring azure #4A7A8C, vermilion cinnabar #A8382B, weathered pine #5A4838, loess ochre #B88648, abyssal obsidian #20242B, ghost green phosphorus #4FA882).",
        "approved_generation_recipe": {
            "unet_checkpoint": "krea2/raySemiReal_krea2TurboV1Nsfw.safetensors",
            "primary_lora": "krea2/Scottie__Krea2.safetensors",
            "primary_lora_node": "917",
            "primary_lora_weight": 1.0,
            "sampler": "euler_ancestral",
            "scheduler": "beta",
            "steps": 8,
            "cfg": 1.0,
            "rembg_model": "RMBG-2.0",
        },
        "supported_gameplay_modes": [
            "Mortal World 9-Realm Cultivation Progression (Qi Refining -> Tribulation Crossing)",
            "Orthodox & Evil Sect Warfare (Righteous Sects vs Corpse Yin, Blood Demon, Myriad Gu)",
            "Mining, Smelting & Metallurgy Economy (Deep Spirit Stone Shafts, Marrow Jade, Stamping Mills)",
            "Multi-Species Enclaves & Bloodlines (Stoneborn, Emberblood, Tidecaller, Fox, Wood Spirit, Asura)",
            "Aerial & Floating Terrain Traversal (Sky Islands, Iron Chain Bridges, Heavenly Wind)",
            "Subaquatic Exploration (Sunken Dragon Palaces, Coral Groves, Abyssal Trenches)",
            "Subterranean Cavern Depths (Bioluminescent Fungi, Magma Rivers, Nether Black Waters)",
            "Peak Mortal Sects, Grand Formations & Heavenly Tribulation Ascension Platforms",
        ],
        "total_categories": len(categories),
        "total_assets": 0,
        "planned_total_assets": len(categories) * 10,
        "categories": categories,
        "assets": [],
    }

    with open(PACK_PATH, "w", encoding="utf-8") as f:
        json.dump(pack_manifest, f, ensure_ascii=False, indent=2)
    print(f"Saved {PACK_PATH}")

    # 3. Create README.md
    readme_content = f"""# Ancient Chinese Mortal World Cultivation Asset Pack
**ID**: `ancient_china_low_cultivation`  
**World Tier**: Mortal World (Phàm Nhân Giới / Cửu Châu) — Full 9 Realms Ladder (Qi Refining -> Tribulation Crossing)  
**Total Categories**: {len(categories)} across 17 Macro-Domains  

## The 9 Mortal Realms in Chaos World
1. **Qi Refining** (Luyện Khí / 练气)
2. **Foundation Establishment** (Trúc Cơ / 筑基)
3. **Core Formation** (Kết Đan / 结丹)
4. **Nascent Soul** (Nguyên Anh / 元婴)
5. **Spirit Transformation** (Hóa Thần / 化神)
6. **Void Refinement** (Luyện Hư / 炼虚)
7. **Body Integration** (Hợp Thể / 合体)
8. **Great Ascension** (Đại Thừa / 大乘)
9. **Tribulation Crossing** (Độ Kiếp / 渡劫)

## Complete Macro-Domains (17 Domains)
1. **Terrains & Geological Formations** (`terrain_and_geology`): Loess plateaus, karst peaks, Danxia red crags, bone earth.
2. **Natural Flora & Spiritual Plants** (`flora_and_spirit_plants`): Iron bamboo, dragon-coil pines, blood ginseng, peach wood.
3. **Water Systems & Springs** (`water_and_springs`): Mountain brooks, low-grade spirit springs, frigid Yin pools, mortal canals.
4. **Environmental Hazards & Phenomena** (`hazards_and_phenomena`): Five-poison miasmas, cloud seas, ghost mist, lightning zones.
5. **Mortal Settlements & Jianghu** (`mortal_and_jianghu`): Thatched cottages, magistrate courts, inns, escort agencies, martial halls.
6. **Cultivation Sect Facilities & Dwellings** (`sect_facilities_and_dwellings`): Sect gates, barracks, pill rooms, forge halls, Dongfu.
7. **Daoist, Buddhist & Folk Religious Sites** (`religious_sanctuaries`): Mountain hermitages, Maoshan altars, relic pagodas, Earth God shrines.
8. **Crypts, Tombs & Ancient Ruins** (`crypts_tombs_and_ruins`): Tumulus tombs, terracotta pits, mercury trenches, hanging coffins.
9. **Low-Realm Fauna & Spirit Beasts** (`fauna_and_spirit_beasts`): Spirit wolves, iron hawks, cave pythons, Jiangshi zombies, Shan Hai Jing beasts.
10. **Cultivation Artifacts & Paraphernalia** (`artifacts_and_paraphernalia`): Wind-skiffs, cauldrons, flying swords, paper talismans, Bagua mirrors.
11. **Evil Sects & Demonic Cultivation** (`evil_sects_and_demonic`): Corpse Yin pits, Ten Thousand Soul banners, blood demon altars, bone thrones, Gu pits.
12. **Mining, Metallurgy & Mineral Extraction** (`mining_and_metallurgy`): Deep shafts, timber shoring, ore carts, stamping mills, blast furnaces, jade geodes.
13. **Non-Human Races, Bloodlines & Enclaves** (`races_and_tribal_enclaves`): Stoneborn, Emberblood, Tidecaller merfolk, Fox clan, Wood spirits, Asura.
14. **Floating Terrains & Celestial Sky Crags** (`floating_terrains_and_sky_crags`): Floating islands, iron chain sky-bridges, cloud waterfalls, magnetic peaks.
15. **Underwater Realms & Dragon Palaces** (`underwater_and_abyssal_realms`): Crystal dragon palaces, fluorescent coral forests, abyssal trenches, air bubbles.
16. **Underground Abyss & Subterranean Depths** (`underground_abyss_and_caverns`): Giant mushroom caverns, stalactite forests, magma rivers, nether lakes.
17. **Peak Mortal Sects & Tribulation Platforms** (`peak_mortal_and_tribulation`): Elder seclusion grottos, Nine-Heaven tribulation platforms, grand sect arrays.
"""
    readme_path = PACK_DIR / "README.md"
    readme_path.write_text(readme_content, encoding="utf-8")
    print(f"Saved {readme_path}")

    # 4. Register in index.json if present
    if INDEX_PATH.exists():
        try:
            with open(INDEX_PATH, "r", encoding="utf-8") as f:
                index_data = json.load(f)
            packs = index_data.get("packs", [])
            existing_ids = {p.get("pack_id") for p in packs}
            if "ancient_china_low_cultivation" not in existing_ids:
                packs.append({
                    "pack_id": "ancient_china_low_cultivation",
                    "asset_count": 0,
                    "has_manifest": True,
                })
                index_data["total_packs"] = len(packs)
                with open(INDEX_PATH, "w", encoding="utf-8") as f:
                    json.dump(index_data, f, ensure_ascii=False, indent=2)
                print(f"Registered pack in {INDEX_PATH}")
            else:
                print(f"Pack already registered in {INDEX_PATH}")
        except Exception as e:
            print(f"Warning: could not update {INDEX_PATH}: {e}")

    print("\nPack scaffolding complete!")


if __name__ == "__main__":
    main()
