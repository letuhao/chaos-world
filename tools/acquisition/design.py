"""The authored design of a body trial, as named constants.

Every number here is a decision a reader could reasonably get wrong, so it is
declared once and named rather than inlined in the generator. Nothing in this
module reads content; `plan.py` turns these constants plus the authored graph into
`.tres` text.
"""

# --- Ids -------------------------------------------------------------------

# `loot_<boss_id>` is a boss's own table and `loot_<domain_id>` its encounter.
# The `loot_` prefix is the one the shipped content already uses, so a collision
# means a file was authored by hand on purpose and must not be overwritten.
TABLE_PREFIX = "loot_"
ENCOUNTER_PREFIX = "loot_"
# A boss's migrated non-catalyst loot, grouped by the realm its items roll at, so
# one iron relic in a primordial trial still rolls at an iron magnitude.
POOL_SUFFIX = "_pool_"
# An authored item with no `realm` still needs a stable pool id, and its drops
# fall back to the trial's own context because a table cannot declare an empty
# realm and mean anything else.
UNREALMED = "unrealm"


# --- A contested domain -----------------------------------------------------

# One domain may carry at most one authored encounter, and two agents seeding the
# same body trial can each claim it. The trial's own `loot_body_*` encounter wins:
# it is two bands deep and guarantees the realm's catalysts, whereas a one-band
# `loot_route_*` encounter ROLLS them. A cleared band grants no second run (rule
# E2), so a rolled catalyst can leave a player permanently unable to reach the
# next realm — the loser is not discarded for seniority, it loses on that soft-lock.
#
# Losing the domain is not the same as losing its content. Every boss the folded
# encounter hosted keeps a table bound on the winner, so its non-catalyst drops —
# the unique artifacts in particular — stay reachable, and the loser's file is
# deleted only after the replacement reads back.
ROUTE_PREFIX = "loot_route_"


def supersedes(encounter_id: str) -> bool:
    """True when `encounter_id` loses a body trial domain to the generated one.

    Scoped by caller, not by name: the seed asks this only about an encounter that
    already claims a body realm's domain, so an unrelated `loot_route_*` encounter
    on a non-body domain is never a candidate for folding.
    """
    return encounter_id.startswith(ROUTE_PREFIX)


def table_id(boss_id: str) -> str:
    return f"{TABLE_PREFIX}{boss_id}"


def pool_id(boss_id: str, realm_id: str) -> str:
    return f"{TABLE_PREFIX}{boss_id}{POOL_SUFFIX}{realm_id}"


def encounter_id(domain_id: str) -> str:
    return f"{ENCOUNTER_PREFIX}{domain_id}"


# --- Difficulty bands ------------------------------------------------------

# A run needs two bands: the loot module refuses a tier a run has already cleared
# (rule E2), so one band would make every catalyst a single chance that cannot be
# retaken, and the shipped content asserts two bands per encounter.
TIERS: tuple[int, ...] = (1, 2)
TIER_LABELS: dict[int, str] = {1: "Gate", 2: "Depths"}
# The deeper band rolls one rarity tier up. Both bands roll for the trial's own
# realm: the band is a statement about difficulty, not about which realm a drop
# belongs to, so moving the realm between bands would mis-scale the loot.
TIER_RARITY: dict[int, str] = {1: "common", 2: "rare"}
# Authored vitality: the pool a boss's share of the fight is spent from. A strike
# is no longer a flat number of button presses — `CombatExchange` resolves the
# player's blow from their own derived stats into a share of this, so the count
# varies with the actor and the fight can be lost (ADR 0076).
VITALITY_BASE = 40.0
VITALITY_PER_REALM = 8.0
HARD_TIER_MULTIPLIER = 1.6


def vitality(realm_index: int, tier: int) -> float:
    base = VITALITY_BASE + VITALITY_PER_REALM * realm_index
    return round(base * HARD_TIER_MULTIPLIER, 1) if tier != TIERS[0] else round(base, 1)


# --- Drop shape ------------------------------------------------------------

# A body realm's three recipes each consume one catalyst, and a failed
# breakthrough consumes another pill, so a realm is worth a dozen crafts. Two
# bands at six guaranteed units each is a comfortable supply that is still finite:
# the trial is a gate the player walks once per realm, not a shop.
CATALYST_QUANTITY = 6
# One weighted draw from the migrated relic pool per resolve. The pool can nest
# once more, so a single resolve stays far below the resolver's plan ceiling.
DRAWS = 1
# Every body trial must yield something: `allow_empty = false` is a promise the
# resolver can keep through the guaranteed catalysts alone.
ALLOW_EMPTY = False
# A route-limited item may only drop from the boss it names, so a generated table
# never lists one under a different boss.
ROUTE_TAG = "unique_route:"
