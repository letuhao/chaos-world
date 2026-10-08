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
# --- Boss vitality: the 60-second duel anchor, applied to CONTENT ------------

# The owner's ruling (ADR 0197): two actors of the same power, no healing, no dodging,
# should finish a fight in 60 seconds, which at the ladder's own blow rate is **25
# landed blows**. The ladder already delivers that -- `RealmScaling.SCALED_STATS`
# carries both `Stat.MAX_HEALTH` and `Stat.ATTACK_PHYSICAL`, so an actor's health pool
# and its attack grow by the SAME authored `RealmDef.power` and the blow count is
# constant down the whole ladder. The ladder and the curve are therefore NOT touched.
#
# What was wrong is AUTHORED BOSS VITALITY, which was flat at 40-800 (~20x) against a
# realm table that spans 1.0-551.46 (551x). A boss's pool is spent by the same blows
# that spend an actor's, so a boss at a high realm must carry a proportionally larger
# pool or the fight against it is a formality.
#
# ## The formula
#
#     vitality(realm) = HITS_TO_KILL * BASE_HEALTH * RealmDef.power(realm)
#                     = 25 * 75 * power            (= 1875 at R1, 1033987.5 at R30)
#
# Three terms, and **every one is already authored**:
#
# - `HITS_TO_KILL` (25) is the owner's blow count, and is the anchor itself.
# - `BASE_HEALTH` (75) is `Stat.MAX_HEALTH` of the anchor's own reference actor: the
#   brief's measured table reports a 75.0 pool and a 3.0 attack at R1, and
#   `75 / 3.0 == 25` blows. One constant, quoted from the actor table, not a new curve.
# - `RealmDef.power` is the authored ladder `core/realm_power_table.tres`, keyed by
#   realm id -- the SAME axis `RealmScaling` already multiplies an actor's health by.
#
# So the boss's pool tracks an actor's pool along the axis the ladder already owns.
# There is no new scale and no formula to fall back on: ADR 0050 says a magnitude is
# `RealmDef.power`, and this is one.
#
# ## Why the previous formula was wrong, and it was not a rounding error
#
# It was `40 + 8 * realm_index`: LINEAR in the index, which is the category ADR 0050
# exists to prevent. It gave R1..R30 40-272 (6.8x) where the ladder gives 1.0-551.46
# (551x). `realm_index` also has no runtime meaning -- `RealmPowerTable` is keyed by
# realm ID, so an insert in the middle of the ladder silently shifts every realm below
# it onto the wrong number, which is the exact failure the id-keying scheme prevents.
# And a *world* band's realm is a DERIVED drop-context label (`Graph.band_realm`), not
# a claim about where the domain sits on the ladder, so pricing a fight off it was
# pricing the fight off a drop label.
#
# ## `WORLD_DOMAIN_FLOOR` -- and why the index had been hiding the need for it
#
# A world domain's band realm is the LOWEST realm any of its drops belongs to, and 59
# of the shipped world bands carry a `qi_refining` or `foundation` label purely because
# they drop something low. Priced straight off that label, R1 of them get 1875.0 and an
# R30-reaching domain 1033987.5 -- a 551x spread between two creatures whose own drops
# say nothing about their strength.
#
# `WORLD_DOMAIN_FLOOR` is a deliberately conservative LABEL FLOOR for a band whose
# declared realm is not a claim about the fight: the ladder rung such a band's pool is
# floored at, and it is `MORTAL_INDEX + 1` (R5, `void_refinement`), a rung where a weak
# creature is still a fight rather than a formality. It moves the LABEL, never the
# rule: a world band is still priced off its declared realm and the floor only ever
# RAISES a label that under-reports. The number itself is a CONTENT decision ("a weak
# creature is a R5 gate, not a R1 formality"), not a power curve, which is why it is
# stated here as a label and not derived from `RealmDef.power`.
WORLD_DOMAIN_FLOOR = 5

# The blow count the owner's ruling fixes: 25 landed blows in 60 s is 25 blows/min,
# one blow every 2.4 s. It is also `Stat.ATTACK_SPEED`'s lever (baseline 1.0, cap 2.5)
# and never a new constant.
HITS_TO_KILL = 25

# `Stat.MAX_HEALTH` of the anchor's reference actor, before gear. Quoted, not derived:
# see the block above -- it is the 75.0 pool the brief's measured table reports, and
# `1875.0 / 75.0 == 25.0` is the anchor restated as a pool rather than as a blow.
BASE_HEALTH = 75.0

# A deep band is a harder fight, and it says so by carrying a larger pool AND, through
# `LootTier.attack_for` / `defense_for`, proportionally harder-hitting and tougher
# bosses. It is the tier's whole meaning and is unchanged by ADR 0197.
HARD_TIER_MULTIPLIER = 1.6

# `RealmDef.power`, keyed by realm id, read off the authored table. Lazy, so importing
# this module never touches the filesystem -- `design.py` declares decisions, it does
# not read content, exactly as its own docstring claims.
_POWER: dict[str, float] | None = None


def realm_power() -> dict[str, float]:
    """`RealmDef.power` per realm id, read off `core/realm_power_table.tres`.

    The ladder itself, not a formula over it, for the three reasons `RealmDefaults`
    states: reading a file cannot need the realm count, a consumer that looked the
    number up its own way would hold a private copy of the contract, and the table is
    keyed by id so a realm inserted mid-ladder cannot shift every realm below it.
    """
    global _POWER
    if _POWER is None:
        from ..realm_power import read_table

        _POWER = read_table()
    return _POWER


def _floor_power() -> float:
    """`RealmDef.power` at [constant WORLD_DOMAIN_FLOOR], resolved through the ladder.

    Resolved rather than quoted, because a ladder that grows is a ladder whose fifth
    rung moves, and a quoted power would then be a second curve next to the first.
    """
    from ..realm_power import load_realms

    realms = [realm_id for realm_id, _name, _tier in load_realms()]
    return realm_power()[realms[WORLD_DOMAIN_FLOOR]]


def vitality(realm_id: str, tier: int, *, ladder: bool = True) -> float:
    """A band's authored vitality: the anchor's pool, at `realm_id`'s authored power.

    `realm_id` is the band's OWN declared realm and `tier` its ordinal, so the caller
    stops passing a ladder index and the id-keying scheme gets to do its job. `ladder`
    is False for a WORLD domain, which is floored per [constant WORLD_DOMAIN_FLOOR].

    A realm the power table does not carry is a content gap, not a number to invent:
    `ToolError` rather than a default that would silently mis-price a whole band.
    """
    from ..common import ToolError

    power = realm_power().get(realm_id)
    if power is None:
        raise ToolError(
            f"no RealmDef.power for realm {realm_id!r}; run "
            "`uv run python -m tools realm_power emit` before seeding content"
        )
    if not ladder:
        power = max(power, _floor_power())
    base = BASE_HEALTH * power
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
