# 0085 A conflict is a declaration of sides and a prize, and never a formula

- Status: Accepted
- Date: 2026-10-03
- Depends on: ADR 0067 (one spine, one seam), ADR 0076 (an encounter is a stat-resolved
  exchange), ADR 0077 (the damage spine is designed, not built), ADR 0083 (one vocabulary),
  ADR 0084 (no stat grants)
- Resolves: BL-0187, BL-0193, BL-0194, BL-0196

## Context

War, siege, rivalry and schism are the parts of a sect/nation feature most likely to become a
second combat system. The failure has a specific shape and the repo has already paid for it once.

ADR 0076 built the real damage model: `CombatApi.resolve_hit` / `exchange`, where damage is a
**share of the target's own pool** so the 551x realm table moves both sides together and cannot
make an endgame actor one-shot a low-realm boss. ADR 0077 then recorded the cost of getting
ahead of the design: five Accepted ADRs describing a spine, a `DamageMechanism` seam and a
`CombatTuning` resource, and **not one of the named symbols existed** — 0 hits for
`DamageMechanism`, `DamageProposal`, `CombatTuning`, `element_share` across the whole repo. That
is the state this ADR must not repeat. A political layer that rolls its own damage numbers does
not merely duplicate the model; it forks it, and the fork is the one nobody can see coming.

Two further facts constrain the design rather than merely caution it:

- **Stances are already a decided shape.** ADR 0047 makes faction stance symmetric — *"if A is
  hostile to B, B is hostile to A"* — and authored as `WorldFactionDef.relationships`. A sect
  rivalry and a nation diplomacy that store a one-sided opinion would be a third, incompatible
  answer to the same question.
- **`DEF-0097` still carries a superseded formula in its `reason` field.** It specifies
  `mitigated = attack * (100/(100+defense))` with crit clamped at 0.75 — the pre-spine shape
  that ADR 0067 replaced with its 11 stages and ADR 0069/0070/0071 then split per path. An agent
  building war resolution from DEF-0097's prose would build exactly the second formula this ADR
  refuses. That entry needs a supersede note, and it is the highest-value line of work this ADR
  creates.

## Decision

**A conflict is a declaration of sides and a prize. It is not a fight, and it owns no number.**

- **A declaration writes a standoff**: two institution ids, a mode, a verdict quota, an
  exhaustion counter, and **the prize, declared up front and never computed at resolution.** The
  prize is `transfer` (`ownership` | `recognition` | `tribute`) plus a standing delta per side.
  Fixing the prize at declaration is what makes a conflict a political object rather than a
  scoring function: both sides know what is at stake before the first verdict.
- **Verdicts arrive from outside.** `resolve_conflict` accepts an outcome already decided —
  a `CombatApi.exchange` the caller ran, a tournament result, a tribunal's ruling. The
  conflict module **never calls combat, never reads a combat stat, and never owns an `rng`.**
  It counts verdicts and pays the declared prize when the quota is met.
- **The module's only arithmetic is `tally + transfer`.** There is no `army_strength`, no
  `territory_defense`, no aggregate hit points, no unit counts. Those would be a second magnitude
  ladder beside `realm_power_table.tres` (ADR 0050) and a third unreconciled per-realm-style
  scale.
- **Exhaustion decides whether a side may keep fighting, never who owns ground.** A side that
  loses verdicts accrues exhaustion and must withdraw or forfeit at a declared standing cost;
  **a withdrawal moves no territory.** Without this, a conflict is decided by a counter and the
  declaration is decoration.
- **`mode` changes the quota and the prize shape only**, never how a verdict is produced:

| `mode` | quota | prize | verdict source |
|---|---|---|---|
| `contest` | 3 | ownership + standing deltas | combat, three times |
| `siege` | 5 | ownership + recognition | combat, five times |
| `tribunal` | 1 | tribute only | a named third institution's standing, **read** |

  `tribunal` is the honest escape hatch: the one place the political layer makes a judgement, and
  it reads `standing` — a number the institution already owns (ADR 0083) — never damage. An
  institution that cannot field a champion can still buy its ground back by owing a favour.

**Stance is one canonical row per unordered pair, on every tier.** The key is the two ids ordered
lexicographically, so `summary()` read with the ids swapped returns the identical dictionary and
a one-sided opinion is structurally impossible. This extends ADR 0047's symmetry rather than
restating it.

- **Diplomacy is a closed verb set**: `rival`, `neutral`, `allied`, `truce`, `embargo`, `war`. An
  unknown value refuses closed and **names itself** in `reason` (the `DestinyGate` precedent);
  nothing anywhere defaults an unreadable stance to neutral. `war` is reachable **only** through
  the declaration verb, refused as `war_requires_a_prize` otherwise — so no war can exist without
  a declared prize.
- **A claim on held ground never moves ground.** It writes a challenger and opens exactly one
  standoff. `holder_id` is byte-identical before and after. This is the invariant that separates
  a claim from a conquest.

**Schism costs both halves.** A split halves the undivided standing, charges each half a
declared cost, and charges each half again per territory the declaration leaves unassigned.
A free schism is a strictly-positive action, so every crisis would end in a split and no
institution would ever have to answer for one.

## Consequences

- **DEF-0097 needs a supersede note before any of this is built.** Until then its `reason`
  describes a formula ADR 0067 replaced, and it is the single most likely source of a second
  damage model. Recorded as work, not done here.
- **The conflict module is testable before combat exists**, because verdicts are injected. That is
  deliberate: ADR 0077's lesson is that a layer written ahead of its dependency stays written
  ahead of it. `resolve_conflict` is fully testable now and wireable later, and the wiring is one
  call at the place combat decides.
- **`contest` succession must not ship before a tournament can call it.** An authored-but-
  unreachable succession method is the same dead content ADR 0063 shipped as unreachable tiers.
  The first content wave authors `heir`, `trial` and `appointed` only.
- **Territory grants no combat bonus.** A home-ground defense modifier would make the map a
  combat *input*, so every territory inherits a balance obligation against every mechanism. The
  terrain's effect is authored *content* — which technique a side chooses to fight there — and
  the combat model does the rest. Territory decides who may fight and where; the spine decides
  who wins.
- **A defeat lowers a number and never dissolves an institution.** Standing recovery is authored
  and bounded, so a lost war is a condition to climb out of rather than a save-deletion.
- There is **no world tick**, so nothing accrues on its own. Every accrual takes an explicit
  period count from a caller that owns time (DEF-0111), and a module that invented a timer would
  be a second source of truth for when a save happened.