"""Per-archetype semantics: the authored (LLM-classified) layer.

One row per archetype, 65 total, matching tools/map_assets.ASSET_ROLES.
This is the ONCE-authored answer to "what does this art mean in a map", as
opposed to build/mapdata/measure.py which is per-file pixel truth.

Rules, and why each exists (all derived from measured per-cell coverage):
  ground_contact  only the bottom row blocks; the art above is overhang.
                  canopy_tree coverage is 0.44 top / 0.12 bottom -- the trunk
                  is at the bottom, so a full-body mask over-blocks 2x.
                  NOTE its gate is 0.05, not 0.20: _install centers the art in
                  the canvas, so a ~30px trunk straddles the 128px cell boundary
                  and lands ~0.12 in BOTH bottom cells. A 0.20 gate deleted both
                  halves of every tree and made the whole forest walkable.
                  Whether a trunk "should" be 1 cell cannot be decided at 128px;
                  it straddles, so it is 2. See the sub-cell note in the plan.
  full_body       every cell with coverage >= cov_gate blocks.
  core_ring      cells >= cov_gate block; thinner art (an arch opening,
                  ruined walls) stays passable, which is how an arch gets a
                  doorway without authoring one.
  none           never blocks. Ground, decals, effects, shallow water.

cov_gate is the minimum coverage for a cell to count as body. 0.20 separates a
mass from an open cell for full_body props; 0.02 is required for ground_contact,
where the art is a pole a few pixels wide. A failed background-removal pass is
NOT caught by cov_gate -- real trunks and failed cutouts overlap at the bottom
row (measured canopy p50=0.198 vs failures 0.001-0.083). It is caught by the
max-coverage test in derive.py, which looks at the whole frame.
"""

from __future__ import annotations

from typing import Any

# occluder_rule values
GROUND_CONTACT = "ground_contact"
FULL_BODY = "full_body"
CORE_RING = "core_ring"
NONE = "none"

_M = {  # material -> (tier, hp, on_destroy archetype or None)
    "earth": (1, 40, "ground_tile.cracked_ground"),
    "foliage": (1, 25, "landmark_and_environment_detail.ground_decal"),
    "wood": (2, 60, "stone_and_ore.rubble"),
    "stone": (3, 140, "stone_and_ore.rubble"),
    "metal": (3, 160, "stone_and_ore.rubble"),
    "crystal": (4, 220, "stone_and_ore.rubble"),
    "water": (0, 0, None),
    "spirit": (0, 0, None),
    # Fabric: no tier, so destructible.enabled is False and it never claims a
    # rubble reveal. Banner keeps its own row rather than borrowing earth.
    "cloth": (0, 0, None),
}


def _row(
    archetype: str,
    *,
    rule: str,
    cov_gate: float = 0.20,
    small_gate: float | None = None,
    passable_under: bool = False,
    walk_surface: bool = False,
    blocks_sight: bool = False,
    blocks_projectile: bool | None = None,
    vision_mode: str | None = None,
    acoustic_profile: str | None = None,
    material: str = "earth",
    elevation: int = 0,
    verb: str = "",
    reach: int = 0,
    adjacent: bool = True,
    authored_open: str = "",
    cultivation: dict[str, Any] | None = None,
    resource: dict[str, Any] | None = None,
    scale_profile: dict[str, Any] | None = None,
    unique_destroyed: str | None = None,
    elemental_vulnerabilities: list[str] | None = None,
    reveals_loot: str | None = None,
) -> dict[str, Any]:
    tier, hp, reveals = _M[material]
    destructible = tier > 0
    if blocks_projectile is None:
        blocks_projectile = (
            rule in (FULL_BODY, GROUND_CONTACT) and not walk_surface and material != "water"
        )
    if vision_mode is None:
        if passable_under:
            vision_mode = "canopy"
        elif blocks_sight:
            vision_mode = "solid"
        elif rule == GROUND_CONTACT and not passable_under:
            vision_mode = "brush"
        else:
            vision_mode = "transparent"
    if acoustic_profile is None:
        acoustic_profile = material

    vulns = elemental_vulnerabilities
    if vulns is None and destructible:
        if material in ("wood", "foliage"):
            vulns = ["fire", "slash"]
        elif material in ("stone", "crystal"):
            vulns = ["crush", "earth"]
        elif material == "metal":
            vulns = ["corrosion", "fire"]
        elif material == "earth":
            vulns = ["water", "wind"]
        else:
            vulns = []

    return {
        "archetype": archetype,
        "occluder_rule": rule,
        "cov_gate": cov_gate,
        "small_cov_gate": small_gate if small_gate is not None else min(cov_gate, 0.10),
        "passable_under": passable_under,
        "walk_surface": walk_surface,
        "blocks_sight": blocks_sight,
        "blocks_projectile": blocks_projectile,
        "vision_mode": vision_mode,
        "acoustic_profile": acoustic_profile,
        "material": material,
        "elevation": elevation,
        "authored_open": authored_open,
        "destructible": {
            "enabled": destructible,
            "tier": tier,
            "hp": hp if destructible else 0,
            "on_destroy": reveals if destructible else None,
            "unique_destroyed_archetype": unique_destroyed,
            "elemental_vulnerabilities": vulns or [],
            "reveals_loot_category": reveals_loot,
        },
        "interact": {"verb": verb, "reach_cells": reach, "from_adjacent": adjacent}
        if verb
        else None,
        "cultivation": cultivation
        or {
            "element": "none",
            "qi_affinity": "neutral",
            "qi_density_modifier": 1.0,
            "resonance_radius_cells": 0,
            "feng_shui_direction": "neutral",
        },
        "resource": resource,
        "scale_profile": scale_profile
        or {
            "min_scale": 1.0,
            "max_scale": 1.0,
            "default_scale": 1.0,
            "scale_mode": "constant",
            "contact_rule": "constant_subcell",
        },
    }


TREE = dict(
    rule=GROUND_CONTACT,
    cov_gate=0.01,
    passable_under=True,
    blocks_sight=True,
    blocks_projectile=True,
    vision_mode="canopy",
    material="foliage",
    cultivation={
        "element": "wood",
        "qi_affinity": "ambient_absorb",
        "qi_density_modifier": 1.15,
        "resonance_radius_cells": 1,
        "feng_shui_direction": "yang",
    },
    resource={
        "resource_type": "timber",
        "base_yield": 3,
        "respawn_turns": 300,
        "min_realm_tier": 1,
        "harvest_tool_tag": "axe",
    },
    scale_profile={
        "min_scale": 0.85,
        "max_scale": 1.6,
        "default_scale": 1.0,
        "supported_scales": [0.85, 1.0, 1.15, 1.35, 1.6],
        "scale_mode": "stepped",
        "contact_rule": "constant_subcell",
    },
    reveals_loot="timber",
)

RING = dict(rule=CORE_RING, cov_gate=0.10)

SEMANTICS: dict[str, dict[str, Any]] = {
    # ---- ground: never occludes, this is terrain not prop ------------------
    "ground_tile.base_ground": _row("ground_tile.base_ground", rule=NONE, material="earth"),
    "ground_tile.soft_ground": _row("ground_tile.soft_ground", rule=NONE, material="earth"),
    "ground_tile.packed_trail": _row("ground_tile.packed_trail", rule=NONE, material="earth"),
    "ground_tile.stone_paving": _row("ground_tile.stone_paving", rule=NONE, material="stone"),
    "ground_tile.leaf_or_silt_litter": _row(
        "ground_tile.leaf_or_silt_litter", rule=NONE, material="earth"
    ),
    "ground_tile.cracked_ground": _row("ground_tile.cracked_ground", rule=NONE, material="earth"),
    "ground_tile.sacred_ground": _row("ground_tile.sacred_ground", rule=NONE, material="stone"),
    "ground_tile.resource_bare_ground": _row(
        "ground_tile.resource_bare_ground", rule=NONE, material="earth"
    ),
    "terrain_texture.base_surface": _row(
        "terrain_texture.base_surface", rule=NONE, material="earth"
    ),
    # ---- terrain transitions ---------------------------------------------
    "terrain_transition.ground_edge": _row("terrain_transition.ground_edge", rule=NONE),
    "terrain_transition.trail_edge": _row("terrain_transition.trail_edge", rule=NONE),
    "terrain_transition.shore_edge": _row("terrain_transition.shore_edge", rule=NONE),
    "terrain_transition.cliff_edge": _row(
        "terrain_transition.cliff_edge",
        rule=FULL_BODY,
        material="stone",
        blocks_sight=True,
        elevation=1,
    ),
    "terrain_transition.slope_ramp": _row(
        "terrain_transition.slope_ramp", rule=NONE, walk_surface=True, material="stone", elevation=1
    ),
    "terrain_transition.terrain_corner": _row("terrain_transition.terrain_corner", rule=NONE),
    "terrain_transition.terrain_inner_corner": _row(
        "terrain_transition.terrain_inner_corner", rule=NONE
    ),
    "terrain_transition.terrain_island": _row("terrain_transition.terrain_island", rule=NONE),
    # ---- flora: ground_contact, walk under the canopy ----------------------
    "flora.canopy_tree": _row("flora.canopy_tree", **TREE),
    "flora.slender_tree": _row("flora.slender_tree", **TREE),
    "flora.ancient_tree": _row("flora.ancient_tree", **TREE),
    "flora.shrub": _row(
        "flora.shrub", rule=GROUND_CONTACT, cov_gate=0.01, material="foliage", passable_under=False
    ),
    "flora.flower_cluster": _row("flora.flower_cluster", rule=NONE, material="foliage"),
    "flora.cultivation_herb": _row(
        "flora.cultivation_herb", rule=NONE, material="foliage", verb="harvest", reach=1
    ),
    "flora.fallen_log": _row(
        "flora.fallen_log",
        rule=GROUND_CONTACT,
        cov_gate=0.01,
        material="wood",
        walk_surface=True,
        elevation=1,
    ),
    "flora.root_cluster": _row(
        "flora.root_cluster", rule=GROUND_CONTACT, cov_gate=0.01, material="foliage"
    ),
    # ---- stone and ore ----------------------------------------------------
    "stone_and_ore.small_rock": _row("stone_and_ore.small_rock", rule=FULL_BODY, material="stone"),
    "stone_and_ore.boulder": _row("stone_and_ore.boulder", rule=FULL_BODY, material="stone"),
    "stone_and_ore.stone_cluster": _row(
        "stone_and_ore.stone_cluster", rule=FULL_BODY, material="stone"
    ),
    "stone_and_ore.ore_vein": _row(
        "stone_and_ore.ore_vein", rule=FULL_BODY, material="crystal", verb="mine", reach=1
    ),
    "stone_and_ore.crystal_growth": _row(
        "stone_and_ore.crystal_growth", rule=FULL_BODY, material="crystal", verb="harvest", reach=1
    ),
    "stone_and_ore.standing_stone": _row(
        "stone_and_ore.standing_stone",
        rule=GROUND_CONTACT,
        cov_gate=0.01,
        material="stone",
        blocks_sight=True,
        elevation=1,
    ),
    "stone_and_ore.rubble": _row("stone_and_ore.rubble", rule=NONE, material="stone"),
    "stone_and_ore.mineral_spring": _row(
        "stone_and_ore.mineral_spring", rule=FULL_BODY, material="stone", verb="draw_water", reach=1
    ),
    # ---- travel and wayfinding -------------------------------------------
    "travel_and_wayfinding.trail_marker": _row(
        "travel_and_wayfinding.trail_marker",
        rule=GROUND_CONTACT,
        cov_gate=0.01,
        material="wood",
        verb="read",
        reach=1,
    ),
    "travel_and_wayfinding.signpost": _row(
        "travel_and_wayfinding.signpost",
        rule=GROUND_CONTACT,
        cov_gate=0.01,
        material="wood",
        verb="read",
        reach=1,
    ),
    "travel_and_wayfinding.stone_waypoint": _row(
        "travel_and_wayfinding.stone_waypoint",
        rule=GROUND_CONTACT,
        cov_gate=0.01,
        material="stone",
        verb="activate",
        reach=1,
    ),
    # A bridge is the one archetype that is BOTH walkable and an occluder:
    # you stand on top of it, and the water under it stays blocked.
    "travel_and_wayfinding.wooden_bridge": _row(
        "travel_and_wayfinding.wooden_bridge",
        rule=FULL_BODY,
        cov_gate=0.15,
        material="wood",
        walk_surface=True,
        elevation=1,
    ),
    "travel_and_wayfinding.stone_bridge": _row(
        "travel_and_wayfinding.stone_bridge",
        rule=FULL_BODY,
        cov_gate=0.15,
        material="stone",
        walk_surface=True,
        elevation=1,
    ),
    "travel_and_wayfinding.path_gate": _row(
        "travel_and_wayfinding.path_gate",
        **RING,
        material="wood",
        passable_under=True,
        verb="unlock",
        reach=1,
        authored_open="bottom_centre",
    ),
    "travel_and_wayfinding.portal_frame": _row(
        "travel_and_wayfinding.portal_frame",
        **RING,
        material="stone",
        blocks_sight=True,
        elevation=1,
        verb="enter",
        reach=1,
        authored_open="bottom_centre",
    ),
    "travel_and_wayfinding.travel_shrine": _row(
        "travel_and_wayfinding.travel_shrine",
        rule=FULL_BODY,
        material="stone",
        verb="pray",
        reach=1,
    ),
    # ---- settlement -------------------------------------------------------
    "settlement_and_domain_prop.shelter": _row(
        "settlement_and_domain_prop.shelter", rule=FULL_BODY, material="wood", elevation=1
    ),
    "settlement_and_domain_prop.storehouse": _row(
        "settlement_and_domain_prop.storehouse",
        rule=FULL_BODY,
        material="wood",
        blocks_sight=True,
        elevation=1,
        verb="enter",
        reach=1,
    ),
    "settlement_and_domain_prop.workbench": _row(
        "settlement_and_domain_prop.workbench",
        rule=FULL_BODY,
        material="wood",
        verb="craft",
        reach=1,
    ),
    "settlement_and_domain_prop.supply_crate": _row(
        "settlement_and_domain_prop.supply_crate",
        rule=FULL_BODY,
        material="wood",
        verb="loot",
        reach=1,
    ),
    "settlement_and_domain_prop.sealed_cache": _row(
        "settlement_and_domain_prop.sealed_cache",
        rule=FULL_BODY,
        material="stone",
        verb="open",
        reach=1,
    ),
    "settlement_and_domain_prop.cultivation_altar": _row(
        "settlement_and_domain_prop.cultivation_altar",
        rule=FULL_BODY,
        material="stone",
        blocks_sight=True,
        elevation=1,
        verb="meditate",
        reach=1,
    ),
    "settlement_and_domain_prop.domain_seal": _row(
        "settlement_and_domain_prop.domain_seal",
        rule=FULL_BODY,
        material="spirit",
        blocks_sight=True,
        elevation=1,
        verb="unseal",
        reach=1,
    ),
    "settlement_and_domain_prop.resting_stone": _row(
        "settlement_and_domain_prop.resting_stone",
        rule=FULL_BODY,
        material="stone",
        verb="rest",
        reach=1,
    ),
    # ---- landmarks and detail --------------------------------------------
    "landmark_and_environment_detail.cliff_formation": _row(
        "landmark_and_environment_detail.cliff_formation",
        rule=FULL_BODY,
        material="stone",
        blocks_sight=True,
        elevation=2,
    ),
    "landmark_and_environment_detail.cave_entrance": _row(
        "landmark_and_environment_detail.cave_entrance",
        **RING,
        material="stone",
        blocks_sight=True,
        verb="enter",
        reach=1,
        authored_open="bottom_centre",
    ),
    "landmark_and_environment_detail.domain_entrance": _row(
        "landmark_and_environment_detail.domain_entrance",
        **RING,
        material="stone",
        blocks_sight=True,
        verb="enter",
        reach=1,
        authored_open="bottom_centre",
    ),
    # An arch's opening is the whole point, so core_ring rather than full_body.
    "landmark_and_environment_detail.ruined_arch": _row(
        "landmark_and_environment_detail.ruined_arch",
        **RING,
        material="stone",
        passable_under=True,
        authored_open="bottom_centre",
    ),
    "landmark_and_environment_detail.statue": _row(
        "landmark_and_environment_detail.statue",
        rule=FULL_BODY,
        material="stone",
        blocks_sight=True,
        elevation=1,
        verb="examine",
        reach=2,
    ),
    "landmark_and_environment_detail.banner": _row(
        "landmark_and_environment_detail.banner",
        rule=GROUND_CONTACT,
        cov_gate=0.01,
        material="cloth",
        passable_under=False,
    ),
    "landmark_and_environment_detail.ground_decal": _row(
        "landmark_and_environment_detail.ground_decal", rule=NONE
    ),
    "landmark_and_environment_detail.ambient_effect": _row(
        "landmark_and_environment_detail.ambient_effect", rule=NONE, material="spirit"
    ),
    # ---- water ------------------------------------------------------------
    "water_feature.shallow_water": _row("water_feature.shallow_water", rule=NONE, material="water"),
    "water_feature.deep_water": _row(
        "water_feature.deep_water", rule=FULL_BODY, material="water", elevation=0
    ),
    "water_feature.pool": _row("water_feature.pool", rule=FULL_BODY, material="water"),
    "water_feature.stream": _row("water_feature.stream", rule=NONE, material="water"),
    "water_feature.waterfall": _row(
        "water_feature.waterfall", rule=NONE, material="water", passable_under=True
    ),
    "water_feature.spring": _row(
        "water_feature.spring", rule=NONE, material="water", verb="draw_water", reach=1
    ),
    "water_feature.water_foam": _row("water_feature.water_foam", rule=NONE, material="water"),
    "water_feature.water_plant": _row(
        "water_feature.water_plant", rule=NONE, material="foliage", passable_under=True
    ),
}

assert len(SEMANTICS) == 65, f"expected 65 archetypes, got {len(SEMANTICS)}"


# --- authored footprint: the cell size of the KIND ----------------------
# Emitted by author_footprint.py. Do not hand-edit; edit OVERRIDES there.
#
# This replaces `canvas_px / 128`, which made collision a property of the
# PNG's resolution. See author_footprint.py for the three measurements
# that forced the change.
FOOTPRINT: dict[str, tuple[int, int]] = {
    "flora.ancient_tree": (3, 3),  # the chunk's landmark; 4x4 overstates a 480px sprite
    "flora.canopy_tree": (2, 2),  # a full tree; its art is 178px into a 2x2 box
    "flora.cultivation_herb": (1, 1),  # a herb is a handful
    "flora.fallen_log": (2, 2),  # a log is long
    "flora.flower_cluster": (1, 1),  # a flower patch
    "flora.root_cluster": (1, 1),  # low ground cover
    "flora.shrub": (1, 1),  # low ground cover
    "flora.slender_tree": (2, 2),  # full height like any other tree
    "ground_tile.base_ground": (1, 1),
    "ground_tile.cracked_ground": (1, 1),
    "ground_tile.leaf_or_silt_litter": (1, 1),
    "ground_tile.packed_trail": (1, 1),
    "ground_tile.resource_bare_ground": (1, 1),
    "ground_tile.sacred_ground": (1, 1),
    "ground_tile.soft_ground": (1, 1),
    "ground_tile.stone_paving": (1, 1),
    "landmark_and_environment_detail.banner": (1, 2),  # a banner is tall and thin
    "landmark_and_environment_detail.cave_entrance": (4, 4),
    "landmark_and_environment_detail.cliff_formation": (3, 3),  # a cliff face
    "landmark_and_environment_detail.domain_entrance": (4, 4),
    "landmark_and_environment_detail.ground_decal": (1, 1),  # a flat decal
    "landmark_and_environment_detail.ruined_arch": (2, 2),  # an arch you walk through
    "landmark_and_environment_detail.statue": (2, 2),
    "settlement_and_domain_prop.cultivation_altar": (2, 2),  # an altar
    "settlement_and_domain_prop.domain_seal": (2, 2),
    "settlement_and_domain_prop.resting_stone": (1, 1),
    "settlement_and_domain_prop.sealed_cache": (1, 1),  # a cache
    "settlement_and_domain_prop.shelter": (3, 3),  # a hut; was (2,2) and (8,8)
    "settlement_and_domain_prop.storehouse": (4, 4),  # the building
    "settlement_and_domain_prop.supply_crate": (1, 1),  # a crate
    "settlement_and_domain_prop.workbench": (2, 2),  # a bench
    "stone_and_ore.boulder": (2, 2),  # waist-high rock
    "stone_and_ore.crystal_growth": (1, 1),  # a single growth
    "stone_and_ore.mineral_spring": (2, 2),
    "stone_and_ore.ore_vein": (1, 1),  # a seam in rock
    "stone_and_ore.rubble": (1, 1),
    "stone_and_ore.small_rock": (1, 1),  # a pebble; was (2,2) in some environments
    "stone_and_ore.standing_stone": (2, 2),
    "stone_and_ore.stone_cluster": (2, 2),  # several stones together
    "terrain_texture.base_surface": (1, 1),
    "terrain_transition.cliff_edge": (1, 1),
    "terrain_transition.ground_edge": (1, 1),
    "terrain_transition.shore_edge": (1, 1),
    "terrain_transition.slope_ramp": (1, 1),
    "terrain_transition.terrain_corner": (1, 1),
    "terrain_transition.terrain_inner_corner": (1, 1),
    "terrain_transition.terrain_island": (1, 1),
    "terrain_transition.trail_edge": (1, 1),
    "travel_and_wayfinding.path_gate": (2, 2),
    "travel_and_wayfinding.portal_frame": (4, 4),
    "travel_and_wayfinding.signpost": (1, 1),  # a post; was (2,2) in some environments
    "travel_and_wayfinding.stone_bridge": (2, 1),  # a bridge spans, it does not tower
    "travel_and_wayfinding.stone_waypoint": (1, 1),  # a marker
    "travel_and_wayfinding.trail_marker": (1, 1),  # a marker; was (1,1)/(2,2)/(8,8)
    "travel_and_wayfinding.travel_shrine": (2, 2),
    "travel_and_wayfinding.wooden_bridge": (2, 1),  # a bridge spans, it does not tower
    "water_feature.deep_water": (1, 1),  # terrain, sized by the grid
    "water_feature.pool": (2, 2),  # a pool wide enough to read
    "water_feature.shallow_water": (1, 1),  # terrain, sized by the grid
    "water_feature.spring": (1, 1),  # a spring head
    "water_feature.stream": (1, 1),  # terrain, sized by the grid
    "water_feature.water_foam": (1, 1),  # surface detail
    "water_feature.water_plant": (1, 1),  # surface detail
    "water_feature.waterfall": (2, 2),  # a fall has height
}
