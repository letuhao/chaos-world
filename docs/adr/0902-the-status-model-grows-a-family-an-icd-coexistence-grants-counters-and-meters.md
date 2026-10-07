# 0902 the status model grows: family, categories, an ICD, coexistence, grants, counters and meters

- Status: Accepted
- Date: 2026-10-07

## Context

The Keepverse status port (DEF-0363, picks P1–P15) adds mechanisms our model lacks: an authored `family` and
`categories`, an explicit crowd-control flag, a per-status ICD, the third stacking semantic (`coexist`), a
grant handle with lifecycle verbs, counter milestones and meter accumulators, apply-shape tuning, and two new
refusal reasons. This ADR records where each mechanism lands and which boundaries it must not cross. Spread
and projection stay backlogged (`BL-0925`/`BL-0924`, after the six layers); the payload taxonomy is mapped,
not renamed; the per-category resist cap is declined; the 12→15 re-key is out of scope (DEF-0359).

## Decision

1. **Def shape (P2/P3/P4/P12).** `StatusDef` grows `family`, `categories`, `crowd_control`, and `icd`
   (authored per def; the tuning file carries a default, P4=C). `family` and `category` join the resist
   resolution as two channel terms (`status.resist.<family>` / `status.resist.<category>`) beside the
   shipped omni/kind/status/element terms, and immunity resolves through the same family/category tags.
   `STACKING` gains `coexist` (never matches an existing instance); `replace` clears every same-id instance
   and `refresh` matches one — Keepverse's `UpsertInstance` semantics. Our magnitude `stack` is kept.
2. **Lifecycle + readback (P5/P13).** Application carries a `grant_id`; the facade grows
   `clear_grant(grant_id)` and `withdraw(actor)`, plus an applied/resisted event surface — the resisted log
   carries the reason. `summary()` publishes primitives only, for tests and future screens.
3. **Counters (P6=C).** One actor-scoped counter store with two key spaces: grant-keyed (`grant|scope`) and
   per-instance (identity fixed by the stacking semantics). `every_hits`, `reset_on_burst`, the residual
   (`n % every_hits`) and coalesced hits follow Keepverse's measured `RecordCounterHit` semantics; the
   spine's landed-blow event reaches it through a status facade verb — no new module edge.
4. **Meters + kinds (P7/P2).** Kinds `counter` and `meter` land over ONE accumulator with two sources (hit
   counts and value events). UnityCc maps onto `control` (no new kind); contagion waits for spread (P9).
5. **Apply math + tuning (P10/P11/P15).** Shape/offset/steepness, the per-category hooks (pass-throughs for
   now), a default-OFF tier-power knob, and the ICD default all live in `CombatTuning`/`combat_damage.tres`;
   the linear default reproduces today's parity-½ byte-identically; an authored-completeness guard test fails
   when a required key is not authored. No second tuning file (versioned JSON declined).
6. **Refusals (P14).** `status_icd` and `useless_magnitude` join the closed reason vocabulary;
   existing reason strings never rename. The order is LAYERED because the layers own different
   facts: the combat gate refuses immunity → potency floor → apply roll (unchanged), and the
   status module refuses `status_icd` BEFORE the effect lands — it is the only layer that owns
   the per-instance lockout clock (P4). `useless_magnitude` refines the potency split (T8). An
   unknown id is a lookup failure, not a refusal.
7. **Mind tree (T7).** The mind defs (`res://src/data/mind_statuses` — their own roles, shapes, steepness,
   refresh-only stacking) are NOT gated by the new mechanisms: no family term, no status ICD, no counter
   store copy. Their lock guards stay as shipped; sharing is limited to pure helpers.
8. **Persistence (T13).** MEASURED: statuses do not ride the actor save at all (ADR 0089 — `Actor.to_dict`
   emits no `statuses` key), so counters, meters, grant handles and the ICD clock are transient WITH them,
   and the blessing tree's own save carries only its blessing records. No schema change; the evidence is
   `test_status_persistence.gd` beside `test_status_round_trip.gd`.

**Payload mapping (declined rename).** Their `PulseHp` → our per-tick pool writes; `ModifyStat` → our payload
modifiers; `UnityCc` → `control` + the CC flag; `Spread` → P9 (`BL-0925`). Our mechanics vocabulary is the
shipped one; no second taxonomy.

## Consequences

- Content gains authorable family / category / ICD / CC fields; every new channel id must be visible to the
  content coverage gate or it ships unwritable.
- One counter store, one accumulator, one ICD: guards pin that no second copy ever appears (T2/T5/T7).
- Apply defaults keep every shipped number byte-identical until content earns a change.
- P8 (projection) and P9 (spread) remain the only deferred mechanisms, both gated behind the six layers
  with a drift re-audit against DEF-0363 before building.
