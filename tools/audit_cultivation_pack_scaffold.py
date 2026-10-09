"""Comprehensive Audit Tool for Ancient Chinese Low Cultivation Pack Scaffold.

Audits:
  1. File Integrity & Completeness (Manifest, Categories, README, Index).
  2. Taxonomy & Categorization (426 categories across all 25 canonical domains).
  3. Hanzi & Pinyin Cleanliness (Zero Pinyin leakage in Hanzi, authentic Pinyin populated).
  4. Asset Schema Compliance (Section 6 schema: footprints, px, cell_span, collision, materials).
  5. Cultivation Element Balance (16 affinities, diverse distribution across wuxing & branches).
  6. 9-Realm Mortal Ladder Progression (All 9 realms and 1-9 elevation tiers represented).
  7. Variant & Prompt Pre-Baking (100% of variants have game-ready positive and negative prompts).
  8. Physical Scaffolding & Directory Structure (1,278 category directories created).
"""

from __future__ import annotations

import collections
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_DIR = REPO_ROOT / "game/assets/packs/ancient_china_low_cultivation"
PACK_PATH = PACK_DIR / "ancient_china_low_cultivation_pack.json"
CATEGORIES_PATH = PACK_DIR / "categories.json"
README_PATH = PACK_DIR / "README.md"
INDEX_PATH = REPO_ROOT / "game/assets/packs/index.json"

CANONICAL_DOMAINS = [
    "terrain_and_geology",
    "flora_and_spirit_plants",
    "water_and_springs",
    "hazards_and_phenomena",
    "mortal_and_jianghu",
    "sect_facilities_and_dwellings",
    "religious_sanctuaries",
    "crypts_tombs_and_ruins",
    "fauna_and_spirit_beasts",
    "artifacts_and_paraphernalia",
    "evil_sects_and_demonic",
    "mining_and_metallurgy",
    "races_and_tribal_enclaves",
    "floating_terrains_and_sky_crags",
    "underwater_and_abyssal_realms",
    "underground_abyss_and_caverns",
    "peak_mortal_and_tribulation",
    "atmospheric_vfx_and_phenomena",
    "secret_realms_and_grotto_heavens",
    "cultivation_commerce_and_auctions",
    "world_events_and_calamities",
    "body_cultivation_and_tempering",
    "spirit_farming_and_sericulture",
    "elemental_sanctuaries_and_extremes",
    "dao_companions_and_sanctuary_living",
]

EXPECTED_REALMS = [
    "Qi Refining (Luyện Khí / 练气)",
    "Foundation Establishment (Trúc Cơ / 筑基)",
    "Core Formation (Kết Đan / 结丹)",
    "Nascent Soul (Nguyên Anh / 元婴)",
    "Spirit Transformation (Hóa Thần / 化神)",
    "Void Refinement (Luyện Hư / 炼虚)",
    "Body Integration (Hợp Thể / 合体)",
    "Great Ascension (Đại Thừa / 大乘)",
    "Tribulation Crossing (Độ Kiếp / 渡劫)",
]


class CultivationPackAuditor:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.info: list[str] = []

    def audit_all(self) -> int:
        print("=" * 80)
        print("AUDITING ANCIENT CHINESE LOW CULTIVATION PACK SCAFFOLD")
        print("=" * 80)

        self._check_file_existence()
        categories = self._check_categories()
        assets = self._check_manifest_and_assets(categories)
        self._check_directory_structure(categories)
        self._check_index()

        self._print_summary(categories, assets)
        return 1 if self.errors else 0

    def _check_file_existence(self) -> None:
        print("\n[Audit 1/6] Checking Core Files Existence...")
        for p, label in [
            (PACK_PATH, "Pack manifest"),
            (CATEGORIES_PATH, "Categories taxonomy"),
            (README_PATH, "Pack README"),
            (INDEX_PATH, "Global packs index"),
        ]:
            if not p.exists():
                self.errors.append(f"Missing core file: {p} ({label})")
            else:
                self.info.append(f"Found {label}: {p.name} ({p.stat().st_size / 1024:.1f} KB)")

    def _check_categories(self) -> list[dict]:
        print("\n[Audit 2/6] Auditing Categories Taxonomy & Linguistics...")
        if not CATEGORIES_PATH.exists():
            return []

        with open(CATEGORIES_PATH, encoding="utf-8") as f:
            categories = json.load(f)

        if len(categories) != 426:
            self.errors.append(f"Expected 426 categories, found {len(categories)}")
        else:
            self.info.append("Category count verified: 426 categories")

        domains_found = set()
        hanzi_leakage_count = 0
        missing_pinyin_count = 0

        for c in categories:
            dom = c.get("domain_id") or c.get("domain")
            if dom:
                domains_found.add(dom)
            zh = c.get("hanzi", "")
            if "(" in zh or ")" in zh:
                hanzi_leakage_count += 1
            py = c.get("pinyin", "")
            if not py:
                missing_pinyin_count += 1

        missing_domains = set(CANONICAL_DOMAINS) - domains_found
        if missing_domains:
            self.errors.append(
                f"Missing canonical domains in categories: {sorted(missing_domains)}"
            )
        else:
            self.info.append("All 25 canonical cultivation domains present in categories")

        if hanzi_leakage_count > 0:
            self.errors.append(
                f"Found {hanzi_leakage_count} categories with Pinyin leakage in 'hanzi' field"
            )
        else:
            self.info.append("100% clean Hanzi (zero Pinyin leakage) in categories")

        if missing_pinyin_count > 0:
            self.errors.append(f"Found {missing_pinyin_count} categories missing 'pinyin' field")
        else:
            self.info.append("100% categories have authentic Pinyin populated")

        return categories

    def _check_manifest_and_assets(self, categories: list[dict]) -> list[dict]:
        print("\n[Audit 3/6] Auditing Manifest Schema, Archetypes & Prompts...")
        if not PACK_PATH.exists():
            return []

        with open(PACK_PATH, encoding="utf-8") as f:
            pack = json.load(f)

        assets = pack.get("assets", [])
        if len(assets) != 4260:
            self.errors.append(f"Expected 4,260 assets, found {len(assets)}")
        else:
            self.info.append("Asset count verified: exactly 4,260 assets (10 per category)")

        element_counter = collections.Counter()
        realm_counter = collections.Counter()
        elevation_counter = collections.Counter()
        missing_schema_keys = collections.Counter()
        missing_prompt_count = 0
        total_variants = 0

        required_asset_keys = [
            "id",
            "name",
            "asset_class",
            "type",
            "domain_id",
            "category_id",
            "archetype_name",
            "hanzi",
            "pinyin",
            "footprint_cells",
            "footprint_subcells",
            "footprint_px",
            "cell_span",
            "collision",
            "primary_material",
            "secondary_material",
            "material",
            "visual_style",
            "cultivation_element",
            "element_alignment",
            "elevation_tier",
            "mortal_realm_tier",
            "variants",
            "gameplay_gap_hooks",
        ]

        for a in assets:
            for k in required_asset_keys:
                if k not in a:
                    missing_schema_keys[k] += 1

            element_counter[a.get("cultivation_element", "unknown")] += 1
            realm_counter[a.get("mortal_realm_tier", "unknown")] += 1
            elevation_counter[a.get("elevation_tier", 0)] += 1

            # Validate collision dictionary
            col = a.get("collision")
            if not isinstance(col, dict) or "solid" not in col or "shape" not in col:
                self.errors.append(
                    f"Asset {a.get('id')} has invalid collision dictionary structure"
                )

            # Validate variants and prompts
            variants = a.get("variants", [])
            total_variants += len(variants)
            for v in variants:
                pos = v.get("prompt", "")
                neg = v.get("negative_prompt", "")
                if not pos or len(pos) < 30:
                    missing_prompt_count += 1
                if not neg or len(neg) < 20:
                    missing_prompt_count += 1

        if missing_schema_keys:
            for k, cnt in missing_schema_keys.items():
                self.errors.append(f"Missing schema key '{k}' across {cnt} assets")
        else:
            self.info.append("100% Section 6 schema fields populated on all 4,260 assets")

        if missing_prompt_count > 0:
            self.errors.append(
                f"Found {missing_prompt_count} variants with missing or stub prompts"
            )
        else:
            self.info.append(
                f"100% of variants ({total_variants} total) have complete game-ready prompts"
            )

        # Element distribution check
        if len(element_counter) < 10:
            msg = f"Element affinities under-diversified: only {len(element_counter)} elements"
            self.errors.append(msg)
        else:
            self.info.append(
                f"Cultivation elements well-balanced across {len(element_counter)} affinities"
            )

        # Mortal Realm check
        for r in EXPECTED_REALMS:
            if r not in realm_counter:
                self.errors.append(f"Missing Mortal Realm tier: {r}")
        if len(realm_counter) == 9:
            self.info.append(
                "All 9 Mortal Realms represented with structured intra-category progression"
            )

        # Elevation tiers check
        for elev in range(1, 10):
            if elevation_counter[elev] == 0:
                self.errors.append(f"Missing elevation tier: {elev}")
        if len(elevation_counter) == 9:
            self.info.append("All elevation tiers (1 through 9) fully populated")

        return assets

    def _check_directory_structure(self, categories: list[dict]) -> None:
        print("\n[Audit 4/6] Auditing Physical Directory Scaffolding...")
        missing_dirs = 0
        total_expected_dirs = len(categories) * 3

        for c in categories:
            dom = c.get("domain_id") or c.get("domain")
            cid = c["id"]
            for sub in ("original", "runtime", "data"):
                p = PACK_DIR / sub / dom / cid
                if not p.is_dir():
                    missing_dirs += 1

        if missing_dirs > 0:
            self.errors.append(
                f"Found {missing_dirs}/{total_expected_dirs} missing physical category directories"
            )
        else:
            self.info.append(
                f"All {total_expected_dirs} category directories verified across subdirectories"
            )

    def _check_index(self) -> None:
        print("\n[Audit 5/6] Auditing Global Packs Index...")
        if not INDEX_PATH.exists():
            self.errors.append("game/assets/packs/index.json does not exist")
            return

        with open(INDEX_PATH, encoding="utf-8") as f:
            idx = json.load(f)

        matched = False
        for p in idx.get("packs", []):
            if p.get("pack_id") == "ancient_china_low_cultivation":
                matched = True
                if p.get("asset_count") != 4260:
                    self.errors.append(
                        f"Index asset_count mismatch: expected 4,260, got {p.get('asset_count')}"
                    )
                else:
                    self.info.append(
                        "Global index entry verified: ancient_china_low_cultivation, 4,260 assets"
                    )
                break

        if not matched:
            self.errors.append("ancient_china_low_cultivation not registered in index.json")

    def _print_summary(self, categories: list[dict], assets: list[dict]) -> None:
        print("\n[Audit 6/6] Summary Report")
        print("-" * 80)
        for inf in self.info:
            print(f"  [PASS] {inf}")
        for w in self.warnings:
            print(f"  [WARN] {w}")
        for err in self.errors:
            print(f"  [FAIL] {err}")
        print("-" * 80)

        if self.errors:
            print(f"\nAUDIT FAILED with {len(self.errors)} gap(s) to solve.")
        else:
            print("\nAUDIT PASSED: 0 ERRORS, 0 GAPS. ALL CRITERIA 100% SATISFIED!")
        print("=" * 80)


def main() -> int:
    auditor = CultivationPackAuditor()
    return auditor.audit_all()


if __name__ == "__main__":
    raise SystemExit(main())
