# 0199 Boss vitality is the anchor pool at its own realm's authored power

- Status: Accepted
- Date: 2026-10-04

## Context

ADR 0133 left one question OPEN and it has been carried as OPEN through four subsequent
state reports:

> **The 551x-vs-20x question is OPEN and this ADR does not settle it.** `combat_engine`
> scales `ATTACK_PHYSICAL` by authored realm power, `1.0` to `551.46`
> (`core/realm_power_table.tres`), while authored boss vitality spans **40-800 across 320
> `game/data/loot` encounters** — a 20x span, not the 12x `combat`'s docstrings claim.

`combat_boot.gd:572` restates the same measurement from the other end: the engine "does
14.1% of a boss's pool at R1 and 2032% at R30 — a 144x runaway with nothing on the other
side of it." A boss at `heaven_immortal` is a one-press kill; a boss at `qi_refining` is a
fight nobody finishes.

ADR 0197 then ruled the anchor that settles it: **two same-power actors, no heal, no dodge,
resolve in 60 seconds**, with `Stat.ATTACK_SPEED` as the rate lever. It measured that
`hits_to_kill` is **~25 at every realm R1-R30** and therefore left the ladder alone —
*the ladder and curve are correct; fix authored BOSS vitality to match.* ADR 0197 explicitly
declined to write the content change itself ("another lane owns the retune, and nothing
here writes a `.tres`").

Two candidate answers were on the table and ADR 0050 decides between them:

- **(A) scale the boss's pool** — the only option that leaves `RealmDef.power` the sole
  source of a magnitude.
- **(B) normalise the engine's damage** — which would make a magnitude a computed curve,
  the category error ADR 0050 was written to prevent, and would flatten the ladder the owner
  has ruled correct.

## Decision

**(A). Authored boss vitality is `HITS_TO_KILL * BASE_HEALTH * RealmDef.power(realm)`,
keyed by realm ID, and it is generated.**

    vitality(realm) = 25 * 75 * RealmDef.power(realm)
                     = 1875 at R1 (qi_refining), 1033987.5 at R30

Three terms, **every one already authored**:

- `HITS_TO_KILL = 25` is the owner's blow count from the ADR 0197 anchor.
- `BASE_HEALTH = 75` is `Stat.MAX_HEALTH` of the anchor's own reference actor; with its
  authored `ATTACK_PHYSICAL` of 3.0, `75 / 3.0 == 25` blows. Quoted from the actor table,
  not a new curve.
- `RealmDef.power` is `core/realm_power_table.tres` keyed by realm id — **the same axis
  `RealmScaling` already multiplies an actor's `MAX_HEALTH` and `ATTACK_PHYSICAL` by**, so
  a boss's pool tracks an actor's pool along an axis the ladder already owns.

The harder band (`tier != 1`) pays `HARD_TIER_MULTIPLIER`. A WORLD domain band is floored
at `WORLD_DOMAIN_FLOOR`, because a world's band realm is a DERIVED drop-context label
(`Graph.band_realm`) and pricing a fight off it would price the fight off a drop label.

**The content is GENERATED and the generator is the single source of truth.**
`tools/acquisition/design.py::vitality` computes it and `tools/acquisition/emit.py` writes
it. All 160 `game/data/loot/encounters/*.tres` are regenerated from it. **No `.tres` is ever
hand-edited**, per brief rule "never hand-edit generated seed data". A realm the power table
does not carry raises `ToolError` rather than defaulting — a missing realm is a content gap,
not a number to invent.

The previous formula was `40 + 8 * realm_index`, **linear in the INDEX** — the category ADR
0050 exists to prevent. It gave 40-272 (6.8x) against the ladder's 551x, and `realm_index`
has no runtime meaning at all: `RealmPowerTable` is keyed by realm ID, so inserting one
realm in the middle silently shifts every realm below it onto the wrong number. Keying by
realm id lets the table do the work it was designed for.

## Consequences

- **ADR 0133's open question is CLOSED.** Authored boss vitality now spans the ladder's own
  551x instead of 20x, so a same-realm boss takes ~25 same-realm blows at EVERY realm — the
  anchor, measured rather than asserted.
- **The ladder is untouched.** `core/realm_power_table.tres` and `RealmRate` are not edited,
  per the owner's ruling. No file under `modules/combat_engine/` is edited; the change is
  entirely in a Python content generator and its emitted `.tres`.
- **This does NOT reverse ADR 0123/0126.** `combat`'s share model still resolves authored
  boss encounters and `CombatSpine` still resolves actor-facing blows. This ADR fixes the
  NUMBER the share model spends, so the share model's clamp no longer has to rescue a pool
  that is three orders of magnitude too small.
- **The share model earns its keep.** A 1875 pool at R1 was already survivable; a
  1033987.5 pool at R30 is not reachable by the share model alone, and `clampf(MIN_SHARE,
  1.0)` is not a balance solution. Correct authored content makes the clamp a backstop
  rather than the mechanism.
- **`battle_boot.gd`'s 144x runaway figure is stale** and should be re-measured; this ADR
  changes the number it was computed from.
- **Data tooling caveat:** `tools/acquisition/emit.py` notes generated `vitality` that reads
  back as an int is a shape difference — the values exceed float precision readability at
  R30 (`25 * 75 * 551.46 = 1033987.5`), which is why `float_text` must not round.
- **`Actor.SCHEMA_VERSION` stays 4.** A band's vitality is authored content resolved by
  `LootTier.vitality_for`, not a persisted actor shape.