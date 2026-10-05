# 0084 An institution grants recognition and access, and never power

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0083 (three tiers, one vocabulary), ADR 0063 (purity gates, never scales),
  ADR 0064 (a clan hands out recognition, not power), ADR 0065 (no second stat composer),
  ADR 0067 (one spine, one seam), ADR 0076 (gates read a ledger, never a stat)
- Resolves: BL-0173

## Context

ADR 0064 already fixed the principle for a clan: *"a clan does not hand out power, it hands out
recognition, and recognition scales what the member's own bloodline is worth."* Nothing has
applied it, because `clan` is an empty facade (ADR 0079). Building a sect and a nation now
means writing the first code that could violate it, so the principle needs to be a decision
with a formula and a test rather than a sentence in a sibling ADR.

The obvious design — a sect grants its members bonuses, better techniques, faster cultivation —
is wrong three separate ways, and each failure is already measured somewhere in this repo:

- **A FLAT grant is realm-blind.** ADR 0063 measured it for bloodline purity: a flat value is
  *dominated by the stat pool early and is noise by roughly realm 12*, across a ladder that
  now spans 1.0x to 551x (`core/realm_power_table.tres`, ADR 0050). A bonus that is decisive at
  R2 and rounds to nothing at R20 is a bonus for the first hour of the game.
- **A FLAT grant on a rate stat is a declared content error.** ADR 0068 states the trap exactly:
  `Stat.DAMAGE_REDUCTION` is FLAT with baseline `0.0` and is deliberately absent from
  `RATE_STATS`, so a `PERCENT` modifier there evaluates to `(0.0 + 0.0) * (1 + p) = 0.0` — a
  silent no-op that shipped on 44 items. The mirror failure is standing's: a political number
  that **rises and falls** must never be a multiplier on the whole game's progression rate, or
  a demotion becomes a nerf no authored budget accounts for.
- **A base-attribute write smuggles the member through the gates meant to test them.**
  `ItemRequirement` reads base allocation only, and ADR 0052/0054 pinned that deliberately: *"a
  technique can never satisfy its own requirement with the stats it grants."* `set_base`
  bypasses the modifier stack entirely, so it cannot be stripped, cannot be rebuilt
  idempotently, and does satisfy `get_base(...)`.

## Decision

**An institution grants exactly three things. A fourth is a new ADR.**

1. **Recognition** — `standing`, projected as a **bounded `PERCENT`** on an authored stat
   allowlist.
2. **Access** — membership gates: which shelf, which office, which contest, which doctrine tier.
3. **Transmission** — `fit` (affinity), which projects **zero modifiers**. It is a gate and
   nothing else.

**The formula is one, and it is in `core/` so it cannot be restated:**

```
standing_percent(standing) = min(STANDING_PERCENT_CAP, STANDING_RATE * standing)
```

Applied at the single modifier application stage (ADR 0026), as
`StatModifier(stat, Stat.Op.PERCENT, standing_percent(...), &"sect:<sect_id>")`, source-tagged
and rebuilt from the ledger on every attach — `SectProjection.apply` strips before it rebuilds,
exactly as `DestinyProjection` and `RaceProjection` already do. **No second stat composer. No
`set_base`. No new `StatProvider` carrying institution values.**

- `STANDING_RATE` and `STANDING_PERCENT_CAP` are authored constants, and the cap is the whole
  point: the entire political stat surface of the game is bounded by construction, so no
  ladder of authored positions can add up to an uncapped multiplier.
- **The allowlist is authored per position**, not global, so an author chooses which stats a
  position recognises. Every id on it must have a **non-zero baseline in its derivation**, or
  ADR 0068's shape test requires a `FLAT` op instead and the choice stops being a percent.
- **A refused verb writes nothing.** Every refusal leaves the ledger byte-for-byte as found
  (ADR 0044), and a successful standing move publishes its delta so the write is observable.

**Why `PERCENT` and not `FLAT`, in one sentence:** a percent rides the member's own growth, so
an institution is a real edge at its realm and *exactly as strong at R5 as at R30* — ADR 0063's
sentence, reused verbatim — while a flat breaks realm-invariance and hands a deep-realm actor a
compounding advantage.

**Authority is authored data, not a number.** A position carries `duties` (what the holder must
do) and `authorities` (what the holder may do), both `Array[StringName]` of authored verbs.
"May this member expel another" is therefore a `.tres` question. Rejected: `if rank >= 3`,
which is exactly the numeric hierarchy ADR 0064 kept out.

**Refusals are named game rules, never input validation.** Every mutating verb returns
`{"ok": false, "reason": <named>}`, and `reason` is an authored constant, not free text — the
same shape `DestinyApi.gate` and `SocialApi.gate` already produce, so a panel renders a reason
it did not have to invent. The load-bearing ones, each a rule rather than a check:

- `standing_below_floor` — the ordinary promotion gate. **It is a route, not a wall:** promotion
  on thin standing stays expressible, which is what ADR 0064's two-part split is for.
- `capacity_full` — the position's authored cap is reached. An overflow is a **refused admit**,
  never a silent trim.
- `seat_occupied` — the cap is 1. Distinct from `capacity_full`, and a test pins the difference,
  because they produce different player-facing situations.
- `cannot_expel_equal_or_above` — you cannot purge your equals. Without it a sect is a
  totem-pole and one strong elder is unassailable forever.
- `not_a_member` is the **only** thing `leave` refuses on. Leaving is always permitted; the cost
  is standing, never a gate. A player with no exit is a bad state with no out.
- Expulsion costs the expeller **strictly more** standing than it costs the expelled. That
  asymmetry is what makes an inquisition a political act rather than an admin action.

**A succession is walked, never rolled** (ADR 0058's shape). It advances one authored stage per
call and refuses a further step until a period elapses. No `rng` is consulted, so the outcome is
a function of the ledger and a test needs no seeded generator. Rejected: rolling
`standing / threshold`, which makes a promotion a gambling event and a gate that can satisfy
itself.

## Consequences

- **The refusal is structural, so the guard is a test.** `tools arch` cannot see a method that
  does not exist. The invariant is pinned the way `test_destiny_earning.gd` pins the absence of
  a removal verb: read the facade's published method list and assert it contains none of
  `grant_stat`, `grant_attribute`, `set_base`, `add_base`, `power_up`, `buff`, `apply_modifier`.
  A future verb that grants power fails there rather than in review.
- **A second test pins realm-invariance in ratio**: for one actor, the derived-stat ratio on
  every allowlisted id is identical at R1 and at R30. That is the measurement that makes "a
  percent, never a flat" a property rather than a hope.
- **`SectProjection` must record what it granted**, because a `StatModifier` cannot lower a base
  attribute and a projection that cannot be inverted is a projection that compounds on re-attach.
  `RaceState`'s `applied_race` / `granted` fields are the precedent; ADR 0063 explains why the
  ledger stores the granted numbers rather than re-reading the definition, which is also why
  stripping still works after a `.tres` is deleted.
- **A ledger is `normalize()`d on every read** and must round-trip through
  `JSON.parse_string(JSON.stringify(actor.to_dict()))`. `core/actor.gd` copies `module_data`
  verbatim with a hook only for items, so a `Resource`, an `Actor` or an inner `StringName` key
  in a ledger reaches the save untouched and silently breaks every save. The outer key is
  converted with `String(key)`; **inner keys are not**, so the discipline has to be written by
  hand.
- **The whole institutional stat surface is one capped percent.** That is a small surface on
  purpose. If a future design wants an institution to grant a flat magnitude, a passive of its
  own, or a new stat provider, it supersedes this ADR rather than widening it.
- Two design consequences are free rather than designed: a position that recognises a stat whose
  baseline is zero cannot work until the shape test forces `FLAT` (so the allowlist is
  self-checking), and because `standing` can fall, the only way a member ever loses power is a
  demotion — which means the demotion path must be as well tested as the promotion path.