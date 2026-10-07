# -*- coding: utf-8 -*-
"""Comprehensive scaffolding generator for Ancient Chinese Mortal World Pack Expansion.

Generates 1,500 granular modular assets across Categories 15-19, enriching the pack
from 780 to 2,280 assets with maximized diversity:
  - Category 15: modular_architecture_timber (450 assets)
  - Category 16: mountain_cliff_geology (350 assets)
  - Category 17: flora_and_forest_ecology (250 assets)
  - Category 18: urban_street_and_market (250 assets)
  - Category 19: rural_farming_and_pastoral (200 assets)
"""

from __future__ import annotations

import json
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_PATH = REPO_ROOT / "game/assets/packs/ancient_china_mortal/ancient_china_mortal_pack.json"
CATEGORIES_PATH = REPO_ROOT / "game/assets/packs/ancient_china_mortal/categories.json"


def make_asset(
    cat_id: str,
    slug: str,
    name: str,
    vn_name: str,
    hanzi: str,
    sub_cat: str,
    footprint: list[int],
    collision: str,
    blocks_proj: bool,
    vision: str,
    verb: str | None,
    role: str,
    destructible: bool,
    material: str,
    element: str,
    prompt: str,
    asset_type: str,
    alpha: str,
    pivot: str,
    hooks: dict,
) -> dict:
    return {
        "id": f"ancient_china_mortal.{cat_id}.{slug}",
        "name": name,
        "vietnamese_name": vn_name,
        "hanzi": hanzi,
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
        "cultivation_element": element,
        "prompt_summary": prompt,
        "racial_faction": "mortal_dynasty",
        "environment_name": "Ancient China Mortal World (Cửu Châu Phàm Trần)",
        "environment_theme": "2D Orthographic top-down, gouache hand-painted, ink contour lines (#263A35), grounded East Asian mortal palette.",
        "world_tier": "Mortal World (Phàm Nhân Giới / Cửu Châu)",
        "status": "planned",
        "reference_ids": ["docs/art-direction.md#top-down-world-map"],
        "source": "ComfyUI local unet: krea2/raySemiReal_krea2TurboV1Nsfw.safetensors, lora: krea2/Scottie__Krea2.safetensors (1.0)",
        "license": "Generated locally; source checkpoint license terms apply",
        "gameplay_gap_hooks": hooks,
    }


# ==============================================================================
# CATEGORY 15: MODULAR TIMBER ARCHITECTURE (450 assets)
# ==============================================================================
def generate_category_15() -> list[dict]:
    items: list[dict] = []
    cid = "modular_architecture_timber"

    # 1. foundation_and_plinth_tai_ji (60 assets)
    f_styles = [
        ("granite_imperial", "Carved Imperial Granite", "Đá Hoa Cương Hoàng Triều", "官造花岗岩", "stone", "mortal"),
        ("rustic_fieldstone", "Rustic Dry Fieldstone", "Đá Cuội Đồng Quê Thô Mộc", "质朴乱石砌", "stone", "earth"),
        ("river_waterproof", "Water-Repellent River Siltstone", "Đá Sa Thạch Bến Nước", "防水青石埠", "stone", "water"),
        ("lotus_temple", "Sacred Lotus Carved Pedestal", "Đài Sen Khắc Chùa Miếu", "寺观雕莲瓣", "stone", "yang"),
        ("mossy_ancient", "Mossy Weathered Ancient Stone", "Đá Cổ Rêu Phong Năm Tháng", "青苔古石基", "stone", "yin"),
    ]
    f_types = [
        ("corner_plinth_pier", "Corner Foundation Plinth Pier", "Trụ Đá Chân Góc Móng", "角隅台基石", [1, 1], "solid", "inspect_foundation", "corner_foundation", "stone", None),
        ("straight_curb_edge_single", "Straight Base Curb Border (1x1)", "Gờ Đá Kê Chân Tường (1x1)", "单长阶条石", [1, 1], "walk_surface", "step_on", "edge_curb", "stone", None),
        ("straight_curb_edge_double", "Straight Base Curb Border (2x1)", "Gờ Đá Kê Chân Tường (2x1)", "双长阶条石", [2, 1], "walk_surface", "step_on", "edge_curb", "stone", None),
        ("straight_curb_edge_triple", "Straight Base Curb Border (3x1)", "Gờ Đá Kê Chân Tường (3x1)", "三长阶条石", [3, 1], "walk_surface", "step_on", "edge_curb", "stone", None),
        ("single_step_stair", "Single Tier Low Step", "Bậc Thềm Đơn Một Cấp", "单层垂带石阶", [1, 1], "walk_surface", "climb_steps", "step", "stone", None),
        ("double_step_stair", "Two-Tier Entrance Steps", "Bậc Thềm Đôi Hai Cấp", "双层如意石阶", [2, 1], "walk_surface", "climb_steps", "step", "stone", None),
        ("triple_step_stair", "Three-Tier Grand Court Steps", "Bậc Thềm Ba Cấp Đại Điện", "三级登殿石阶", [2, 1], "walk_surface", "climb_steps", "step", "stone", None),
        ("balustrade_straight_single", "Carved Stone Balustrade (1x1)", "Lan Can Đá Chạm Khắc (1x1)", "单跨透雕望柱栏杆", [1, 1], "solid", "lean_on_balustrade", "railing", "stone", None),
        ("balustrade_straight_double", "Carved Stone Balustrade (2x1)", "Lan Can Đá Chạm Khắc (2x1)", "双跨连环石栏板", [2, 1], "solid", "lean_on_balustrade", "railing", "stone", None),
        ("balustrade_corner_turn", "Corner Balustrade Post Turn", "Trụ Góc Lan Can Khắc Búp Sen", "转角荷花望柱", [1, 1], "solid", "inspect_balustrade_post", "railing_corner", "stone", None),
        ("drainage_dragon_spout", "Carved Dragon Drainage Spout (Chiwen)", "Đầu Rồng Phun Nước Thoát Mưa", "螭首散水石雕", [1, 1], "ground_contact", "inspect_dragon_spout", "drainage_spout", "bronze", "water"),
        ("center_dais_stone_platform", "Elevated Podium Center Dais", "Bệ Đá Trung Tâm Đặt Đại Điện", "殿中正心台座", [2, 2], "solid", "stand_on_dais", "dais_platform", "stone", "yang"),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in f_styles:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in f_types:
            slug = f"fnd_{s_slug}_{t_slug}"
            name = f"{s_en} {t_en}"
            vn = f"{t_vn} ({s_vn})"
            hz = f"{s_hz}{t_hz}"
            p = f"Ancient Chinese modular architectural foundation: {name}. {s_en} texture with dark ink contours, top-down orthographic angle, isolated game asset on transparent background."
            m = mat_override or s_mat
            e = elem_override or s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "foundation_and_plinth_tai_ji", fp, col, False, "transparent", verb, role, False, m, e, p, "structure", "transparent", "bottom_center", {"snap_layer": "foundation", "style": s_slug}))

    # 2. pillar_beam_and_dougong (70 assets)
    p_styles = [
        ("vermilion_palace", "Vermilion Lacquered Palace", "Sơn Son Cung Đình", "朱红宫廷", "wood", "fire"),
        ("weathered_pine", "Weathered Pine Timber", "Gỗ Thông Già Mộc Mạc", "风化老松", "wood", "wood"),
        ("soot_black_forge", "Soot-Blackened Heavy Cedar", "Gỗ Bách Hun Khói Lò Rèn", "熏黑重柏", "wood", "metal"),
        ("golden_nanmu", "Lustrous Gilded Nanmu", "Gỗ Nam Mộc Quý Phái", "金丝楠木", "wood", "yang"),
        ("bamboo_rustic", "Bound Giant Bamboo Culm", "Cọc Tre Già Buộc Lạt", "紧束毛竹", "bamboo", "wind"),
        ("grey_carved_stone", "Carved Grey Granite Column", "Cột Đá Hoa Cương Chạm", "雕纹青石", "stone", "earth"),
        ("decayed_ruin", "Rotting Splintered Temple Timber", "Gỗ Mục Đền Miếu Đổ Nát", "腐朽残断", "wood", "yin"),
    ]
    p_types = [
        ("pillar_round_single_short", "Round Column Pillar (Short 1x1)", "Cột Trụ Tròn Thấp (1x1)", "矮圆立柱", [1, 1], "solid", "inspect_pillar", "vertical_support", None, None),
        ("pillar_round_single_tall", "Round Column Pillar (Tall 1x2)", "Cột Trụ Tròn Cao (1x2)", "高耸通柱", [1, 2], "solid", "inspect_pillar", "vertical_support", None, None),
        ("pillar_corner_square", "Square Corner Pillar Assembly", "Cột Vuông Chân Góc", "角隅方柱", [1, 1], "solid", "inspect_pillar", "corner_support", None, None),
        ("dougong_single_cantilever", "Single-Tier Cantilever Dougong Bracket", "Đẩu Củng Một Tầng Đỡ Mái", "单翘单昂斗栱", [1, 1], "solid", "admire_bracket_joinery", "bracket_set", None, None),
        ("dougong_multi_tier_grand", "Multi-Tier Cluster Dougong Assembly", "Cụm Đẩu Củng Nhiều Tầng Tinh Xảo", "多层重昂大斗栱", [2, 1], "solid", "admire_bracket_joinery", "bracket_set", None, None),
        ("dougong_corner_45deg", "45-Degree Corner Bracket Cluster", "Đẩu Củng Góc 45 Độ", "转角斜栱", [1, 1], "solid", "inspect_corner_bracket", "corner_bracket", None, None),
        ("crossbeam_carved_single", "Horizontal Tie-Beam Girder (2x1)", "Xà Ngang Nối Cột (2x1)", "雕花大额枋", [2, 1], "solid", "examine_carved_beam", "horizontal_beam", None, None),
        ("crossbeam_carved_double", "Long Ceiling Tie-Beam (3x1)", "Xà Gồ Trần Dài (3x1)", "穿插长枋木", [3, 1], "solid", "examine_ceiling_beam", "horizontal_beam", None, None),
        ("lintel_with_inscribed_plaque", "Door Lintel with Gold Lettering Plaque", "Hoành Phi Câu Đối Trên Khung Cửa", "题字金匾门楣", [2, 1], "solid", "read_lintel_inscription", "door_lintel", "lacquer", "mortal"),
        ("open_gateway_frame_skeleton", "Open Two-Pillar Structural Gateway Portal", "Khung Cửa Trụ Đôi Đứng Mở", "双柱歇山门架", [2, 2], "solid", "pass_under_portal", "portal_frame", None, None),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in p_styles:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in p_types:
            slug = f"col_{s_slug}_{t_slug}"
            name = f"{s_en} {t_en}"
            vn = f"{t_vn} ({s_vn})"
            hz = f"{s_hz}{t_hz}"
            p = f"Ancient Chinese timber frame architecture component: {name}. Traditional mortise and tenon craftsmanship, ink contours, top-down orthographic sprite on clean transparent alpha background."
            m = mat_override or s_mat
            e = elem_override or s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "pillar_beam_and_dougong", fp, col, True, "transparent", verb, role, False, m, e, p, "structure", "transparent", "bottom_center", {"snap_layer": "pillar_beam", "style": s_slug}))

    # 3. wall_and_lattice_window (90 assets)
    w_styles = [
        ("white_lime_plaster", "Jiangnan White Lime Plaster", "Tường Vôi Trắng Giang Nam", "江南白灰粉墙", "brick", "water"),
        ("imperial_grey_brick", "Imperial Dynasty Grey Brick", "Gạch Bát Tràng Xám Tro Triều Đình", "官造磨砖缝", "brick", "mortal"),
        ("rammed_earth_rural", "Rammed Loess Clay & Straw", "Tường Đất Nện Pha Rơm Đồng Quê", "夯土版筑墙", "earth", "earth"),
        ("mossy_temple_stone", "Mossy Sacred Mountain Masonry", "Đá Xếp Miếu Núi Rêu Phong", "古刹青苔乱石墙", "stone", "yin"),
        ("fire_scorched_brick", "Battle-Scorched Cracked Brick", "Gạch Nứt Cháy Xém Khói Lửa", "兵火焦黑残垣", "brick", "fire"),
        ("wattle_bamboo_farm", "Woven Bamboo Wattle & Mud", "Liếp Tre Trát Bùn Nông Gia", "编竹抹泥矮隔墙", "bamboo", "wood"),
    ]
    w_types = [
        ("wall_straight_single", "Straight Solid Wall (1x1)", "Tường Đặc Thẳng (1x1)", "单步实墙", [1, 1], "solid", "knock_wall", "wall_segment", None, None),
        ("wall_straight_double", "Straight Solid Wall (2x1)", "Tường Đặc Thẳng (2x1)", "双步长墙", [2, 1], "solid", "knock_wall", "wall_segment", None, None),
        ("wall_straight_triple", "Straight Solid Wall (3x1)", "Tường Đặc Thẳng (3x1)", "三步院墙", [3, 1], "solid", "knock_wall", "wall_segment", None, None),
        ("wall_corner_90deg", "Right-Angle Wall Corner (1x1)", "Góc Tường Vuông 90 Độ", "转角合角墙", [1, 1], "solid", "inspect_wall_corner", "corner_wall", None, None),
        ("wall_t_junction", "T-Junction Intersecting Wall", "Ngã Ba Tường Giao Nhau", "丁字接交墙", [2, 1], "solid", "inspect_junction", "junction_wall", None, None),
        ("wall_end_pier_finial", "Wall Terminal Pier with Tile Coping", "Trụ Kết Thúc Đầu Tường Đội Mũ Ngói", "端头披檐照壁桩", [1, 1], "solid", "inspect_wall_end", "wall_end", None, None),
        ("window_plum_blossom_lattice", "Wall with Plum Blossom Lattice Window", "Tường Trổ Cửa Sổ Hoa Mai", "梅花万字棂花窗", [1, 1], "solid", "peer_through_window", "lattice_window", "paper", "wood"),
        ("window_cracked_ice_pattern", "Wall with Cracked-Ice Geo Lattice Window", "Tường Trổ Cửa Sổ Băng Nứt", "冰裂纹透光花窗", [1, 1], "solid", "peer_through_window", "lattice_window", "wood", "water"),
        ("window_bagua_octagonal", "Wall with Octagonal Bagua Window", "Tường Trổ Cửa Sổ Bát Quái", "八卦开运八角窗", [1, 1], "solid", "align_bagua_window", "lattice_window", "wood", "yang"),
        ("window_sliding_shutter_open", "Wall with Open Wooden Shutter Window", "Tường Có Khung Cửa Sổ Gỗ Chống Mở", "推板支摘木窗", [1, 1], "solid", "unlatch_shutter", "open_window", "wood", "wind"),
        ("screen_carved_silk_divider", "Indoor Carved Silk Folding Screen (2x1)", "Bình Phong Gỗ Khảm Lụa Trong Nhà", "折叠雕花木绢屏风", [2, 1], "solid", "inspect_silk_screen", "interior_screen", "silk", "mortal"),
        ("curtain_bamboo_bead_portal", "Wall Portal with Hanging Bamboo Bead Curtain", "Cửa Vòm Treo Mành Trúc Hạt Gỗ", "悬挂竹帘隔断门洞", [1, 1], "ground_contact", "part_bamboo_curtain", "curtain_portal", "bamboo", "wind"),
        ("wall_broken_exposed_bricks", "Breached Wall with Spilling Broken Bricks", "Tường Sập Lộ Ruột Đất Đá Vỡ Vụn", "坍塌残缺裂口墙", [2, 1], "solid", "search_rubble", "damaged_wall", None, None),
        ("wall_ivy_creeper_dense", "Wall Overgrown with Climbing Green Ivy", "Tường Phủ Dày Dây Leo Dại Xanh", "浓密爬山虎覆绿墙", [2, 1], "solid", "climb_ivy_wall", "foliage_wall", "plant", "wood"),
        ("wall_low_courtyard_parapet", "Low Half-Height Courtyard Parapet (2x1)", "Tường Lửng Sân Vườn Cao Ngang Ngực", "矮身敞空院落矮墙", [2, 1], "solid", "vault_low_wall", "low_wall", None, None),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in w_styles:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in w_types:
            slug = f"wal_{s_slug}_{t_slug}"
            name = f"{s_en} {t_en}"
            vn = f"{t_vn} ({s_vn})"
            hz = f"{s_hz}{t_hz}"
            p = f"Ancient Chinese vernacular building wall module: {name}. Authentic materials, crisp dark ink outlines, orthographic top-down world-map view, isolated cleanly on transparent background."
            m = mat_override or s_mat
            e = elem_override or s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "wall_and_lattice_window", fp, col, True, "transparent" if "window" in t_slug else "solid", verb, role, True if "broken" in t_slug else False, m, e, p, "structure", "transparent", "bottom_center", {"snap_layer": "wall", "style": s_slug}))

    # 4. moon_gate_and_archway (50 assets)
    g_styles = [
        ("scholar_garden", "Scholar Garden Classical", "Vườn Văn Nhân Tao Nhã", "文人园林", "stone", "wood"),
        ("imperial_residence", "Imperial Official Residence", "Dinh Thự Quyền Quý", "王府官邸", "brick", "fire"),
        ("rural_village_gate", "Rural Peasant Village", "Cổng Thôn Trang Bình Dị", "乡野庄门", "wood", "earth"),
        ("mountain_monastery", "Mountain Daoist Monastery", "Cổng Đạo Viện Núi Cao", "仙山道观", "stone", "yang"),
        ("bandit_palisade", "Wilderness Stockade Outlaw", "Cửa Trại Sơn Tặc Rừng Sâu", "绿林寨栅", "wood", "metal"),
    ]
    g_types = [
        ("moon_gate_circular_open", "Circular Moon Gate Arch (Open Portal)", "Cổng Nguyệt Môn Tròn Mở Thông (2x2)", "正圆月洞通门", [2, 2], "ground_contact", "pass_through_moon_gate", "portal", None, None),
        ("moon_gate_red_lanterns", "Moon Gate Draped with Twin Red Lanterns", "Cổng Nguyệt Môn Treo Cặp Đèn Lồng Đỏ", "双红灯笼月洞门", [2, 2], "ground_contact", "inspect_hanging_lanterns", "portal", "silk", "yang"),
        ("moon_gate_bamboo_view", "Moon Gate Framing Green Bamboo Garden", "Nguyệt Môn Nhìn Ra Rừng Trúc", "漏景透竹月亮门", [2, 2], "solid", "admire_framed_view", "framed_view", None, "wood"),
        ("vase_shaped_peace_portal", "Auspicious Vase-Shaped Peace Gate (Ping'an)", "Cổng Hình Bình Hoa Chúc Bình An", "吉祥净瓶吉庆门", [2, 2], "ground_contact", "enter_vase_portal", "portal", None, "water"),
        ("octagonal_bagua_arch", "Octagonal Feng Shui Bagua Courtyard Portal", "Cửa Vòm Bát Giác Phong Thủy", "八卦转运八角门洞", [2, 2], "ground_contact", "pass_bagua_arch", "portal", None, "yang"),
        ("double_door_vermilion_lion", "Heavy Two-Leaf Vermilion Door with Brass Lions", "Cửa Gỗ Hai Cánh Sơn Son Gõ Đầu Sư Tử", "朱红兽首双环大门", [2, 2], "solid", "knock_lion_knocker", "door_barrier", "bronze", "metal"),
        ("double_door_rustic_weathered", "Rustic Split-Timber Double Door with Latch", "Cửa Gỗ Mộc Cũ Kỹ Có Then Cài", "柴木双扇闩门", [2, 2], "solid", "unlatch_wooden_door", "door_barrier", "wood", None),
        ("wicket_single_bamboo_gate", "Light Woven Bamboo Garden Wicket Gate", "Cổng Xoay Bằng Mành Tre Nhẹ Nhàng", "编竹合扇小柴扉", [1, 1], "ground_contact", "push_wicket_gate", "wicket_gate", "bamboo", "wind"),
        ("paifang_two_pillar_memorial", "Two-Pillar Carved Memorial Archway (Paifang)", "Cổng Nghi Môn Hai Trụ Đứng", "二柱单间雕花牌坊", [3, 2], "solid", "pass_memorial_arch", "memorial_arch", None, "mortal"),
        ("overgrown_ancient_arch_ruin", "Collapsed Ruined Stone Gateway with Vines", "Cổng Đá Cổ Đổ Nát Dây Leo Quấn Kín", "藤萝缠绕坍塌古门", [2, 2], "solid", "scramble_over_ruin", "ruined_arch", "stone", "yin"),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in g_styles:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in g_types:
            slug = f"gat_{s_slug}_{t_slug}"
            name = f"{s_en} {t_en}"
            vn = f"{t_vn} ({s_vn})"
            hz = f"{s_hz}{t_hz}"
            p = f"Ancient Chinese architectural entrance portal: {name}. Ornate joinery, traditional aesthetic, top-down orthographic view for 2D RPG, clear transparent background."
            m = mat_override or s_mat
            e = elem_override or s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "moon_gate_and_archway", fp, col, False if "open" in t_slug or "portal" in role else True, "transparent", verb, role, True if "ruin" in t_slug else False, m, e, p, "building", "transparent", "bottom_center", {"snap_layer": "gateway", "style": s_slug}))

    # 5. modular_roof_and_flying_eaves (100 assets)
    r_styles = [
        ("charcoal_grey_tile", "Imperial Charcoal Grey Clay Tile", "Ngói Xám Tro Cung Đình", "官造青灰瓦", "tile", "water"),
        ("golden_glazed_tile", "Imperial Gilded Yellow Glazed Tile", "Ngói Lưu Ly Vàng Hoàng Cung", "明黄琉璃金顶", "tile", "yang"),
        ("straw_peasant_thatch", "Thick Layered Golden Straw Thatch", "Mái Tranh Đồng Quê Dày Rơm Vàng", "农家厚苫麦草", "straw", "earth"),
        ("bark_shingle_mountain", "Split Cedar Wood Shingles", "Ngói Ván Gỗ Bách Sơn Lâm", "雪松劈木瓦", "wood", "wood"),
        ("mossy_weathered_tile", "Moss-Covered Hundred-Year Temple Tile", "Ngói Cổ Trăm Năm Rêu Bám", "百岁苍苔老瓦", "tile", "yin"),
    ]
    r_types = [
        ("straight_ridge_1x1", "Straight Roof Ridge Strip (1x1)", "Sống Nóc Mái Thẳng (1x1)", "单步正脊", [1, 1], "solid", "inspect_roof_ridge", "roof_ridge", None, None),
        ("straight_ridge_2x1", "Straight Roof Ridge Strip (2x1)", "Sống Nóc Mái Thẳng (2x1)", "双步正脊", [2, 1], "solid", "inspect_roof_ridge", "roof_ridge", None, None),
        ("straight_ridge_3x1", "Straight Roof Ridge Strip (3x1)", "Sống Nóc Mái Thẳng (3x1)", "三步正脊", [3, 1], "solid", "inspect_roof_ridge", "roof_ridge", None, None),
        ("pitch_slope_eave_1x1", "Sloping Tile Eaves Bay (1x1)", "Mái Ngói Dốc Xuống (1x1)", "单步顺坡披檐", [1, 1], "solid", "inspect_eave_slope", "roof_slope", None, None),
        ("pitch_slope_eave_2x1", "Sloping Tile Eaves Bay (2x1)", "Mái Ngói Dốc Xuống (2x1)", "双步顺坡披檐", [2, 1], "solid", "inspect_eave_slope", "roof_slope", None, None),
        ("pitch_slope_eave_3x1", "Sloping Tile Eaves Bay (3x1)", "Mái Ngói Dốc Xuống (3x1)", "三步顺坡披檐", [3, 1], "solid", "inspect_eave_slope", "roof_slope", None, None),
        ("flying_eave_corner_se", "Sweeping Flying Eave Upturned Corner (SE)", "Đầu Mái Cong Vút Phi Thiềm (Đông Nam)", "东南飞檐戗角", [1, 1], "solid", "admire_flying_eave", "flying_eave", None, "wind"),
        ("flying_eave_corner_sw", "Sweeping Flying Eave Upturned Corner (SW)", "Đầu Mái Cong Vút Phi Thiềm (Tây Nam)", "西南飞檐戗角", [1, 1], "solid", "admire_flying_eave", "flying_eave", None, "wind"),
        ("flying_eave_corner_ne", "Sweeping Flying Eave Upturned Corner (NE)", "Đầu Mái Cong Vút Phi Thiềm (Đông Bắc)", "东北飞檐戗角", [1, 1], "solid", "admire_flying_eave", "flying_eave", None, "wind"),
        ("flying_eave_corner_nw", "Sweeping Flying Eave Upturned Corner (NW)", "Đầu Mái Cong Vút Phi Thiềm (Tây Bắc)", "西北飞檐戗角", [1, 1], "solid", "admire_flying_eave", "flying_eave", None, "wind"),
        ("eave_corner_wind_bell", "Eave Corner Dangling Bronze Wind Chime", "Đầu Mái Treo Chuông Gió Phong Linh", "角梁悬挂铜风铃", [1, 1], "solid", "listen_wind_bell", "eave_bell", "bronze", "wind"),
        ("eave_ridge_beasts_march", "Eave Corner Line of Imperial Mythical Beasts", "Đoàn Linh Thú Trấn Giữ Góc Mái (Chiwen)", "檐角走兽仙人阵", [1, 1], "solid", "inspect_ridge_beast", "ridge_beasts", "ceramic", "yang"),
        ("hip_gable_corner_turn", "Hipped-and-Gabled Roof Corner Turn", "Góc Mái Khối Nóc Hỗn Hợp Xieshan", "歇山四合推山角", [2, 2], "solid", "inspect_xieshan_corner", "roof_corner", None, None),
        ("gable_end_stepped_wall", "Stepped Horse-Head Gable End (Matouqiang)", "Đầu Hồi Tường Bậc Đầu Ngựa (Mã Đầu Tường)", "徽派马头山墙顶", [2, 2], "solid", "admire_matouqiang", "gable_end", "brick", "fire"),
        ("swallowtail_ridge_apex", "Southern Sweeping Swallowtail Ridge Apex", "Đỉnh Nóc Uốn Cong Đuôi Én Nam Phương", "闽南双燕尾大正脊", [2, 1], "solid", "admire_swallowtail_ridge", "ridge_apex", None, "wind"),
        ("conical_round_apex_cap", "Conical Pavilion Round Roof Finial Cap", "Chóp Nón Đỉnh Đình Bát Giác", "圆亭攒尖宝顶", [2, 2], "solid", "inspect_apex_finial", "roof_cap", "bronze", "metal"),
        ("dormer_ventilating_gable", "Attic Smoke & Ventilation Roof Dormer", "Cửa Sổ Thoát Khói Trên Mái", "通风采光小老虎天窗", [1, 1], "solid", "peer_into_attic", "roof_dormer", "wood", "wind"),
        ("collapsed_damaged_roof_hole", "Broken Collapsed Roof Exposing Rafters", "Lỗ Thủng Trên Mái Lộ Vì Kèo Gỗ", "塌陷破损露橡椽", [2, 1], "solid", "climb_through_roof_gap", "damaged_roof", None, "yin"),
        ("winter_snow_dusted_tiles", "Snow-Dusted Winter Roof Tile Strip (2x1)", "Dải Ngói Phủ Tuyết Trắng Mùa Đông", "雪压青瓦冬景片", [2, 1], "solid", "brush_off_snow", "snow_roof", None, "water"),
        ("copper_dragon_water_gutter", "Copper Rainwater Drainage Gutter & Chain", "Máng Xối Đồng Dẫn Nước Mưa Kèm Xích", "铜水溜承水垂链", [1, 1], "solid", "inspect_rain_chain", "rain_gutter", "bronze", "water"),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in r_styles:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in r_types:
            slug = f"ruf_{s_slug}_{t_slug}"
            name = f"{s_en} {t_en}"
            vn = f"{t_vn} ({s_vn})"
            hz = f"{s_hz}{t_hz}"
            p = f"Ancient Chinese modular roof and eaves component: {name}. Intricate clay tiles, sweeping silhouette, gouache rendering with ink contours, orthographic top-down view, transparent background."
            m = mat_override or s_mat
            e = elem_override or s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "modular_roof_and_flying_eaves", fp, col, True, "solid", verb, role, True if "collapsed" in t_slug else False, m, e, p, "structure", "transparent", "bottom_center", {"snap_layer": "roof", "style": s_slug}))

    # 6. covered_corridor_and_veranda (80 assets)
    c_styles = [
        ("scholar_garden_veranda", "Classical Garden Cloister Walkway", "Hành Lang Vườn Cảnh Giang Nam", "苏式游廊", "wood", "wood"),
        ("yamen_official_corridor", "Magistrate Complex Dignified Corridor", "Hành Lang Nha Môn Uy Nghi", "官署通廊", "wood", "mortal"),
        ("mountain_temple_zigzag", "Mountain Monastery Stepped Walkway", "Hành Lang Ziczac Quanh Núi", "依山曲折栈廊", "wood", "earth"),
        ("lake_waterside_gallery", "Lakeside Pierced Viewing Gallery", "Hành Lang Bến Nước Ngắm Cảnh", "水阁临波水廊", "wood", "water"),
    ]
    c_types = [
        ("straight_bay_single", "Straight Covered Walkway Bay (1x1)", "Một Nhịp Hành Lang Thẳng (1x1)", "单间直长平廊", [1, 1], "walk_surface", "walk_along", "corridor_bay", None, None),
        ("straight_bay_double", "Straight Covered Walkway Bay (2x1)", "Hai Nhịp Hành Lang Thẳng (2x1)", "双间直长平廊", [2, 1], "walk_surface", "walk_along", "corridor_bay", None, None),
        ("straight_bay_triple", "Straight Covered Walkway Bay (3x1)", "Ba Nhịp Hành Lang Thẳng (3x1)", "三间直长平廊", [3, 1], "walk_surface", "walk_along", "corridor_bay", None, None),
        ("corner_90deg_turn", "Right-Angle 90-Degree Corridor Turn", "Khúc Rẽ Hành Lang Vuông 90 Độ", "直角转角廊", [2, 2], "walk_surface", "walk_along", "corridor_turn", None, None),
        ("zigzag_45deg_slant", "Slanted 45-Degree Zigzag Corridor Bay", "Khúc Lượn Hành Lang Nghiêng 45 Độ", "折角游龙曲廊", [2, 2], "walk_surface", "walk_along", "corridor_zigzag", None, None),
        ("climbing_hillside_steps", "Stepped Climbing Hillside Corridor Bay", "Hành Lang Bậc Thang Men Sườn Dốc", "依坡爬山迭落廊", [2, 2], "walk_surface", "climb_stepped_corridor", "stepped_corridor", None, "earth"),
        ("t_junction_crossway", "T-Junction Corridor Intersection Hub", "Ngã Ba Hành Lang Giao Nhau", "三向交会丁字廊亭", [2, 2], "walk_surface", "walk_along", "corridor_junction", None, None),
        ("crossroads_four_way", "Four-Way Corridor Crossroads Pavilion", "Ngã Tư Hành Lang Giao Lộ", "十字四通集散中亭", [3, 3], "walk_surface", "walk_along", "corridor_crossroads", None, None),
        ("meirenkao_beauty_bench", "Corridor Bay with Curved Beauty-Rest Bench", "Hành Lang Có Ghế Tựa Mỹ Nhân Kháo", "带美人靠曲栏平廊", [2, 1], "walk_surface", "rest_on_bench", "corridor_bench", None, "mortal"),
        ("mid_corridor_square_kiosk", "Square Viewing Pavilion on Corridor", "Đình Nghỉ Chân Vuông Giữa Hành Lang", "廊中方角停歇亭", [2, 2], "walk_surface", "rest_at_kiosk", "rest_kiosk", None, "wood"),
        ("octagonal_overlook_kiosk", "Octagonal Water Overlook Corridor Pavilion", "Đình Bát Giác Ngắm Cảnh Bến Nước", "八角临渊水榭亭", [3, 3], "walk_surface", "admire_scenic_overlook", "viewing_pavilion", None, "water"),
        ("hanging_lanterns_bay", "Corridor Bay Hung with Festive Red Lanterns", "Hành Lang Treo Đèn Lồng Đỏ Lễ Hội", "挂双红纱灯连廊", [2, 1], "walk_surface", "gaze_at_lanterns", "lantern_corridor", "silk", "yang"),
        ("bamboo_lattice_gallery", "Open Air Corridor with Carved Bamboo Tracing", "Hành Lang Thông Thoáng Khắc Cành Trúc", "透花镂空赏景长廊", [2, 1], "walk_surface", "peer_through_gallery", "open_gallery", "bamboo", "wind"),
        ("covered_footbridge_span", "Covered Wooden Arch Bridge Walkway Span", "Nhịp Cầu Gỗ Có Mái Che Vượt Nước", "风雨廊桥木步跨", [3, 1], "walk_surface", "cross_covered_bridge", "covered_bridge", None, "water"),
        ("corridor_entrance_landing", "Corridor Terminal Landing with Steps", "Chiếu Nghỉ Đầu Hành Lang Kèm Bậc Đá", "廊端出入石步台", [2, 1], "walk_surface", "step_onto_landing", "corridor_landing", "stone", "earth"),
        ("broken_corridor_rafter_gap", "War-Damaged Corridor with Collapsed Roof", "Hành Lang Gãy Đổ Mái Vì Đạn Tên", "兵燹断落残梁通廊", [2, 1], "walk_surface", "leap_across_broken_gap", "damaged_corridor", None, "yin"),
        ("ivy_draped_cloister_bay", "Corridor Draped in Lush Flowering Wisteria", "Hành Lang Phủ Hoa Tử Đằng Nở Rộ", "垂挂紫藤花影长廊", [2, 1], "walk_surface", "smell_wisteria_blooms", "floral_corridor", "plant", "wood"),
        ("moon_window_gallery_segment", "Corridor Enclosed Wall with Moon View Hole", "Hành Lang Kèm Vách Trổ Cửa Tròn", "临水开窗游步长阁", [2, 1], "walk_surface", "peer_through_moon_window", "windowed_corridor", None, "water"),
        ("wind_screen_sliding_panels", "Corridor with Winter Sliding Paper Screens", "Hành Lang Gắn Cửa Lùa Chắn Gió Đông", "冬日移门避风暖廊", [2, 1], "walk_surface", "slide_wind_screen", "screened_corridor", "paper", "wind"),
        ("courtyard_connecting_arbor", "Shaded Trellis Arbor Linking Two Courtyards", "Hành Lang Giàn Khung Nối Liền Hai Sân", "两进通连葡萄木荫架", [2, 2], "walk_surface", "stroll_under_arbor", "arbor_walkway", "plant", "wood"),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in c_styles:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in c_types:
            slug = f"cor_{s_slug}_{t_slug}"
            name = f"{s_en} {t_en}"
            vn = f"{t_vn} ({s_vn})"
            hz = f"{s_hz}{t_hz}"
            p = f"Ancient Chinese covered garden corridor module: {name}. Traditional tiled wooden gallery, balustrade railing, top-down orthographic game sprite, transparent alpha cutout."
            m = mat_override or s_mat
            e = elem_override or s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "covered_corridor_and_veranda", fp, col, False, "transparent", verb, role, True if "broken" in t_slug else False, m, e, p, "structure", "transparent", "bottom_center", {"snap_layer": "corridor", "style": s_slug}))

    return items


# ==============================================================================
# CATEGORY 16: MOUNTAIN GEOLOGY, CLIFFS & WATERS (350 assets)
# ==============================================================================
def generate_category_16() -> list[dict]:
    items: list[dict] = []
    cid = "mountain_cliff_geology"

    # 1. cliff_face_and_bluff (90 assets)
    c_geos = [
        ("yellow_loess_bluff", "Yellow Loess Terraced Bluff", "Vách Đất Vàng Hoàng Thổ Phù Sa", "黄土塬高崖", "earth", "earth"),
        ("grey_limestone_strata", "Stratified Grey Limestone Cliff", "Vách Đá Vôi Xám Trầm Tích", "层状灰岩绝壁", "stone", "metal"),
        ("craggy_granite_precipice", "Craggy Jagged Granite Precipice", "Vách Đá Hoa Cương Dựng Đứng", "嶙峋花岗岩峭壁", "stone", "earth"),
        ("red_sandstone_danxia", "Crimson Danxia Sandstone Gorge", "Hẻm Núi Sa Thạch Đỏ Đan Hà", "赤壁丹霞峡谷", "stone", "fire"),
        ("mossy_ravine_slate", "Wet Mossy Ravine Dark Slate", "Vách Đá Phiến Rêu Ướt Khe Suối", "湿滑苔藓黑板岩", "stone", "water"),
    ]
    c_types = [
        ("vertical_face_single", "Vertical Cliff Wall Bay (1x2)", "Vách Đứng Đơn (1x2)", "双格垂立壁", [1, 2], "solid", "inspect_cliff_face", "cliff_barrier", None, None),
        ("vertical_face_double", "Vertical Cliff Wall Bay (2x2)", "Vách Đứng Rộng (2x2)", "宽面坚直崖", [2, 2], "solid", "inspect_cliff_face", "cliff_barrier", None, None),
        ("vertical_face_triple", "Massive Mountain Bluff Wall (3x2)", "Vách Núi Dài Đứng Thẳng (3x2)", "宏伟三格大崖壁", [3, 2], "solid", "inspect_cliff_face", "cliff_barrier", None, None),
        ("cliff_corner_convex", "Protruding Convex Cliff Corner", "Góc Vách Núi Nhô Ra Ngoài", "凸突转角崖", [2, 2], "solid", "inspect_cliff_corner", "cliff_corner", None, None),
        ("cliff_corner_concave", "Recessed Concave Cliff Alcove", "Hõm Vách Núi Ăn Sâu Vào", "凹入避风崖窝", [2, 2], "solid", "shelter_in_alcove", "cliff_alcove", None, "yin"),
        ("horizontal_ledge_shelf", "Climbable Rocky Shelf Ledge (2x1)", "Gờ Đá Bằng Để Bước Lên (2x1)", "横平可立岩沿", [2, 1], "walk_surface", "rest_on_ledge", "cliff_ledge", None, None),
        ("cliff_ledge_with_pine", "Cliff Shelf Supporting Dwarf Pine", "Gờ Vách Đá Mọc Cây Tùng Còi", "绝壁斜生怪松岩阶", [2, 2], "solid", "admire_cliff_pine", "scenic_cliff", None, "wood"),
        ("sheer_drop_overhang", "Overhanging Ceiling Rock Eave", "Mái Đá Nhô Ra Che Đầu", "悬突倒扣岩檐", [2, 1], "solid", "shelter_under_overhang", "cliff_overhang", None, None),
        ("shattered_fault_fracture", "Deep Vertical Earthquake Fault Crack", "Vết Nứt Nẹp Sâu Thẳng Đứng", "地震劈裂直断层", [1, 2], "solid", "examine_fault_fracture", "cliff_fissure", None, "yin"),
        ("narrow_chimney_crevice", "Narrow Rock Chimney Pass (1x2)", "Khe Nứt Kẹp Người Đi Lọt", "夹缝一线天石道", [1, 2], "walk_surface", "squeeze_through_chimney", "narrow_pass", None, "wind"),
        ("cliff_cut_stone_stairs", "Ancient Chiseled Cliff Stairway", "Bậc Thang Đục Vào Vách Đá", "悬空凿出盘山石磴", [1, 2], "walk_surface", "climb_cliff_stairs", "cliff_stairs", None, None),
        ("shandao_timber_plank_road", "Cliff-Hanging Wooden Plank Road (2x1)", "Cầu Sạn Đạo Gỗ Bám Vách Núi (2x1)", "险峻绝壁悬木栈道", [2, 1], "walk_surface", "traverse_plank_road", "plank_road", "wood", "wind"),
        ("shandao_corner_turn", "Plank Road Right-Angle Corner", "Khúc Quanh Cầu Sạn Đạo", "栈道直角转角台", [2, 2], "walk_surface", "traverse_plank_road", "plank_corner", "wood", "wind"),
        ("shandao_broken_gap", "Shattered Plank Road Gap (Jump Hazard)", "Đoạn Cầu Sạn Đạo Gãy Sụp", "断落悬空踏板缺口", [2, 1], "none", "leap_across_chasm", "plank_hazard", "wood", "wind"),
        ("natural_rock_footpath", "Natural Meandering Ridge Footpath", "Đường Mòn Đá Men Sườn Vách", "随形自然山径台", [3, 1], "walk_surface", "walk_ridge_path", "ridge_path", None, None),
        ("seeping_water_wet_wall", "Weeping Water Mineral Seepage Wall", "Vách Đá Ngấm Nước Chảy Róc Rách", "渗水潮湿挂水石壁", [2, 2], "solid", "drink_mineral_seepage", "wet_cliff", None, "water"),
        ("scree_apron_base", "Loose Rock Scree Fan at Cliff Base", "Chân Vách Núi Đọng Đá Dăm Lở", "崖脚倒石堆碎屑坡", [2, 1], "walk_surface", "scramble_scree", "scree_base", None, "earth"),
        ("summit_lookout_pinnacle", "High Clifftop Outlook Platform", "Mỏm Đá Đỉnh Vách Nhìn Ra Mây", "登高远眺凸台峰头", [2, 2], "walk_surface", "meditate_on_summit", "lookout_point", None, "wind"),
    ]
    for g_slug, g_en, g_vn, g_hz, g_mat, g_elem in c_geos:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in c_types:
            slug = f"clf_{g_slug}_{t_slug}"
            name = f"{g_en} {t_en}"
            vn = f"{t_vn} ({g_vn})"
            hz = f"{g_hz}{t_hz}"
            p = f"Ancient Chinese mountainous geology landscape: {name}. Realistic rock textures, ink contours, orthographic top-down world-map view, transparent alpha background."
            m = mat_override or g_mat
            e = elem_override or g_elem
            items.append(make_asset(cid, slug, name, vn, hz, "cliff_face_and_bluff", fp, col, False if col == "walk_surface" else True, "solid", verb, role, False, m, e, p, "structure", "transparent", "bottom_center", {"geology_layer": "cliff", "strata": g_slug}))

    # 2. karst_spire_and_pinnacle (70 assets)
    k_regions = [
        ("guilin_jade_tower", "Guilin Verdant Karst Spire", "Trụ Đỉnh Quế Lâm Xanh Biếc", "桂林叠翠秀峰", "stone", "wood"),
        ("yangshuo_slender_needle", "Yangshuo Razor Needle Peak", "Đỉnh Kim Dương Sóc Nhọn Hoắt", "阳朔一线立独锥", "stone", "metal"),
        ("wulingyuan_sandstone_pillar", "Zhangjiajie Towering Sandstone Monolith", "Trụ Cột Trương Gia Giới Cao Vút", "武陵源砂岩天柱", "stone", "earth"),
        ("misty_cloud_shrouded", "Cloud-Veiled Spirit Mountain Peak", "Đỉnh Núi Mây Mù Quanh Năm", "云海缭绕仙山巅", "stone", "wind"),
        ("charred_lightning_crag", "Lightning-Struck Thunder Crag", "Đỉnh Sét Đánh Cháy Đen Đơn Độc", "遭雷劈裂焦黑孤崖", "stone", "yang"),
    ]
    k_types = [
        ("monolithic_spire_single", "Solitary Karst Tower Monolith", "Trụ Núi Độc Đỉnh Thẳng Đứng (2x2)", "独立插天石笋峰", [2, 2], "solid", "gaze_at_spire", "karst_peak", None, None),
        ("slender_needle_pinnacle", "Razor Slender Stone Needle Pinnacle", "Mũi Kim Nhọn Chọc Trời (1x2)", "极细剑指冲天石锥", [1, 2], "solid", "gaze_at_needle_peak", "needle_peak", None, None),
        ("twin_sister_peaks", "Paired Twin Sister Karst Peaks", "Cặp Đỉnh Núi Song Sinh (3x2)", "并肩连体姊妹双峰", [3, 2], "solid", "admire_twin_peaks", "twin_peaks", None, None),
        ("broad_flat_table_mesa", "Flat-Topped Cloud Mesa (Table Peak)", "Đỉnh Núi Bàn Bằng Phẳng Ngắm Mây (3x3)", "平顶白云大方桌台", [3, 3], "solid", "explore_cloud_mesa", "mesa_peak", None, None),
        ("curved_finger_arch_crag", "Arched Hook Overhanging Finger Peak", "Mỏm Núi Cong Như Ngón Tay (2x2)", "弯如屈指悬空老峰", [2, 2], "solid", "inspect_arch_crag", "arch_crag", None, None),
        ("knife_edge_ridge_crest", "Knife-Edge Razor Crest Segment (3x1)", "Sống Núi Lưỡi Dao Hẹp (3x1)", "利刃薄片山脊梁", [3, 1], "solid", "traverse_knife_ridge", "razor_ridge", None, "wind"),
        ("natural_rock_arch_bridge", "Natural Eroded Karst Bridge over Void", "Cầu Vòm Đá Tự Nhiên Bắc Qua Vực", "天生石拱仙人桥", [3, 2], "walk_surface", "cross_natural_bridge", "natural_bridge", None, None),
        ("balancing_rock_pinnacle", "Impossibly Balanced Perched Boulder Peak", "Khối Đá Nghiêng Kê Trên Đỉnh Núi", "风动险叠飞来孤石", [2, 2], "solid", "inspect_balanced_rock", "balanced_rock", None, "wind"),
        ("crag_cave_eye_perforation", "Karst Peak with Pierced Sky-Eye Hole", "Đỉnh Núi Thủng Mắt Trời Thông Gió", "穿山穿心天门洞", [2, 2], "solid", "gaze_through_sky_eye", "sky_eye_peak", None, "wind"),
        ("summit_meditation_platform", "Peak Summit Flat Daoist Retreat Seat", "Bệ Đá Đỉnh Núi Ngồi Tọa Thiền", "峰头绝顶盘坐平石", [1, 1], "walk_surface", "meditate_on_peak", "meditation_peak", None, "yang"),
        ("spire_base_boulder_skirt", "Spire Base Ring of Weathered Boulders", "Vành Đá Tảng Quanh Chân Núi", "石峰裙边堆叠乱矶", [3, 1], "solid", "climb_spire_base", "peak_base", None, None),
        ("water_rooted_karst_island", "River-Emerging Karst Island Mountain", "Đảo Núi Đá Mọc Từ Lòng Sông", "浮水立根碧水石洲", [3, 3], "solid", "survey_karst_island", "river_karst", None, "water"),
        ("ruined_crag_collapsed_rubble", "Collapsed Karst Peak Avalanche Cone", "Đỉnh Núi Sập Lở Thành Gò Đá Vỡ", "坍塌碎裂巨石崩塌体", [3, 2], "solid", "scramble_avalanche_cone", "collapsed_crag", None, "earth"),
        ("beacon_fire_summit_post", "Peak Top Military Signal Brazier Post", "Đài Khói Phong Hỏa Trên Chóp Núi", "绝顶烽火望哨石墩", [2, 2], "solid", "light_beacon_fire", "summit_beacon", "stone", "fire"),
    ]
    for r_slug, r_en, r_vn, r_hz, r_mat, r_elem in k_regions:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in k_types:
            slug = f"kst_{r_slug}_{t_slug}"
            name = f"{r_en} {t_en}"
            vn = f"{t_vn} ({r_vn})"
            hz = f"{r_hz}{t_hz}"
            p = f"Ancient Chinese karst pinnacle mountain landscape: {name}. Towering verticality, poetic gouache shading, dark ink contour lines, top-down orthographic sprite on transparent background."
            m = mat_override or r_mat
            e = elem_override or r_elem
            items.append(make_asset(cid, slug, name, vn, hz, "karst_spire_and_pinnacle", fp, col, False if col == "walk_surface" else True, "solid", verb, role, False, m, e, p, "structure", "transparent", "bottom_center", {"geology_layer": "karst", "region": r_slug}))

    # 3. boulder_scree_and_pebbles (80 assets)
    b_classes = [
        ("hard_granite", "Grey River Granite", "Đá Hoa Cương Ven Suối", "青灰花岗", "stone", "earth"),
        ("mossy_creek", "Mossy Wet River Stone", "Đá Suối Bám Rêu Xanh", "湿润青苔", "stone", "water"),
        ("weathered_sandstone", "Yellow Sun-Baked Sandstone", "Đá Sa Thạch Nắng Dãi Vàng", "风蚀黄砂", "stone", "wind"),
        ("dark_obsidian_slate", "Dark Iron Mineral Slate", "Đá Phiến Đen Chứa Quặng Sắt", "玄黑铁矿", "stone", "metal"),
    ]
    b_types = [
        ("colossal_monolith_boulder", "Colossal Standing Monolith Boulder", "Khối Đá Tảng Khổng Lồ Độc Lập (2x2)", "大如房屋独立巨岩", [2, 2], "solid", "climb_boulder", "large_boulder", None, None),
        ("rounded_river_boulder", "Smooth Water-Worn River Boulder", "Đá Tảng Tròn Mòn Dòng Nước", "水蚀圆浑大卵石", [1, 1], "solid", "rest_on_rock", "boulder", None, None),
        ("split_lightning_rock_halves", "Boulder Split in Two by Lightning", "Tảng Đá Bị Sét Đánh Tách Đôi", "雷火齐劈两半中分石", [2, 1], "solid", "inspect_split_rock", "split_rock", None, "yang"),
        ("flat_meditation_slab", "Smooth Flat Resting & Meditation Slab", "Phiến Đá Phẳng Tọa Thiền", "平整光洁打坐石床", [2, 1], "walk_surface", "meditate_on_slab", "rest_slab", None, "yang"),
        ("cluster_three_standing_stones", "Trio Cluster of Weathered Stones", "Cụm Ba Hòn Đá Tựa Nhau", "品字聚拢三立石", [2, 2], "solid", "inspect_stone_cluster", "stone_cluster", None, None),
        ("scree_slope_loose_gravel_strip", "Loose Rock Scree Gravel Slip (2x1)", "Thảm Đá Dăm Trôi Dốc (2x1)", "碎裂溜滑砂石滑带", [2, 1], "walk_surface", "scramble_scree", "scree_patch", None, None),
        ("scree_slope_broad_fan", "Broad Talus Scree Avalanche Fan (3x2)", "Gò Đá Sỏi Tràn Sườn Dốc (3x2)", "扇形倾泻倒石碎堆", [3, 2], "walk_surface", "traverse_talus_fan", "talus_fan", None, None),
        ("flat_stepping_stones_path", "Line of Three Stream Stepping Stones", "Hàng Ba Hòn Đá Bước Qua Suối", "过溪三眼嵌水踏脚石", [2, 1], "walk_surface", "cross_stepping_stones", "stepping_stones", None, "water"),
        ("sharp_pointed_crag_stone", "Jagged Upright Spire Rock", "Hòn Đá Nhọn Đâm Ngược Lên", "尖耸出土如笋怪石", [1, 1], "solid", "avoid_sharp_stone", "sharp_rock", None, "metal"),
        ("hollow_weathered_perforated_rock", "Taihu Ornamental Perforated Scholar Rock", "Đá Thái Hồ Đục Lỗ Nghệ Thuật", "漏透玲珑太湖清赏石", [1, 2], "solid", "admire_taihu_rock", "scholar_rock", None, "wind"),
        ("river_gravel_shingle_patch", "Riverbank Oval Pebble Shingle Bed (2x1)", "Bãi Sỏi Tròn Rải Rác Ven Bờ", "水畔椭圆鹅卵石滩", [2, 1], "none", "walk_on_pebbles", "gravel_bed", None, "water"),
        ("iron_ore_veined_boulder", "Heavy Boulder with Glistening Metallic Vein", "Tảng Đá Lộ Gân Quặng Kim Loại", "含银包铁重黑矿石", [1, 1], "solid", "mine_iron_ore", "ore_rock", "iron", "metal"),
        ("fallen_roadblock_boulder", "Avalanche Boulder Blocking Roadway", "Tảng Đá Lăn Chắn Ngang Lối Đi", "滚落挡道崩塌阻路石", [2, 1], "solid", "clear_roadblock_boulder", "roadblock", None, None),
        ("moss_draped_waterline_rock", "Low Wet Stone Lapped by River Waves", "Hòn Đá Nửa Chìm Mép Nước Vỗ", "浸润波纹半露水渚石", [1, 1], "ground_contact", "step_on_waterline_rock", "waterline_rock", None, "water"),
        ("cracked_weathered_shale_pile", "Layered Thin Flaking Shale Plates", "Đống Đá Phiến Tách Lớp Mỏng", "层状剥落页岩碎片堆", [1, 1], "ground_contact", "gather_shale_plates", "shale_plates", None, None),
        ("lichen_crusted_boulder", "Dry Boulder Crusted with Golden Lichen", "Tảng Đá Bám Đầy Rêu Địa Y Vàng", "厚覆金黄干地衣老石", [1, 1], "solid", "inspect_golden_lichen", "lichen_rock", None, "earth"),
        ("hiding_alcove_twin_boulders", "Twin Boulders Forming Hiding Niche", "Hai Hòn Đá Kê Tạo Hốc Trú Thân", "双石夹空可匿身缝", [2, 2], "solid", "hide_between_boulders", "hiding_rocks", None, "yin"),
        ("quarry_chiseled_square_blocks", "Hand-Chiseled Fresh Granite Quarry Blocks", "Khối Đá Đẽo Vuông Chờ Xây Thành", "开山采石规整方料石", [2, 1], "solid", "inspect_quarry_blocks", "quarry_stone", None, "mortal"),
        ("scattered_loose_pebbles_decal", "Scatter of Small Roadside Pebbles Decal", "Vệt Đá Cuội Nhỏ Rải Ven Đường", "细碎路面零落散碎石", [1, 1], "none", "kick_pebbles", "pebble_decal", None, None),
        ("boulder_with_carved_calligraphy", "Mountain Boulder Inscribed with Poetry", "Tảng Đá Khắc Thơ Thư Pháp Đỏ", "摩崖丹砂题刻老岩", [2, 1], "solid", "read_carved_poem", "inscribed_boulder", None, "mortal"),
    ]
    for c_slug, c_en, c_vn, c_hz, c_mat, c_elem in b_classes:
        for t_slug, t_en, t_vn, t_hz, fp, col, verb, role, mat_override, elem_override in b_types:
            slug = f"rck_{c_slug}_{t_slug}"
            name = f"{c_en} {t_en}"
            vn = f"{t_vn} ({c_vn})"
            hz = f"{c_hz}{t_hz}"
            p = f"Ancient Chinese geology boulder prop: {name}. Realistic mineral surface, ink contour line, top-down orthographic game asset, transparent background."
            m = mat_override or c_mat
            e = elem_override or c_elem
            items.append(make_asset(cid, slug, name, vn, hz, "boulder_scree_and_pebbles", fp, col, False if col in ("walk_surface", "none") else True, "transparent" if col == "none" else "solid", verb, role, True if "shale" in t_slug or "scree" in t_slug else False, m, e, p, "prop", "transparent", "bottom_center", {"rock_type": c_slug}))

    # 4. cave_mouth_and_grotto (50 assets)
    cv_types = [
        ("bandit_lair", "Bandit Mountain Lair", "Hang Ổ Sơn Tặc", "匪寨幽洞", "stone", "metal"),
        ("ascetic_hermit", "Daoist Hermit Meditation Cave", "Động Tu Chân Ẩn Sĩ", "隐者仙窟", "stone", "wood"),
        ("water_karst_subterranean", "Water-Dripping Karst Sinkhole", "Hang Karst Nước Chảy Ngầm", "溶水漏斗", "stone", "water"),
        ("ancient_ancestral_tomb", "Plundered Cliff Burial Grotto", "Động Huyền Táng Vách Núi", "崖墓岩洞", "stone", "yin"),
        ("volcanic_fissure", "Sulfur Mineral Fissure Vent", "Khe Nứt Địa Nhiệt Lưu Huỳnh", "硫磺火穴", "stone", "fire"),
    ]
    cv_comps = [
        ("gaping_cavern_mouth_entrance", "Dark Gaping Cavern Mouth Entrance (3x2)", "Cửa Hang Tối Om Rộng Lớn (3x2)", "幽黑张口深岩洞门", [3, 2], "solid", "enter_cavern_depths", "dungeon_entrance", None, None),
        ("cave_mouth_with_log_gate", "Cavern Entrance Fortified with Log Gate", "Cửa Hang Gia Cố Cổng Gỗ Cọc Nhọn", "木栅堵门隐蔽洞口", [3, 2], "solid", "breach_log_gate", "fortified_cave", "wood", "metal"),
        ("shallow_rock_shelter_niche", "Shallow Cliff Undercut Camp Shelter", "Hốc Đá Nông Che Mưa Cắm Trại", "凹坑避雨猎人浅龛", [2, 2], "ground_contact", "shelter_from_rain", "rock_shelter", None, None),
        ("hanging_stalactites_overhang", "Overhanging Cave Lip with Dripping Stalactites", "Mái Hang Nhũ Đá Nhỏ Nước Tí Tách", "洞檐倒挂滴水石钟乳", [2, 1], "solid", "inspect_stalactites", "stalactites", None, "water"),
        ("stalagmite_spire_cluster", "Cluster of Ground-Sprouting Stalagmites", "Cụm Măng Đá Mọc Từ Lòng Hang", "地面拔起石笋簇", [1, 1], "solid", "examine_stalagmites", "stalagmites", None, "earth"),
        ("camp_fire_ash_hearth_cave", "Stone Fire Hearth inside Cave Mouth", "Bếp Lửa Sưởi Ấm Trong Hang", "洞口背风篝火灰烬坑", [1, 1], "ground_contact", "warm_at_cave_hearth", "cave_hearth", "stone", "fire"),
        ("dripping_cave_spring_basin", "Cave Pool Collecting Pure Mineral Water", "Hồ Nước Ngầm Đọng Trong Động", "石洼承滴清冽洞泉池", [2, 1], "none", "drink_cave_spring", "cave_pool", "water", "water"),
        ("camouflaged_vine_cave_door", "Hidden Grotto Mouth Shrouded in Thick Vines", "Cửa Động Giấu Kín Dưới Dây Leo", "垂帘青藤掩映秘密洞", [2, 2], "solid", "part_camouflaged_vines", "secret_cave", "plant", "wood"),
        ("collapsed_cave_boulder_block", "Cave Entrance Choked by Rockfall Debris", "Cửa Hang Bị Đá Sập Bịt Kín Lối", "巨石坍塌封堵洞口", [2, 2], "solid", "clear_cave_blockade", "blocked_cave", None, "earth"),
        ("natural_chimney_light_shaft", "Overhead Ceiling Fissure Venting Daylight", "Lỗ Trời Chiếu Ánh Sáng Xuống Động", "洞顶通天贯日天眼坑", [2, 2], "walk_surface", "bask_in_light_shaft", "light_shaft", None, "yang"),
    ]
    for a_slug, a_en, a_vn, a_hz, a_mat, a_elem in cv_types:
        for c_slug, c_en, c_vn, c_hz, fp, col, verb, role, mat_override, elem_override in cv_comps:
            slug = f"cav_{a_slug}_{c_slug}"
            name = f"{a_en} {c_en}"
            vn = f"{c_vn} ({a_vn})"
            hz = f"{a_hz}{c_hz}"
            p = f"Ancient Chinese mountain cave entrance landscape: {name}. Mysterious shadowy depths, rugged stone edges, ink outlines, top-down orthographic RPG sprite, transparent cutout."
            m = mat_override or a_mat
            e = elem_override or a_elem
            items.append(make_asset(cid, slug, name, vn, hz, "cave_mouth_and_grotto", fp, col, False if "entrance" in c_slug or "pool" in c_slug else True, "solid", verb, role, True if "blocked" in c_slug else False, m, e, p, "structure", "transparent", "bottom_center", {"cave_archetype": a_slug}))

    # 5. waterfall_stream_and_cascade (60 assets)
    w_scales = [
        ("rushing_torrents", "High-Volume Mountain Torrent", "Dòng Thác Cuồn Cuộn Lưng Trời", "怒涛奔涌大悬瀑", "water", "water"),
        ("gentle_cascades", "Gentle Stepped Rocky Cascade", "Dòng Thác Bậc Thang Êm Đềm", "清平迭级叠翠流", "water", "wood"),
        ("hidden_glen_creek", "Shaded Forest Valley Stream", "Khe Suối Thung Lũng U Tịch", "幽谷盘石曲折溪", "water", "yin"),
    ]
    w_elements = [
        ("vertical_fall_drop_2x3", "Vertical Waterfall Drop Wall (2x3)", "Tấm Màn Nước Đổ Thẳng Đứng (2x3)", "两格垂直白练水帘", [2, 3], "solid", "gaze_at_waterfall", "waterfall_wall", None, None),
        ("vertical_fall_drop_3x4", "Monumental Grand Waterfall Sheet (3x4)", "Đại Thác Khổng Lồ Đổ Xuống (3x4)", "三格宏伟排空大瀑布", [3, 4], "solid", "gaze_at_grand_waterfall", "waterfall_wall", None, "yang"),
        ("waterfall_crest_lip_2x1", "Waterfall Overflow Crest Lip (2x1)", "Mép Nước Tràn Đỉnh Thác (2x1)", "瀑布顶口奔涌溢流檐", [2, 1], "walk_surface", "peer_over_waterfall_crest", "waterfall_crest", None, None),
        ("plunge_pool_churning_foam", "Base Plunge Pool Churning Foam Decal (2x2)", "Hồ Chân Thác Bọt Nước Trắng Xóa (2x2)", "瀑脚潭面回旋激荡白波", [2, 2], "none", "watch_churning_foam", "water_splash_decal", None, None),
        ("mist_cloud_splash_spray", "Rising Dense Mist Spray Fog Decal (2x2)", "Màn Sương Nước Bốc Lên Từ Chân Thác", "飞沫如烟腾空水雾团", [2, 2], "none", "feel_water_spray", "mist_decal", None, "wind"),
        ("stepped_cascade_tier_double", "Two-Tier Rocky Cascade Steps (2x2)", "Thác Bậc Thang Đôi Qua Gờ Đá (2x2)", "两级破石翻卷叠水", [2, 2], "solid", "listen_stepped_cascade", "stepped_cascade", None, None),
        ("stepped_cascade_tier_triple", "Three-Tier Sloping Cascade Run (3x2)", "Thác Bậc Thang Ba Cấp (3x2)", "三级跌水如琴弦长阶", [3, 2], "solid", "listen_stepped_cascade", "stepped_cascade", None, None),
        ("rock_choked_rapid_stream", "White-Water Rapids between Jagged Rocks", "Ghềnh Nước Xiết Chen Giữa Đá Nhọn", "暗礁阻截急流险滩", [2, 1], "none", "navigate_rapids", "river_rapids", None, None),
        ("deep_tranquil_emerald_pool", "Deep Emerald Green Mountain Pool (2x2)", "Hồ Nước Xanh Như Ngọc Bích (2x2)", "深幽如玉清澈碧水潭", [2, 2], "none", "meditate_by_emerald_pool", "calm_pool", None, "wood"),
        ("stream_boulder_stepping_chain", "Five Stepping Stones across Mountain Stream", "Chuỗi Năm Hòn Đá Vượt Dòng Suối", "五步横渡流水碇步桥", [3, 1], "walk_surface", "cross_stepping_stones", "stepping_stream", "stone", "earth"),
        ("fallen_tree_creek_bridge", "Mossy Fallen Log Spanning Creek", "Thân Cây Đổ Bắc Ngang Khe Nước", "青苔倒木天然跨溪桥", [3, 1], "walk_surface", "cross_log_bridge", "log_bridge", "wood", "wood"),
        ("brook_split_pebble_island", "Shallow Stream Dividing around Pebble Island", "Suối Cạn Chẻ Đôi Quanh Cồn Cát", "中流击石分叉卵石洲", [2, 2], "none", "explore_pebble_island", "braided_stream", "stone", "earth"),
        ("natural_rock_water_slide", "Polished Slick Bedrock Water Chute", "Máng Trượt Bằng Đá Nước Chảy Xiết", "滑腻石床天然水滑道", [2, 1], "walk_surface", "slide_down_chute", "water_slide", "stone", None),
        ("bamboo_flume_spring_capture", "Mountain Spring Captured in Bamboo Spout", "Máng Tre Hứng Nước Suối Đầu Nguồn", "破竹引泉清甜出水口", [1, 1], "ground_contact", "drink_sweet_spring", "spring_spout", "bamboo", "wood"),
        ("mossy_rock_waterfall_alcove", "Secret Dry Cave Behind Waterfall Curtain", "Hang Khô Bí Mật Đằng Sau Màn Nước", "水帘洞天内藏别有干坤", [2, 2], "ground_contact", "enter_water_curtain_cave", "water_curtain_cave", "stone", "yin"),
        ("river_whirlpool_eddy", "Swirling River Eddy Whirlpool Decal", "Vòng Xoáy Nước Xiết Nguy Hiểm", "江心回旋暗流吸人涡", [2, 2], "none", "avoid_whirlpool", "water_hazard", None, "water"),
        ("gravel_bank_shallows", "Gentle River Gravel Shallows (3x1)", "Bãi Nước Nông Cát Sỏi Dễ Lội Qua", "可徒步涉水碎石浅滩", [3, 1], "walk_surface", "wade_through_shallows", "shallow_crossing", "stone", "earth"),
        ("floating_river_weed_mat", "Patch of River Weeds Trapped in Eddy", "Mảng Rong Suối Nổi Trôi Theo Dòng", "溪边浮萍与长水草垫", [1, 1], "none", "skim_river_weeds", "riverweed_mat", "plant", "wood"),
        ("sunken_timber_snag_water", "Waterlogged Timber Snag in River Current", "Thân Gỗ Chìm Nửa Ngập Lòng Sông", "沉水黑木斜突滞留桩", [2, 1], "none", "inspect_sunken_snag", "submerged_snag", "wood", "yin"),
        ("dry_stony_riverbed_wash", "Dry Season Stony Riverbed Gravel Wash", "Lòng Suối Cạn Trơ Đá Mùa Khô", "枯水季露骨干涸乱石河床", [2, 2], "walk_surface", "cross_dry_riverbed", "dry_riverbed", "stone", "earth"),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in w_scales:
        for e_slug, e_en, e_vn, e_hz, fp, col, verb, role, mat_override, elem_override in w_elements:
            slug = f"wat_{s_slug}_{e_slug}"
            name = f"{s_en} {e_en}"
            vn = f"{e_vn} ({s_vn})"
            hz = f"{s_hz}{e_hz}"
            p = f"Ancient Chinese mountainous water feature: {name}. Flowing crystal water with gouache splashes, dark ink outlines, top-down orthographic game asset on transparent background."
            m = mat_override or s_mat
            e = elem_override or s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "waterfall_stream_and_cascade", fp, col, False if col in ("walk_surface", "none") else True, "transparent", verb, role, False, m, e, p, "structure", "transparent", "bottom_center", {"water_scale": s_slug}))

    return items


# ==============================================================================
# CATEGORY 17: FLORA & FOREST ECOLOGY (250 assets)
# ==============================================================================
def generate_category_17() -> list[dict]:
    items: list[dict] = []
    cid = "flora_and_forest_ecology"

    # 1. ancient_pine_and_conifer (60 assets)
    p_vars = [
        ("huangshan_guest_pine", "Huangshan Welcoming Pine", "Hoàng Sơn Nghênh Khách Tùng", "黄山迎客松", "wood", "wood"),
        ("twisted_ridge_cypress", "Twisted Mountain Ridge Cypress", "Bách Xoắn Sườn Núi Gió Lộng", "苍龙盘旋老崖柏", "wood", "wind"),
        ("umbrella_shaded_pine", "Broad Umbrella Canopy Pine", "Cây Tùng Tán Dù Che Mát", "华盖参天平顶松", "wood", "earth"),
        ("lightning_struck_snag", "Charred Dead Conifer Snag", "Thân Cây Tùng Sét Đánh Trơ Trọi", "雷火烧枯古松桩", "wood", "yang"),
        ("weeping_mountain_hemlock", "Weeping Hemlock Needles", "Tùng Kim Rủ Giọt Sương Rừng", "幽谷垂针铁杉", "wood", "water"),
    ]
    p_postures = [
        ("colossal_ancient_giant_3x3", "Colossal Century-Old Pine Giant (3x3)", "Cổ Thụ Trăm Năm Tùng Đại Thụ (3x3)", "三格百岁参天老古木", [3, 3], "ground_contact", "rest_under_ancient_giant", "landmark_tree", None, None),
        ("mature_stout_tree_2x2", "Mature Stout Mountain Pine (2x2)", "Cây Tùng Trưởng Thành Vững Chãi (2x2)", "双格健硕山崖成年松", [2, 2], "ground_contact", "rest_under_pine_shade", "forest_tree", None, None),
        ("horizontal_cliff_reaching", "Horizontal Branch Reaching over Precipice", "Cành Tùng Vươn Ngang Qua Vách Núi", "横空出世探崖平枝", [2, 2], "ground_contact", "admire_reaching_branch", "scenic_tree", None, None),
        ("twin_intertwined_trunks", "Twin Pine Trunks Intertwined like Dragons", "Cặp Cây Tùng Đôi Quấn Nhau", "连理并蒂双生交缠木", [3, 2], "ground_contact", "admire_twin_dragon_trunks", "twin_tree", None, None),
        ("young_conifer_sapling", "Young Slender Conifer Sapling", "Cây Tùng Non Mới Mọc Thẳng Tắp", "亭亭独立幼年生青松", [1, 1], "ground_contact", "inspect_conifer_sapling", "young_tree", None, None),
        ("bonsai_rock_crevice_dwarf", "Dwarf Bonsai Pine Clinging in Rock Crevice", "Tùng Còi Tự Nhiên Bám Khe Đá", "绝壁石缝天生古盆景", [1, 1], "ground_contact", "admire_cliff_bonsai", "dwarf_tree", None, None),
        ("wind_sheared_one_sided", "Wind-Sheared Flag Pine (Branches on One Side)", "Cây Tùng Tán Cờ Nghiêng Theo Gió", "经年劲风单向旗形松", [2, 2], "ground_contact", "listen_wind_in_pines", "wind_pine", None, "wind"),
        ("fallen_rotten_moss_log", "Fallen Conifer Log Carpeted in Green Moss", "Thân Tùng Đổ Nát Phủ Lớp Rêu Xanh", "倒伏朽烂铺苔厚树干", [3, 1], "walk_surface", "walk_across_fallen_log", "fallen_log", None, "yin"),
        ("hollow_conifer_trunk_refuge", "Hollow Burnt Trunk Offering Hunter Shelter", "Gốc Tùng Rỗng Ruột Trú Ẩn Thợ Săn", "腹空可容一人藏身树洞", [2, 2], "ground_contact", "take_refuge_in_hollow", "hollow_tree", None, None),
        ("pine_cone_drop_scatter", "Ground Drift of Fallen Needles & Pine Cones", "Thảm Kim Tùng & Quả Thông Rơi Đầy Đất", "满地松针黄叶与干松果", [1, 1], "none", "gather_pine_cones", "pine_litter", "plant", "earth"),
        ("dead_spire_snag_crow", "Dead Timber Spire with Black Crow Perch", "Cành Cây Khô Độc Đạo Quạ Đen Đậu", "枯枝干耸乌鸦栖息桩", [1, 2], "ground_contact", "watch_perched_crow", "dead_snag", None, "yin"),
        ("exposed_claw_root_pedestal", "Gnarled Claw Roots Gripping Boulder", "Chùm Rễ Tùng Bám Chặt Tảng Đá", "虬曲如龙盘石裸露树根", [2, 1], "ground_contact", "rest_on_claw_roots", "tree_roots", None, "earth"),
    ]
    for v_slug, v_en, v_vn, v_hz, v_mat, v_elem in p_vars:
        for p_slug, p_en, p_vn, p_hz, fp, col, verb, role, mat_override, elem_override in p_postures:
            slug = f"pin_{v_slug}_{p_slug}"
            name = f"{v_en} {p_en}"
            vn = f"{p_vn} ({v_vn})"
            hz = f"{v_hz}{p_hz}"
            p = f"Ancient Chinese pine tree landscape asset: {name}. Evergreen needle tufts, rough peeling bark, dark ink contours, top-down orthographic RPG sprite on transparent background."
            m = mat_override or v_mat
            e = elem_override or v_elem
            items.append(make_asset(cid, slug, name, vn, hz, "ancient_pine_and_conifer", fp, col, False if col == "none" else True, "transparent", verb, role, True if "dead" in p_slug or "fallen" in p_slug else False, m, e, p, "structure", "transparent", "bottom_center", {"tree_family": "conifer", "variety": v_slug}))

    # 2. bamboo_grove_and_thicket (50 assets)
    bm_vars = [
        ("green_moso_timber", "Giant Green Moso Bamboo", "Tre Mạy Bương Xanh Khổng Lồ", "翠绿巨型毛竹", "bamboo", "wood"),
        ("golden_yellow_bamboo", "Imperial Golden Stalk Bamboo", "Tre Vàng Óng Quý Hiếm", "金黄名贵刚竹", "bamboo", "earth"),
        ("purple_black_bamboo", "Mystic Purple-Black Bamboo", "Trúc Đen Tía Huyền Bí (Tử Trúc)", "紫黑典雅斑竹", "bamboo", "yin"),
        ("slender_reed_bamboo", "Slender Arrow Bamboo Thicket", "Trúc Mũi Tên Thanh Mảnh", "细密丛生箭竹", "bamboo", "wind"),
        ("snapped_war_bamboo", "Battle-Splintered Sharp Bamboo", "Bụi Tre Bị Chém Vỡ Vót Nhọn", "战火劈裂尖锐残竹", "bamboo", "metal"),
    ]
    bm_comps = [
        ("single_tall_culm", "Single Graceful Bamboo Stalk (1x2)", "Một Thân Tre Cao Thẳng (1x2)", "单株挺拔修竹竿", [1, 2], "ground_contact", "chop_timber_bamboo", "bamboo_stalk", None, None),
        ("dense_thicket_cluster_1x1", "Compact Bamboo Thicket Cluster (1x1)", "Khóm Tre Dày Đặc (1x1)", "单格紧密小竹丛", [1, 1], "solid", "inspect_bamboo_cluster", "bamboo_barrier", None, None),
        ("dense_thicket_wall_2x1", "Dense Impassable Bamboo Wall (2x1)", "Hàng Rào Bụi Tre Dày (2x1)", "两格密不透风竹林墙", [2, 1], "solid", "inspect_bamboo_wall", "bamboo_barrier", None, None),
        ("dense_thicket_wall_3x1", "Long Bamboo Grove Screen (3x1)", "Rặng Trúc Râm Mát Dài (3x1)", "三格幽深青翠竹屏障", [3, 1], "solid", "inspect_bamboo_screen", "bamboo_barrier", None, None),
        ("wind_swaying_arch_culms", "Arched Bamboo Stalks Swaying in Wind", "Cành Tre Uốn Cong Đung Đưa Theo Gió", "风动弯躬翠叶婆娑竹", [2, 2], "ground_contact", "listen_rustling_bamboo", "bamboo_arch", None, "wind"),
        ("clearing_bamboo_circle", "Natural Circular Bamboo Grove Clearing", "Khoảng Đất Trống Giữa Rừng Trúc", "环回清修幽境竹心空地", [3, 3], "ground_contact", "meditate_in_bamboo_clearing", "bamboo_grove", None, "wood"),
        ("fresh_spring_shoots_cluster", "Cluster of Crisp Emerging Spring Shoots", "Bụi Măng Non Mới Nhú Mùa Xuân", "春雨初发破土鲜笋尖", [1, 1], "none", "harvest_spring_shoots", "bamboo_shoots", "plant", "wood"),
        ("chopped_bamboo_stumps_ground", "Ground Patch of Cut Bamboo Stumps", "Đám Gốc Tre Bị Đốn Bằng Rìu", "砍伐削平带露竹桩地", [1, 1], "ground_contact", "inspect_cut_stumps", "bamboo_stumps", None, None),
        ("carpet_fallen_bamboo_leaves", "Thick Yellow Carpet of Fallen Bamboo Leaves", "Thảm Lá Tre Rụng Vàng Rực", "满地干燥金黄竹叶毯", [2, 1], "none", "walk_on_bamboo_carpet", "bamboo_litter", "plant", "earth"),
        ("sharpened_bamboo_punji_trap", "Concealed Sharpened Bamboo Stake Trap", "Hố Bẫy Chông Tre Vót Nhọn", "陷坑插置尖刺竹签阵", [1, 1], "none", "disarm_punji_trap", "punji_trap", None, "metal"),
    ]
    for v_slug, v_en, v_vn, v_hz, v_mat, v_elem in bm_vars:
        for c_slug, c_en, c_vn, c_hz, fp, col, verb, role, mat_override, elem_override in bm_comps:
            slug = f"bam_{v_slug}_{c_slug}"
            name = f"{v_en} {c_en}"
            vn = f"{c_vn} ({v_vn})"
            hz = f"{v_hz}{c_hz}"
            p = f"Ancient Chinese bamboo grove vegetation: {name}. Slender culms with delicate fluttering green leaves, dark ink contours, top-down orthographic game asset on transparent background."
            m = mat_override or v_mat
            e = elem_override or v_elem
            items.append(make_asset(cid, slug, name, vn, hz, "bamboo_grove_and_thicket", fp, col, False if col == "none" else True, "transparent", verb, role, True if "trap" in c_slug else False, m, e, p, "structure", "transparent", "bottom_center", {"bamboo_variety": v_slug}))

    # 3. underbrush_fern_and_creeper (50 assets)
    ub_groups = [
        ("mountain_bracken_fern", "Mountain Bracken & Maidenhair Ferns", "Dương Xỉ Núi & Ráng Cây", "深山凤尾蕨草", "plant", "wood"),
        ("flowering_wild_azalea", "Flowering Mountain Azalea Shrubs", "Bụi Hoa Đỗ Quyên Rừng Nở Rực", "艳红高山映山红", "plant", "fire"),
        ("climbing_green_ivy", "Climbing Wall Ivy & Creepers", "Dây Thường Xuân Leo Tường Đá", "络石爬藤绿蔓", "plant", "earth"),
        ("thorny_blackberry_briar", "Thorny Mountain Bramble & Briars", "Bụi Gai Góc Rừng Sâu Rậm Rạp", "尖刺密布野荆棘", "plant", "metal"),
        ("fragrant_wild_camellia", "Fragrant Wild Winter Camellia", "Trà My Rừng Mùa Đông Tỏa Hương", "耐冬傲霜野山茶", "plant", "water"),
    ]
    ub_comps = [
        ("dense_shrub_patch_1x1", "Dense Rounded Shrub Bush (1x1)", "Bụi Cây Tròn Dày Đặc (1x1)", "单格团簇茂密矮灌木", [1, 1], "ground_contact", "inspect_shrub", "underbrush"),
        ("broad_undergrowth_patch_2x1", "Broad Underbrush Foliage Strip (2x1)", "Dải Cây Bụi Dày Liền Nhau (2x1)", "双格横生低矮灌木带", [2, 1], "ground_contact", "inspect_undergrowth", "underbrush"),
        ("sprawling_brier_patch_2x2", "Sprawling Thorny Thicket Patch (2x2)", "Vạt Cây Bụi Lan Rộng (2x2)", "四方盘结大蓬灌木丛", [2, 2], "ground_contact", "navigate_brier_patch", "underbrush"),
        ("climbing_creeper_on_tree", "Creepers Wrapping Around Tree Trunk", "Dây Leo Quấn Chặt Thân Cây Cổ", "附木攀援老藤条缠树", [1, 2], "ground_contact", "climb_tree_creeper", "tree_creeper"),
        ("draped_creeper_on_boulder", "Trailing Ivy Draped over Grey Rock", "Dây Leo Buông Xõa Trùm Lên Đá", "垂挂蔓生覆石蔓藤", [1, 1], "ground_contact", "inspect_rock_creeper", "rock_creeper"),
        ("low_ground_carpet_ferns", "Lush Ground Carpet of Wild Green Ferns", "Thảm Dương Xỉ Xanh Rì Bám Đất", "林下成片碧绿蕨菜丛", [2, 1], "none", "gather_bracken_fern", "fern_carpet"),
        ("flowering_spring_blossom_bush", "Bush Heavy with Radiant Spring Flowers", "Bụi Cây Đang Nở Hoa Rực Rỡ", "繁花盛开明艳春景灌木", [1, 1], "ground_contact", "smell_blossom_fragrance", "flower_bush"),
        ("autumn_berry_laden_bramble", "Bramble Loaded with Ripe Wild Berries", "Bụi Cây Trĩu Quả Dại Chín Đỏ", "挂满朱红多汁野果丛", [1, 1], "ground_contact", "gather_wild_berries", "berry_bush"),
        ("dry_withered_winter_twigs", "Winter Dried Thorny Tangle of Bare Twigs", "Cụm Gai Khô Khẳng Khiu Mùa Đông", "干枯落叶寒冬刺条堆", [1, 1], "ground_contact", "gather_dry_kindling", "dead_shrub"),
        ("trampled_flattened_foliage", "Trampled Wildlife Trail through Underbrush", "Vạt Cây Bụi Bị Thú Rừng Giẫm Bẹp", "野兽践踏踏平踩道草丛", [2, 1], "none", "track_wildlife_trail", "animal_trail"),
    ]
    for g_slug, g_en, g_vn, g_hz, g_mat, g_elem in ub_groups:
        for c_slug, c_en, c_vn, c_hz, fp, col, verb, role in ub_comps:
            slug = f"und_{g_slug}_{c_slug}"
            name = f"{g_en} {c_en}"
            vn = f"{c_vn} ({g_vn})"
            hz = f"{g_hz}{c_hz}"
            p = f"Ancient Chinese forest underbrush vegetation: {name}. Organic foliage, delicate leaves and flowers, ink outlines, top-down orthographic game asset on transparent background."
            items.append(make_asset(cid, slug, name, vn, hz, "underbrush_fern_and_creeper", fp, col, False, "transparent", verb, role, False, g_mat, g_elem, p, "prop", "transparent", "bottom_center", {"foliage_group": g_slug}))

    # 4. aquatic_lotus_and_wetland_reed (40 assets)
    aq_types = [
        ("sacred_pink_lotus", "Sacred Blooming Pink Lotus", "Sen Hồng Thắm Nở Rộ Mặt Hồ", "十里荷香粉红莲", "plant", "water"),
        ("white_pure_lotus", "Purity White Snow Lotus Lake", "Sen Trắng Tinh Khiết Đầm Nước", "冰清玉洁千叶白莲", "plant", "metal"),
        ("wetland_cattail_marsh", "River Delta Cattail Reed Marsh", "Đầm Lầy Lau Sậy Đầy Nước", "水泽香蒲丰茂苇荡", "plant", "earth"),
        ("autumn_withered_lotus", "Autumn Rain Withered Lotus Lake", "Đầm Sen Tàn Lá Rách Mùa Thu", "秋雨听残破荷枯叶", "plant", "yin"),
    ]
    aq_comps = [
        ("broad_floating_pads_cluster", "Cluster of Broad Emerald Floating Lotus Pads", "Cụm Lá Sen Tròn Xanh Nổi Mặt Nước", "浮水团团碧绿大荷叶", [2, 2], "none", "pick_lotus_pad", "lotus_pads", None, None),
        ("single_proud_blossom_flower", "Single Magnificent Blossom on High Stalk", "Bông Sen Nở Xòe Trên Cuống Cao", "擎雨出水盛开大莲花", [1, 1], "none", "admire_lotus_blossom", "lotus_flower", None, None),
        ("half_opened_lotus_bud", "Slender Tapered Pink Lotus Flower Bud", "Búp Sen Non E Ấp Chưa Nở", "含苞待放尖角小荷芽", [1, 1], "none", "admire_lotus_bud", "lotus_bud", None, None),
        ("dried_autumn_seedpod_stalk", "Ripe Drying Lotus Seedpod on Stiff Stalk", "Bát Sen Già Chứa Hạt Ngon", "结子干枯老莲蓬头", [1, 1], "none", "harvest_lotus_seeds", "seedpod", None, None),
        ("mixed_pads_and_blooms_colony", "Dense Colony of Intermingled Pads and Blooms", "Thảm Sen Rậm Rạp Hoa Lá Chen Chúc (3x2)", "接天莲叶映日大荷塘", [3, 2], "none", "survey_lotus_colony", "lotus_colony", None, None),
        ("tall_cattail_reed_cluster_1x1", "Dense Cluster of Tall Brown Cattails (1x1)", "Khóm Cỏ Nến Nâu Vươn Cao (1x1)", "直立水畔长穗香蒲草", [1, 1], "ground_contact", "hide_in_cattails", "cattails", None, None),
        ("riverbank_reed_bed_wall_2x1", "Thick Wall of Riverbank Wetland Reeds (2x1)", "Rặng Sậy Dày Đặc Ngăn Nước (2x1)", "茂密掩映芦苇屏障带", [2, 1], "solid", "hide_in_reed_bed", "reed_wall", None, None),
        ("white_pampas_grass_plumes", "Flowering White Feathered Reed Plumes", "Bông Lau Trắng Bay Theo Gió Chiều", "迎风飘洒白茫茫芦花", [2, 1], "ground_contact", "watch_pampas_in_wind", "pampas_plumes", None, "wind"),
        ("duckweed_blanket_decal", "Vibrant Green Duckweed Blanket on Water", "Thảm Bèo Tấm Xanh Kín Mặt Ao", "浮游水面细碎绿浮萍", [2, 2], "none", "skim_duckweed", "duckweed_mat", None, "water"),
        ("submerged_water_celery_patch", "Shallow Riverbed Water Celery & Lily Patch", "Vạt Rau Cần Nước & Hoa Súng Cạn", "清流见底水芹与萍蓬", [2, 1], "none", "gather_water_celery", "water_herbs", None, "water"),
    ]
    for t_slug, t_en, t_vn, t_hz, t_mat, t_elem in aq_types:
        for c_slug, c_en, c_vn, c_hz, fp, col, verb, role, mat_override, elem_override in aq_comps:
            slug = f"wat_{t_slug}_{c_slug}"
            name = f"{t_en} {c_en}"
            vn = f"{c_vn} ({t_vn})"
            hz = f"{t_hz}{c_hz}"
            p = f"Ancient Chinese wetland aquatic flora: {name}. Delicate water reflection, ink outlines, top-down orthographic game asset on transparent background."
            m = mat_override or t_mat
            e = elem_override or t_elem
            items.append(make_asset(cid, slug, name, vn, hz, "aquatic_lotus_and_wetland_reed", fp, col, False if col == "none" else True, "transparent", verb, role, False, m, e, p, "prop", "transparent", "bottom_center", {"wetland_type": t_slug}))

    # 5. mountain_medicinal_herb_wild (50 assets)
    hb_species = [
        ("century_wild_ginseng", "Mountain Century Wild Ginseng", "Nhân Sâm Núi Trăm Năm", "长白山百年野山参", "plant", "earth"),
        ("immortal_purple_lingzhi", "Cliffside Immortal Purple Lingzhi", "Linh Chi Tím Bất Tử Vách Đá", "悬崖九品紫芝仙草", "plant", "yang"),
        ("dragon_blood_fleeceflower", "Dragon-Blood Knotweed (He Shou Wu)", "Hà Thủ Ô Huyết Long Hóa Rồng", "何首乌盘结龙血根", "plant", "wood"),
        ("tianshan_snow_lotus", "Tianshan Glacial Snow Lotus", "Tuyết Liên Hoa Băng Đỉnh Thiên Sơn", "天山绝顶傲霜雪莲", "plant", "metal"),
        ("cliff_iron_skin_dendrobium", "Cliff Iron-Skin Dendrobium Orchid", "Thạch Hộc Thiết Bì Mọc Vách Đá", "雁荡绝壁铁皮石斛", "plant", "water"),
    ]
    hb_stages = [
        ("single_mature_herb_shoot", "Single Mature Harvestable Herb Shoot", "Mầm Thuốc Trưởng Thành Sẵn Sàng Hái", "单株饱满待采灵药苗", [1, 1], "ground_contact", "harvest_medicinal_herb", "herb_harvestable"),
        ("seedling_wild_sprout", "Delicate Emerging Wild Seedling Sprout", "Cây Thuốc Non Mới Mọc Yếu Ớt", "含苞初发纤弱幼药芽", [1, 1], "none", "inspect_herb_seedling", "herb_seedling"),
        ("hidden_root_clump_under_stone", "Medicinal Root Knot Exposed under Boulder", "Chùm Rễ Thuốc Lộ Dưới Tảng Đá", "石缝盘根虬结药疙瘩", [1, 1], "ground_contact", "dig_medicinal_root", "herb_root"),
        ("red_berry_seeded_stem", "Mature Stem Laden with Ripe Scarlet Seed Berries", "Cành Thuốc Trĩu Quả Hạt Đỏ Mọng", "顶生朱红累累灵药籽", [1, 1], "ground_contact", "gather_herb_seeds", "herb_seeds"),
        ("twin_conjoined_herbs", "Rare Pair of Twin Conjoined Sacred Herbs", "Cặp Thuốc Quý Song Sinh Liền Gốc", "并蒂连根并生双宝药", [1, 1], "ground_contact", "harvest_twin_herbs", "twin_herbs"),
        ("medicinal_patch_in_moss", "Dense Medicinal Cluster Nestled in Green Moss", "Khóm Thuốc Nhỏ Giữa Thảm Rêu Ẩm", "青苔湿润护持小药圃", [2, 1], "ground_contact", "gather_moss_herb_patch", "herb_patch"),
        ("dried_withered_herb_stalk", "Withered Winter Stalk with Dormant Underground Root", "Cành Thuốc Khô Đông Chờ Xuân Nở", "枯萎假死冬眠宿根桩", [1, 1], "none", "inspect_withered_herb", "withered_herb"),
        ("trampled_damaged_herb", "Herb Bruised by Mountain Beast Hooves", "Cây Thuốc Bị Thú Dẫm Gãy Cành", "兽蹄踩折残损药草丛", [1, 1], "none", "salvage_damaged_herb", "damaged_herb"),
        ("rare_thousand_year_king_specimen", "Legendary Thousand-Year Herb King Specimen (2x2)", "Vua Thuốc Ngàn Năm Tỏa Ánh Linh Quang (2x2)", "千年成精宝光药王桩", [2, 2], "ground_contact", "harvest_immortal_king_herb", "legendary_herb"),
        ("wild_herb_drying_flat_rock", "Flat Sun-Warmed Rock with Freshly Plucked Herbs", "Phiến Đá Nắng Phơi Thuốc Vừa Hái", "向阳温石摊晾鲜药草", [2, 1], "walk_surface", "turn_drying_herbs", "drying_herbs"),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in hb_species:
        for st_slug, st_en, st_vn, st_hz, fp, col, verb, role in hb_stages:
            slug = f"hrb_{s_slug}_{st_slug}"
            name = f"{s_en} {st_en}"
            vn = f"{st_vn} ({s_vn})"
            hz = f"{s_hz}{st_hz}"
            p = f"Ancient Chinese valuable mountain medicinal herb: {name}. Botanical accuracy, luminous gouache accents, ink contours, top-down orthographic game prop on transparent background."
            e = "yang" if "thousand_year" in st_slug else s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "mountain_medicinal_herb_wild", fp, col, False, "transparent", verb, role, True if "damaged" in st_slug else False, s_mat, e, p, "prop", "transparent", "bottom_center", {"species": s_slug}))

    return items


# ==============================================================================
# CATEGORY 18: URBAN STREET & MARKET (250 assets)
# ==============================================================================
def generate_category_18() -> list[dict]:
    items: list[dict] = []
    cid = "urban_street_and_market"

    # 1. market_stall_and_hawker_booth (60 assets)
    m_genres = [
        ("steamed_dumpling_baozi", "Steamed Bun & Dumpling Stall", "Sạp Bánh Bao Nóng Hổi", "热腾包子蒸笼档", "wood", "fire"),
        ("fresh_river_fishmonger", "Fresh Fish & Seafood Monger", "Sạp Bán Cá Tươi Sống", "活水鱼鲜海味摊", "wood", "water"),
        ("butcher_hanging_meat", "Butcher Shop & Carcass Rack", "Phản Thịt Heo & Thịt Bò Treo Móc", "肉案悬钩屠夫档", "wood", "metal"),
        ("green_vegetable_produce", "Farm Produce & Fruit Basket", "Sạp Rau Củ Quả Nhà Nông", "新鲜果蔬水灵摊", "bamboo", "earth"),
        ("silk_cloth_tailoring", "Textile & Folded Silk Draper", "Sạp Vải Vóc Lụa Là Tươi Đẹp", "绫罗绸缎锦匹案", "cloth", "mortal"),
        ("ceramic_crockery_merchant", "Glazed Ceramics & Pottery Stand", "Sạp Bát Đĩa Gốm Sứ Bày Bán", "瓷碗陶壶日用铺", "ceramic", "earth"),
    ]
    m_comps = [
        ("portable_shoulder_yoke_baskets", "Pair of Woven Baskets on Bamboo Shoulder Yoke", "Cặp Gánh Tre Đan Trên Đòn Gánh", "挑担前后双竹篾筐", [2, 1], "ground_contact", "inspect_yoke_baskets", "hawker_yoke", "bamboo", None),
        ("folding_wooden_market_table", "Low Folding Wooden Trestle Table with Goods", "Bàn Gỗ Xếp Bày Hàng Chợ", "支腿木质平摆案板", [2, 1], "solid", "browse_market_table", "market_table", "wood", None),
        ("canopy_covered_bamboo_stall", "Stall with Striped Hemp Sunshade Canopy (2x2)", "Sạp Hàng Có Mái Bạt Che Nắng (2x2)", "麻布撑顶四方小货摊", [2, 2], "solid", "browse_canopy_stall", "canopy_stall", "cloth", None),
        ("three_tier_stepped_display_rack", "Three-Tier Wooden Stepped Produce Display", "Kệ Gỗ Ba Tầng Bày Hàng Bắt Mắt", "三级层叠阶梯陈列架", [2, 1], "solid", "inspect_display_rack", "display_rack", "wood", None),
        ("overflowing_woven_bamboo_crates", "Pair of Round Baskets Overflowing with Goods", "Cặp Thúng Tre Đầy Ắp Hàng Hóa", "圆篾筐堆满货物两只", [1, 1], "ground_contact", "inspect_produce_crates", "produce_crates", "bamboo", None),
        ("hand_cranked_balance_scales", "Brass Balance Scales on Iron Hook Tripod", "Cân Cán Đồng Treo Giá Sắt Đứng Cân Hàng", "铜盘立架折吊天平秤", [1, 1], "ground_contact", "weigh_goods_scale", "trade_scale", "bronze", "metal"),
        ("merchant_folding_wooden_stool", "Low Folding Wooden Merchant Stool & Teapot", "Ghế Đẩu Gỗ Gấp Kèm Ấm Trà", "商贩歇脚矮木马扎", [1, 1], "ground_contact", "sit_on_stool", "seating", "wood", "mortal"),
        ("hanging_dried_produce_line", "Overhead Line of Hanging Dried Goods", "Dây Treo Hàng Khô Ngang Trán", "摊顶横挂干货串排", [2, 1], "solid", "examine_hanging_goods", "hanging_goods", "plant", None),
        ("brazier_charcoal_cooking_pot", "Glowing Clay Charcoal Stove with Iron Cauldron", "Bếp Than Nướng Đang Đỏ Lửa Nấu Nướng", "红泥小火炉滚沸汤锅", [1, 1], "solid", "warm_hands_brazier", "cooking_hearth", "iron", "fire"),
        ("unattended_hastily_closed_stall", "Hastily Abandoned Stall with Scattered Goods", "Sạp Hàng Bị Bỏ Chạy Hàng Hóa Rơi Vãi", "仓皇弃置凌乱残货摊", [2, 1], "solid", "search_abandoned_stall", "abandoned_stall", "wood", "yin"),
    ]
    for g_slug, g_en, g_vn, g_hz, g_mat, g_elem in m_genres:
        for c_slug, c_en, c_vn, c_hz, fp, col, verb, role, mat_override, elem_override in m_comps:
            slug = f"mkt_{g_slug}_{c_slug}"
            name = f"{g_en} {c_en}"
            vn = f"{c_vn} ({g_vn})"
            hz = f"{g_hz}{c_hz}"
            p = f"Ancient Chinese urban street market asset: {name}. Detailed mercantile props, gouache textures with ink line accents, orthographic top-down view, clean transparent background."
            m = mat_override or g_mat
            e = elem_override or g_elem
            items.append(make_asset(cid, slug, name, vn, hz, "market_stall_and_hawker_booth", fp, col, True if col == "solid" else False, "transparent", verb, role, True if "abandoned" in c_slug else False, m, e, p, "structure", "transparent", "bottom_center", {"market_genre": g_slug}))

    # 2. shop_sign_board_and_banner (60 assets)
    s_types = [
        ("wine_tavern_spirit", "Wine Tavern & Alehouse", "Quán Rượu Tửu Quán", "太白杏花酒家", "cloth", "water"),
        ("apothecary_herb_pharmacy", "Herbal Pharmacy & Clinic", "Tiệm Thuốc Bắc Nhân Hòa", "济世仁心药肆", "wood", "wood"),
        ("pawnshop_finance_exchange", "Pawnshop & Silver Exchange", "Tiệm Cầm Đồ Đương Phố", "万通典当银号", "wood", "metal"),
        ("blacksmith_ironmonger", "Blacksmith & Weapon Armory", "Tiệm Rèn Đao Kiếm Binh Khí", "神锋百炼铁铺", "iron", "fire"),
        ("teahouse_scholar_retreat", "Teahouse & Storyteller Stage", "Trà Quán Thính Phòng", "春雨煮茗茶坊", "bamboo", "earth"),
        ("inn_guest_lodging", "Jianghu Caravanserai Inn", "Khách Điếm Giang Hồ", "悦来四海客栈", "silk", "mortal"),
    ]
    s_signs = [
        ("vertical_hanging_carved_plaque", "Vertical Carved Lacquer Signboard with Gold Characters", "Biển Hiệu Dọc Bằng Gỗ Khắc Chữ Vàng", "悬壁黑漆描金竖招牌", [1, 2], "ground_contact", "read_lacquer_plaque", "hanging_sign", "lacquer", "mortal"),
        ("triangular_cloth_swallowtail_flag", "Triangular Cloth Trade Pennant on Bamboo Pole", "Cờ Hiệu Vải Tam Giác Cắm Cọc Tre", "挑出青布燕尾酒旗帜", [1, 1], "ground_contact", "watch_trade_flag", "shop_flag", "cloth", "wind"),
        ("large_square_tavern_banner", "Large Square Canvas Trade Banner Billowing", "Đại Kỳ Vải Vuông Bay Phấp Phới", "宽大迎风招展字号幡", [1, 2], "ground_contact", "watch_tavern_banner", "shop_banner", "cloth", "wind"),
        ("carved_symbolic_trade_emblem", "Carved Wooden Trade Emblem Figure (Fish/Mortar)", "Biển Hiệu Hình Vật Tượng Trưng (Cá/Cối)", "立体圆雕行当标志木象", [1, 1], "ground_contact", "inspect_trade_emblem", "emblem_sign", "wood", None),
        ("painted_oilpaper_hanging_lantern", "Round Red Oilpaper Lantern with Black Character", "Đèn Lồng Giấy Dầu Đỏ Viết Tên Hiệu", "透光红油纸店名圆灯笼", [1, 1], "ground_contact", "light_paper_lantern", "paper_lantern", "paper", "yang"),
        ("pair_ornate_palace_lanterns", "Pair of Octagonal Gilded Horn Palace Lanterns", "Cặp Đèn Lồng Cung Đình Bát Giác", "门前悬挂双八角雕宫灯", [2, 1], "ground_contact", "inspect_palace_lanterns", "palace_lanterns", "silk", "yang"),
        ("standing_a_frame_chalkboard", "Wooden A-Frame Roadside Price Notice Board", "Bảng Gỗ Chữ A Để Giá Hàng Ven Đường", "立地人字木价目水牌", [1, 1], "ground_contact", "read_price_chalkboard", "menu_board", "wood", "mortal"),
        ("post_mounted_iron_lantern_bracket", "Wrought-Iron Lamp Bracket Extends from Wall", "Giá Đèn Sắt Mỹ Thuật Vươn Ra Từ Tường", "墙头挑铁花油灯支架", [1, 1], "ground_contact", "inspect_iron_lamp_bracket", "wall_lamp", "iron", "fire"),
        ("tattered_storm_torn_flag", "Faded Tattered Shop Flag Shredded by Storm", "Cờ Tiệm Bạc Màu Rách Tả Tơi Sau Bão", "风雨残蚀褪色破布幌子", [1, 1], "ground_contact", "inspect_tattered_flag", "tattered_flag", "cloth", "wind"),
        ("multi_tiered_festival_lantern_pole", "Tall Festival Pole Strung with Six Red Lanterns", "Cột Cao Treo Chùm Sáu Đèn Lồng Đỏ", "高耸六级连串节庆灯竿", [1, 3], "ground_contact", "admire_festival_lantern_pole", "festival_pole", "bamboo", "yang"),
    ]
    for b_slug, b_en, b_vn, b_hz, b_mat, b_elem in s_types:
        for c_slug, c_en, c_vn, c_hz, fp, col, verb, role, mat_override, elem_override in s_signs:
            slug = f"sgn_{b_slug}_{c_slug}"
            name = f"{b_en} {c_en}"
            vn = f"{c_vn} ({b_vn})"
            hz = f"{b_hz}{c_hz}"
            p = f"Ancient Chinese commercial street sign asset: {name}. Traditional calligraphy, vibrant cloth or weathered timber, ink outlines, top-down orthographic game sprite, transparent background."
            m = mat_override or b_mat
            e = elem_override or b_elem
            items.append(make_asset(cid, slug, name, vn, hz, "shop_sign_board_and_banner", fp, col, False, "transparent", verb, role, True if "tattered" in c_slug else False, m, e, p, "prop", "transparent", "bottom_center", {"business_type": b_slug}))

    # 3. street_furniture_and_wellhead (70 assets)
    sf_groups = [
        ("water_wells_and_cisterns", "Public Wells & Water Cisterns", "Giếng Nước & Bể Chữa Cháy", "水井消防池", "stone", "water"),
        ("public_announcements", "Imperial Noticeboards & Steles", "Bảng Cáo Thị & Bia Đá", "告示公堂桩", "wood", "mortal"),
        ("seating_and_rest_stops", "Street Benches & Rest Shelters", "Ghế Đá & Đình Nghỉ Dừng Chân", "街头长凳廊", "stone", "earth"),
        ("horse_and_convoy_gear", "Hitching Posts & Cart Accessories", "Cột Buộc Ngựa & Tiện Ích Xe Cộ", "栓马系车架", "stone", "metal"),
        ("fire_prevention_braziers", "Night Watch Braziers & Torches", "Bếp Lửa Sưởi & Đuốc Tuần Tra", "夜巡防冻盆", "iron", "fire"),
        ("waste_and_drainage_grates", "Drainage Canals & Stone Slabs", "Cống Rãnh & Phiến Đá Đậy Nắp", "排洪石箅沟", "stone", "water"),
        ("memorial_stone_lions", "Street Corner Guardian Statuary", "Sư Tử Đá Trấn Góc Phố", "避邪小石狮", "stone", "yang"),
    ]
    sf_comps = [
        ("octagonal_carved_stone_well", "Octagonal Carved Granite Wellhead with Winch", "Giếng Đá Bát Giác Kèm Trục Kéo Nước", "八角雕纹辘轳古井", [2, 2], "solid", "draw_well_water", "wellhead", "stone", "water"),
        ("round_village_brick_well", "Round Village Brick Well with Wooden Bucket", "Giếng Gạch Tròn Kèm Thùng Gỗ Múc Nước", "红砖圆砌木桶水井", [1, 1], "solid", "draw_well_water", "wellhead", "brick", "water"),
        ("stone_cistern_fire_prevention", "Great Stone Water Vat for Firefighting (2x1)", "Bể Đá Chứa Nước Chữa Cháy Cứu Hỏa", "蓄水防火青石大缸", [2, 1], "solid", "inspect_fire_cistern", "fire_cistern", "stone", "water"),
        ("clothes_washing_stone_slab", "Flat River Granite Slab for Beating Clothes", "Phiến Đá Giặt Giũ Quần Áo Ven Rãnh", "平滑捣衣青石板", [1, 1], "walk_surface", "wash_clothes_on_slab", "wash_slab", "stone", "water"),
        ("roofed_imperial_notice_board", "Shingled Timber Public Bounty Noticeboard", "Bảng Dán Cáo Thị Triều Đình Có Mái", "披檐悬榜官方告示牌", [2, 1], "solid", "read_imperial_notice", "noticeboard", "wood", "mortal"),
        ("roadside_stone_milestone_post", "Carved Roadside Distance Milestone Stele", "Cột Mốc Đá Báo Dặm Đường (Thập Lý)", "道旁指路十里路碑", [1, 1], "ground_contact", "read_milestone_stele", "milestone", "stone", "mortal"),
        ("stone_lion_headed_hitching_post", "Carved Stone Horse Hitching Post with Lion Finial", "Cột Buộc Ngựa Đầu Sư Tử Bằng Đá", "拴马望头小石狮桩", [1, 1], "ground_contact", "tie_mount_post", "hitching_post", "stone", "metal"),
        ("long_granite_street_bench", "Solid Three-Slab Granite Street Rest Bench", "Ghế Đá Dài Dành Cho Khách Bộ Hành", "青石条砌街头休歇凳", [2, 1], "walk_surface", "rest_on_street_bench", "rest_bench", "stone", "earth"),
        ("night_watchman_gong_bell_stand", "Watchman Bronze Gong Stand on Street Corner", "Giá Treo Thanh La Của Người Điểm Canh", "更夫敲锣挂铃打更架", [1, 1], "ground_contact", "strike_watchman_gong", "watchman_gong", "bronze", "metal"),
        ("incense_burning_roadside_altar", "Small Brick Roadside Spirit Incense Niche", "Miếu Nhỏ Thắp Nhang Trừ Ma Ven Đường", "街角砖砌敬天香炉龛", [1, 1], "solid", "light_incense_altar", "roadside_altar", "brick", "yang"),
    ]
    for g_slug, g_en, g_vn, g_hz, g_mat, g_elem in sf_groups:
        for c_slug, c_en, c_vn, c_hz, fp, col, verb, role, mat_override, elem_override in sf_comps:
            slug = f"fur_{g_slug}_{c_slug}"
            name = f"{g_en} {c_en}"
            vn = f"{c_vn} ({g_vn})"
            hz = f"{g_hz}{c_hz}"
            p = f"Ancient Chinese urban street furniture: {name}. Realistic civic utility styling, ink outlines, top-down orthographic game asset, transparent background."
            m = mat_override or g_mat
            e = elem_override or g_elem
            items.append(make_asset(cid, slug, name, vn, hz, "street_furniture_and_wellhead", fp, col, False if col == "walk_surface" else True, "transparent", verb, role, False, m, e, p, "structure", "transparent", "bottom_center", {"furniture_group": g_slug}))

    # 4. litter_wheel_rut_and_puddle (60 assets)
    lt_conds = [
        ("muddy_rain_ruts", "Rainy Season Deep Mud Rut", "Vết Bánh Xe Lún Bùn Mùa Mưa", "泥泞雨季辙", "earth", "water"),
        ("market_debris_waste", "Market End Organic Waste", "Rác Rưởi Tan Chợ Vương Vãi", "散市残菜叶", "plant", "earth"),
        ("construction_rubble", "Building Masonry & Sand Rubble", "Cát Sỏi Vật Liệu Xây Dựng", "泥水工匠渣", "stone", "mortal"),
        ("spilled_goods_stain", "Spilled Merchant Goods Stain", "Vết Rơi Vãi Hàng Hóa Buôn Bán", "倾覆遗落迹", "ceramic", "fire"),
        ("autumn_fallen_litter", "Autumn Fallen Leaves & Straw", "Lá Rụng Mùa Thu & Rơm Rạ Bẩn", "晚秋干草落", "straw", "yin"),
        ("frost_winter_ruts", "Winter Frost Dusted Ground Ruts", "Vệt Bánh Xe Đóng Băng Tuyết Mùa Đông", "隆冬积雪冻车辙", "earth", "metal"),
    ]
    lt_decals = [
        ("deep_cart_wheel_rut_straight", "Deep Parallel Cart Wheel Ruts (2x1)", "Vết Hằn Bánh Xe Ngựa Đôi Thẳng (2x1)", "平行深陷车辙直印", [2, 1], "none", "inspect_cart_ruts", "rut_decal", "earth", None),
        ("turning_cart_wheel_rut_curve", "Curved Wheel Ruts Showing Turning Wagons", "Vết Hằn Bánh Xe Uốn Cong Lượn Lối", "转向交错弯曲泥辙", [2, 2], "none", "inspect_cart_ruts", "rut_decal", "earth", None),
        ("muddy_water_puddle_reflection", "Muddy Rain Puddle with Sky Water Reflection", "Vũng Nước Bùn Đọng Soi Bóng Trời (2x1)", "积水泥洼映空水塘", [2, 1], "none", "gaze_into_puddle", "puddle_decal", "water", "water"),
        ("scattered_cabbage_leaves_peels", "Scatter of Rotten Cabbage Leaves & Fruit Peels", "Lá Bắp Cải Úa & Vỏ Hoa Quả Vứt Bừa", "烂菜叶瓜果皮碎落片", [1, 1], "none", "kick_aside_debris", "trash_decal", "plant", "earth"),
        ("broken_earthenware_potsherds", "Cluster of Smashed Clay Wine Jar Potsherds", "Mảnh Vò Rượu Gốm Vỡ Nát Trên Đất", "摔碎陶瓦酒坛碎尖堆", [1, 1], "none", "search_broken_potsherds", "shards_decal", "ceramic", None),
        ("spilled_yellow_grain_chaff", "Spilled Yellow Grain Husks and Chaff Stains", "Vết Thóc Vàng & Trấu Rơi Vãi", "倾洒金黄稻谷糠秕片", [1, 1], "none", "sweep_grain_chaff", "grain_stain", "plant", "mortal"),
        ("pile_of_loose_masonry_sand", "Neat Mound of Yellow Construction Sand", "Đụn Cát Vàng Đắp Chờ Xây Tường", "泥水匠筛好细黄砂堆", [1, 1], "none", "examine_sand_pile", "sand_pile", "earth", "earth"),
        ("broken_split_firewood_scatter", "Scatter of Chopped Pine Wood Chips and Bark", "Vụn Gỗ Bổ Củi Rơi Vãi Quanh Gốc", "砍木飞溅残余松树皮片", [1, 1], "none", "gather_woodchips", "woodchips_decal", "wood", "wood"),
        ("horse_manure_hoofprint_patch", "Dry Horse Droppings and Fresh Hoofprints", "Phân Ngựa Khô & Dấu Móng Ngựa Đạp Đất", "马蹄杂乱与干马粪堆", [1, 1], "none", "track_horse_hoofprints", "manure_decal", "earth", None),
        ("discarded_frayed_straw_sandals", "Pair of Worn-Out Discarded Straw Sandals", "Đôi Dép Rơm Rách Rưới Bỏ Đi", "磨破断带废弃草鞋两只", [1, 1], "none", "inspect_straw_sandals", "litter_decal", "straw", "yin"),
    ]
    for c_slug, c_en, c_vn, c_hz, c_mat, c_elem in lt_conds:
        for d_slug, d_en, d_vn, d_hz, fp, col, verb, role, mat_override, elem_override in lt_decals:
            slug = f"dec_{c_slug}_{d_slug}"
            name = f"{c_en} {d_en}"
            vn = f"{d_vn} ({c_vn})"
            hz = f"{c_hz}{d_hz}"
            p = f"Ancient Chinese street floor decal: {name}. Ground-level realistic grunge detail, ink outlines, top-down orthographic game decal on transparent background."
            m = mat_override or c_mat
            e = elem_override or c_elem
            items.append(make_asset(cid, slug, name, vn, hz, "litter_wheel_rut_and_puddle", fp, col, False, "transparent", verb, role, False, m, e, p, "prop", "transparent", "center", {"decal_condition": c_slug}))

    return items


# ==============================================================================
# CATEGORY 19: RURAL FARMING & PASTORAL (200 assets)
# ==============================================================================
def generate_category_19() -> list[dict]:
    items: list[dict] = []
    cid = "rural_farming_and_pastoral"

    # 1. irrigation_flume_and_waterwheel (50 assets)
    ir_systems = [
        ("giant_river_noria", "Colossal Timber River Noria (Tongche)", "Cọn Nước Bờ Sông Khổng Lồ", "巨大江畔筒车", "wood", "water"),
        ("bamboo_elevated_flume", "Elevated Split-Bamboo Aqueduct Flume", "Máng Tre Dẫn Nước Trên Giàn Cao", "竹制架空引水槽", "bamboo", "wood"),
        ("dragon_bone_treadle_pump", "Pedal Dragon-Bone Chain Water Pump", "Guồng Nước Đạp Chân Long Cốt Xa", "脚踏翻水龙骨车", "wood", "mortal"),
        ("stone_sluice_gate_weir", "Masonry Canal Sluice Gate & Weir", "Cống Đá Điều Tiết Nước Kênh", "规整石砌斗门闸", "stone", "earth"),
        ("water_shadoof_counterpoise", "Counterpoised Shadoof Water Lifter", "Cần Vọt Múc Nước Có Quả Đối Trọng", "桔槔杠杆汲水器", "wood", "wind"),
    ]
    ir_parts = [
        ("main_wheel_driving_assembly", "Main Radial Timber Scoop Wheel Assembly (2x2)", "Trục Guồng Bánh Xe Múc Nước (2x2)", "主体带水斗转轮", [2, 2], "solid", "inspect_noria_wheel", "waterwheel_hub", "wood", "water"),
        ("supporting_timber_a_frame_pier", "Heavy Timber A-Frame Bearing Pier", "Chân Đỡ Chữ A Bằng Gỗ Nặng", "人字交叉撑木承重架", [1, 2], "solid", "inspect_support_frame", "support_frame", "wood", None),
        ("straight_flume_trough_single", "Straight Bamboo Water Trough (2x1)", "Máng Tre Dẫn Nước Thẳng (2x1)", "两格平直流水竹槽", [2, 1], "walk_surface", "wash_in_flume_water", "water_flume", "bamboo", "water"),
        ("straight_flume_trough_triple", "Long Bamboo Water Trough Span (3x1)", "Máng Tre Dẫn Nước Dài (3x1)", "三格凌空飞水长木枧", [3, 1], "walk_surface", "wash_in_flume_water", "water_flume", "bamboo", "water"),
        ("corner_flume_elbow_junction", "Right-Angle Flume Water Diverter Elbow", "Co Nối Máng Tre Chuyển Hướng Nước", "直角转弯承接斗", [1, 1], "solid", "inspect_flume_elbow", "flume_elbow", "wood", None),
        ("slotted_timber_sluice_gate", "Vertical Slotted Wood Canal Sluice Gate", "Cánh Phai Gỗ Đóng Mở Cửa Cống", "插板式升降木闸板", [2, 1], "solid", "operate_sluice_gate", "sluice_gate", "wood", "earth"),
        ("splashing_water_outflow_trough", "Discharge Spout Splashing into Paddy", "Mương Trút Nước Vào Ruộng Lúa", "倾注奔流出水嘴石槽", [1, 1], "none", "wash_in_outflow", "spillway", "water", "water"),
        ("treadle_foot_cranking_pedals", "Dual Wooden Foot Treadle Cranks", "Bàn Đạp Hai Chân Quay Trục Nước", "双脚轮踏踏木曲柄", [1, 1], "ground_contact", "crank_dragonbone_pump", "treadle_pedal", "wood", "mortal"),
        ("clattering_bamboo_deer_scare", "Water-Tipping Clattering Bamboo Device (Luode)", "Ống Tre Bập Bênh Gõ Nước Đuổi Thú", "水满自跌击石鹿得器", [1, 1], "ground_contact", "listen_deer_scare", "water_chime", "bamboo", "wind"),
        ("muddy_drainage_dike_cutoff", "Compacted Earth Irrigation Dike Border", "Bờ Đê Đất Nện Dẫn Nước Thửa Ruộng", "夯泥固土灌溉埂条", [2, 1], "walk_surface", "walk_dike_border", "dike_border", "earth", "earth"),
    ]
    for s_slug, s_en, s_vn, s_hz, s_mat, s_elem in ir_systems:
        for p_slug, p_en, p_vn, p_hz, fp, col, verb, role, mat_override, elem_override in ir_parts:
            slug = f"irg_{s_slug}_{p_slug}"
            name = f"{s_en} {p_en}"
            vn = f"{p_vn} ({s_vn})"
            hz = f"{s_hz}{p_hz}"
            p = f"Ancient Chinese agricultural irrigation system part: {name}. Functional wooden hydraulics, ink contours, top-down orthographic game asset on transparent background."
            m = mat_override or s_mat
            e = elem_override or s_elem
            items.append(make_asset(cid, slug, name, vn, hz, "irrigation_flume_and_waterwheel", fp, col, False if col in ("walk_surface", "none") else True, "transparent", verb, role, False, m, e, p, "structure", "transparent", "bottom_center", {"irrigation_tech": s_slug}))

    # 2. homestead_pen_and_coop (50 assets)
    hs_animals = [
        ("muddy_swine_pigpen", "Wattle & Mud Peasant Pigsty", "Chuồng Heo Bằng Bùn & Tre", "泥抹围栏肥猪圈", "earth", "earth"),
        ("woven_willow_chicken_coop", "Woven Wicker Poultry & Hen Coop", "Chuồng Gà Đan Bằng Liễu & Tre", "编柳鸡鸭双栖舍", "bamboo", "wood"),
        ("water_buffalo_thatched_shed", "Thatched Water Buffalo Stable", "Lán Tranh Cho Trâu Nước Nghỉ", "厚草顶卧牛敞棚", "straw", "water"),
        ("mountain_goat_brush_corral", "Thorny Brush Mountain Goat Corral", "Bãi Quây Dê Rừng Bằng Cành Gai", "干荆棘圈羊栅栏", "wood", "metal"),
        ("draft_horse_timber_stable", "Working Draft Horse Post & Manger", "Chuồng Ngựa Thồ Bằng Gỗ", "挽马歇草架木厩", "wood", "fire"),
    ]
    hs_structs = [
        ("enclosed_animal_pen_2x2", "Enclosed Post-and-Rail Animal Pen (2x2)", "Bãi Quây Rào Gỗ Nhốt Gia Súc (2x2)", "四方合围栅条牲畜圈", [2, 2], "solid", "inspect_livestock_pen", "livestock_pen", None, None),
        ("large_communal_paddock_3x2", "Broad Communal Livestock Corral (3x2)", "Khu Rào Gia Súc Rộng Lớn (3x2)", "大间通开群牧栏栅", [3, 2], "solid", "inspect_communal_corral", "livestock_corral", None, None),
        ("thatched_shelter_sleeping_hut", "Thatched Lean-To Sleeping Shelter for Beasts", "Mái Tranh Che Mưa Cho Gia Súc", "靠壁单坡歇卧草篷", [2, 1], "solid", "rest_in_animal_shelter", "animal_hut", "straw", None),
        ("hollow_log_feeding_trough", "Long Hollow-Log Grain & Mash Manger", "Máng Ăn Bằng Thân Cây Đục Rỗng", "整木挖凿长条饲料槽", [2, 1], "solid", "fill_feeding_trough", "feeding_trough", "wood", None),
        ("carved_stone_watering_basin", "Carved Stone Water Trough for Cattle", "Bể Đá Đựng Nước Cho Trâu Bò Uống", "方形厚实石凿饮水池", [1, 1], "solid", "fill_water_basin", "water_trough", "stone", "water"),
        ("hanging_woven_wicker_feed_rack", "Suspended Wicker Hay Rack for Horses", "Giá Tre Đựng Cỏ Khô Treo Cao", "悬挂篾编储草料篓", [1, 1], "ground_contact", "fill_hay_rack", "hay_rack", "bamboo", None),
        ("slanting_wooden_poultry_ladder", "Slanted Cleated Wooden Chicken Ladder", "Thang Gỗ Có Khấc Cho Gà Lên Chuồng", "细木钉条登高鸡跳梯", [1, 1], "ground_contact", "inspect_poultry_ladder", "hen_ladder", "wood", None),
        ("straw_nesting_box_with_eggs", "Straw Woven Nesting Box with Clutch of Eggs", "Ổ Rơm Ấp Trứng Của Gà Mái", "垫草抱窝蛋卵圆筐", [1, 1], "ground_contact", "gather_fresh_eggs", "nest_box", "straw", "yin"),
        ("animal_gate_swing_latch", "Rough Picket Animal Gate with Rope Latch", "Cánh Cửa Rào Có Dây Buộc Chắc", "简易搭扣单扇木圈门", [1, 1], "solid", "unlatch_pen_gate", "pen_gate", "wood", None),
        ("muddy_wallow_trough_basin", "Muddy Wallow Depression inside Pigsty", "Vũng Bùn Lầy Cho Heo Đầm Mình", "湿洼泛泡滚泥下洼处", [2, 1], "none", "inspect_mud_wallow", "mud_wallow", "earth", "earth"),
    ]
    for a_slug, a_en, a_vn, a_hz, a_mat, a_elem in hs_animals:
        for s_slug, s_en, s_vn, s_hz, fp, col, verb, role, mat_override, elem_override in hs_structs:
            slug = f"pen_{a_slug}_{s_slug}"
            name = f"{a_en} {s_en}"
            vn = f"{s_vn} ({a_vn})"
            hz = f"{a_hz}{s_hz}"
            p = f"Ancient Chinese farm homestead animal husbandry prop: {name}. Rustic peasant craftsmanship, gouache textures with ink outlines, top-down orthographic game sprite, transparent background."
            m = mat_override or a_mat
            e = elem_override or a_elem
            items.append(make_asset(cid, slug, name, vn, hz, "homestead_pen_and_coop", fp, col, False if col == "none" else True, "transparent", verb, role, True, m, e, p, "structure", "transparent", "bottom_center", {"animal_housing": a_slug}))

    # 3. crop_trellis_and_hanging_harvest (50 assets)
    cr_crops = [
        ("bottle_gourd_calabash", "Green Bottle Gourd & Calabash", "Dàn Bầu Hồ Lô Thả Trái", "如意大葫芦藤", "plant", "wood"),
        ("long_string_beans", "Climbing Long Pole Green Beans", "Giàn Đậu Cô Ve Dài Leo Cọc", "青长豆角藤架", "plant", "earth"),
        ("crimson_sun_chili", "Fiery Red Sun-Drying Peppers", "Ớt Đỏ Cay Nồng Phơi Nắng", "朝天红辣串串", "plant", "yang"),
        ("braided_garlic_onions", "Braided White Garlic & Shallot Strings", "Tỏi Trắng Thắt Bím Dưới Mái", "编结整齐白大蒜辫", "plant", "metal"),
        ("golden_maize_corn_cobs", "Golden Sun-Cured Corn on the Cob", "Bắp Ngô Vàng Óng Buộc Chùm", "金黄饱满玉米棒挂", "plant", "earth"),
    ]
    cr_styles = [
        ("arched_bamboo_garden_trellis_2x2", "Arched Bamboo Garden Trellis (2x2)", "Giàn Tre Uốn Vòm Cho Cây Leo (2x2)", "拱形毛竹透光大棚架", [2, 2], "ground_contact", "inspect_garden_trellis", "garden_trellis", "bamboo", None),
        ("straight_pole_climber_row_2x1", "A-Frame Wooden Pole Climbing Row (2x1)", "Giàn Cọc Gỗ Chữ A Trồng Cây (2x1)", "人字绑竿攀附长架", [2, 1], "ground_contact", "inspect_pole_trellis", "pole_trellis", "wood", None),
        ("leaning_wall_bamboo_lattice", "Bamboo Trellis Leaning Against Mud Wall", "Giàn Tre Tựa Vào Vách Tường Đất", "依贴土墙斜放竹格架", [2, 1], "solid", "inspect_wall_trellis", "wall_trellis", "bamboo", None),
        ("hung_under_roof_eaves_string", "Heavy Strung Clusters Hung Under Thatch Eaves", "Chùm Nông Sản Buộc Dưới Mái Hiên", "茅檐垂吊风干排串", [2, 1], "solid", "harvest_hanging_crop", "eave_harvest", "plant", None),
        ("sun_drying_round_bamboo_mat", "Round Bamboo Winnowing Mat Full of Harvest", "Mẹt Tre Tròn Phơi Nông Sản Nắng To", "平展大圆竹匾晒粮晒物", [1, 1], "none", "turn_drying_grain", "drying_tray", "bamboo", "yang"),
        ("wooden_scaffold_drying_rack", "Three-Tier Wooden Scaffold Outdoor Drying Rack", "Giàn Gỗ Phơi Nông Sản Ngoài Trời", "露天搭起三层晾晒架", [2, 1], "ground_contact", "inspect_drying_scaffold", "drying_scaffold", "wood", None),
        ("braided_harvest_hung_column", "Harvest Braids Tied Along Veranda Pillars", "Chùm Nông Sản Thắt Bím Buộc Cột Hiên", "檐柱垂挂丰收编织串", [1, 2], "ground_contact", "inspect_hanging_braid", "pillar_braid", "plant", None),
        ("woven_wicker_drying_basket", "Shallow Woven Wicker Basket of Sliced Produce", "Rổ Rảo Tre Đan Phơi Thái Lát Nông Sản", "浅口篾盘晒切片干货", [1, 1], "ground_contact", "gather_dried_crop", "drying_basket", "bamboo", None),
        ("threshing_flail_leaning_wall", "Wooden Threshing Flail Leaning on Mud Wall", "Đòn Đập Lúa Bằng Gỗ Dựa Vào Vách", "靠墙放置打谷连枷农具", [1, 1], "ground_contact", "pick_up_threshing_flail", "harvest_tool", "wood", "mortal"),
        ("solar_grain_drying_tarpaulin", "Coarse Hemp Sheet Spread with Golden Harvest", "Tấm Bạt Vải Thô Trải Phơi Thóc Vàng (2x2)", "铺地粗麻布摊晒稻谷片", [2, 2], "none", "rake_solar_drying_grain", "drying_sheet", "cloth", "yang"),
    ]
    for c_slug, c_en, c_vn, c_hz, c_mat, c_elem in cr_crops:
        for s_slug, s_en, s_vn, s_hz, fp, col, verb, role, mat_override, elem_override in cr_styles:
            slug = f"trp_{c_slug}_{s_slug}"
            name = f"{c_en} {s_en}"
            vn = f"{s_vn} ({c_vn})"
            hz = f"{c_hz}{s_hz}"
            p = f"Ancient Chinese farm crop harvest display: {name}. Golden rustic farm aesthetic, ink contours, top-down orthographic game asset on transparent background."
            m = mat_override or c_mat
            e = elem_override or c_elem
            items.append(make_asset(cid, slug, name, vn, hz, "crop_trellis_and_hanging_harvest", fp, col, False if col == "none" else True, "transparent", verb, role, False, m, e, p, "prop", "transparent", "bottom_center", {"crop_type": c_slug}))

    # 4. grain_granary_and_haystack (50 assets)
    gr_farms = [
        ("round_clay_granary", "Peasant Round Mud Silo Granary", "Bồ Thóc Tròn Đất Nện Nông Thôn", "农家圆顶泥抹谷仓", "earth", "earth"),
        ("stilt_timber_granary", "Raised Stilt Timber Aerated Granary", "Kho Thóc Nhà Sàn Gỗ Thooáng Khí", "防潮干栏高脚木仓", "wood", "wood"),
        ("earthen_walled_barn", "Communal Earthen Village Barn", "Nhà Kho Thôn Trang Tường Đất Rơm", "庄稼大聚落土打公仓", "earth", "mortal"),
        ("conical_straw_haystack", "Straw Thatched Peasant Hay Cone", "Đụn Rơm Conic Đồng Quê Mộc Mạc", "田埂金黄尖锥草垛", "straw", "yin"),
        ("masonry_grain_cellar", "Stone-Lined Subterranean Grain Cellar", "Hầm Thóc Đá Lót Dưới Lòng Đất", "防虫石衬地窖暗粮仓", "stone", "metal"),
    ]
    gr_props = [
        ("round_thatched_conical_haystack", "Round Thatched Conical Field Haystack (2x2)", "Đụn Rơm Tròn Đội Mũ Tranh Đồ Sộ (2x2)", "大号厚密圆锥稻草堆", [2, 2], "solid", "hide_in_haystack", "haystack", "straw", None),
        ("small_haystack_sheaf_cluster", "Trio Cluster of Bound Straw Sheaves (1x1)", "Cụm Ba Bó Rơm Buộc Chụm (1x1)", "三捆聚拢金黄小麦垛", [1, 1], "ground_contact", "gather_straw_sheaves", "hay_cluster", "straw", None),
        ("raised_stilt_granary_building", "Stilt Raised Timber Granary Building (3x2)", "Kho Thóc Gỗ Trên Cột Sàn Chống Chuột (3x2)", "两开间飞檐高脚木粮库", [3, 2], "solid", "inspect_granary_stores", "granary_building", "wood", None),
        ("carved_stone_grain_roller_mill", "Carved Stone Roller on Circular Basin (2x1)", "Con Lăn Đá Kéo Cối Xay Thóc (2x1)", "碾米推谷重磨大石磙", [2, 1], "solid", "turn_grain_roller", "grain_roller", "stone", "metal"),
        ("circular_stone_threshing_floor", "Paved Circular Granite Threshing Floor (3x3)", "Sân Đập Lúa Lát Đá Tròn (3x3)", "平整青石圆盘大晒谷场", [3, 3], "walk_surface", "thresh_grain_on_floor", "threshing_floor", "stone", "yang"),
        ("winnowing_wooden_grain_shovel", "Wooden Winnowing Fork & Chaff Shovel", "Xẻng Gỗ Sàng Trấu & Chĩa Rơm", "迎风扬场木掀与挑草叉", [1, 1], "ground_contact", "winnow_grain_chaff", "winnowing_tool", "wood", "wind"),
        ("earthenware_fermentation_soy_vats", "Pair of Giant Glazed Soy Fermentation Vats", "Cặp Chum Sành Ủ Tương Đen Khổng Lồ", "双只酱菜封泥粗陶大坛", [2, 1], "solid", "inspect_soy_vats", "soy_vats", "ceramic", None),
        ("stone_mortar_wooden_foot_pounder", "Stone Grain Mortar with Wooden Treadle Pounder", "Cối Giã Gạo Bằng Chân Bập Bênh", "脚踏碓臼凿石春米器", [1, 1], "ground_contact", "pound_rice_mortar", "rice_mortar", "stone", "mortal"),
        ("rat_proof_tin_plinths_granary_leg", "Timber Support Post with Anti-Rodent Metal Disc", "Chân Cột Chống Chuột Bọc Miếng Thiếc", "立柱镶铁皮防鼠挡板腿", [1, 1], "solid", "inspect_rat_proof_plinth", "granary_post", "iron", "metal"),
        ("bundle_of_tied_wheat_sheaves", "Neatly Stacked Pile of Bound Wheat Sheaves", "Đống Bó Lúa Vàng Xếp Ngay Ngắn", "整齐码放金黄麦穗捆堆", [1, 1], "ground_contact", "lift_wheat_sheaf", "grain_sheaves", "straw", "earth"),
    ]
    for f_slug, f_en, f_vn, f_hz, f_mat, f_elem in gr_farms:
        for p_slug, p_en, p_vn, p_hz, fp, col, verb, role, mat_override, elem_override in gr_props:
            slug = f"gra_{f_slug}_{p_slug}"
            name = f"{f_en} {p_en}"
            vn = f"{p_vn} ({f_vn})"
            hz = f"{f_hz}{p_hz}"
            p = f"Ancient Chinese farm grain storage asset: {name}. Peasant pastoral atmosphere, ink outlines, top-down orthographic game sprite, transparent background."
            m = mat_override or f_mat
            e = elem_override or f_elem
            items.append(make_asset(cid, slug, name, vn, hz, "grain_granary_and_haystack", fp, col, False if col in ("walk_surface", "none") else True, "transparent", verb, role, False, m, e, p, "structure", "transparent", "bottom_center", {"farm_archetype": f_slug}))

    return items


def append_expansion_to_pack():
    with open(PACK_PATH, "r", encoding="utf-8") as f:
        pack = json.load(f)

    # First 780 assets are the completed existing categories 1-14
    base_assets = pack["assets"][:780]
    print(f"Loaded existing pack. Preserved base assets: {len(base_assets)}")

    t0 = time.time()
    c15 = generate_category_15()
    print(f"Generated Category 15 (modular_architecture_timber): {len(c15)} assets")

    c16 = generate_category_16()
    print(f"Generated Category 16 (mountain_cliff_geology):       {len(c16)} assets")

    c17 = generate_category_17()
    print(f"Generated Category 17 (flora_and_forest_ecology):      {len(c17)} assets")

    c18 = generate_category_18()
    print(f"Generated Category 18 (urban_street_and_market):       {len(c18)} assets")

    c19 = generate_category_19()
    print(f"Generated Category 19 (rural_farming_and_pastoral):    {len(c19)} assets")

    all_expansion = c15 + c16 + c17 + c18 + c19
    print(f"\nTotal new expansion assets: {len(all_expansion)}")

    # Combine base assets with the enriched expansion
    all_assets = list(base_assets) + all_expansion
    pack["assets"] = all_assets
    pack["total_assets"] = len(all_assets)

    # Synchronize top-level categories array in pack
    with open(CATEGORIES_PATH, "r", encoding="utf-8") as f:
        categories_def = json.load(f)
    pack["categories"] = categories_def

    temp_pack = PACK_PATH.with_suffix(".tmp")
    with open(temp_pack, "w", encoding="utf-8") as f:
        json.dump(pack, f, indent=2, ensure_ascii=False)

    for _ in range(10):
        try:
            temp_pack.replace(PACK_PATH)
            break
        except PermissionError:
            time.sleep(0.5)

    print(f"\nSuccessfully updated {PACK_PATH}")
    print(f"Total assets in pack manifest now: {pack['total_assets']} (Elapsed: {time.time()-t0:.2f}s)")


if __name__ == "__main__":
    append_expansion_to_pack()
