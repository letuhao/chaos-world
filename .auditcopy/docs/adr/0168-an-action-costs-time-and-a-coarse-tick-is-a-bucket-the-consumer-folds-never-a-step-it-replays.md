# 0168 an action costs time and a coarse tick is a bucket the consumer folds, never a step it replays

- Status: **Superseded by ADR 0173**
- Date: 2026-10-04
- Superseded by: ADR 0173 (the clock is one SSOT, an elapsed span has a fixed event budget, a place advances when observed)
- Depends on: ADR 0089 / DEF-0111 (the caller owns time), 0113 (one monotone fact ledger),
  0117 (one director, one beat), 0066 (one authored constant, one file), 0050 (authored data,
  keyed by name)

## Superseded

**The fold rule survives. The six-tier ladder does not.** This is the trace of a ladder that was
reviewed, measured and then replaced — not a competing proposal. ADR 0173 owns the replacement
design; this file does not restate it.

- **Inherited, still in force:** an elapsed interval is a **count handed down, never a sequence
  of steps replayed** — the finer steps under a bucket are never emitted and never looped;
  surplus is **dropped, never banked**; ratios are **authored whole numbers in one file**, never
  derived from each other or from a tier index; descent is **iterative over an explicit
  worklist** under a machine-checked depth cap, because `test_no_unbounded_wait.gd` cannot see
  recursion.
- **Superseded:** the fixed six-row ladder, the `O(tiers crossed × consumers)` cost claim, and
  `MAX_TIER_DEPTH := 6` *as a cost argument* — the cap as a guard is inherited; what it counted,
  the tiers, is 0173's. A billion-year skip does not **cross** six tiers: it sits **inside** the
  era tier, so the era row is crossed once and the consumer answers from one enormous bucket.
  The claim held only while a span happened to cross the ladder, and the premise this file
  opens with (~10^6 years) is exactly the span where it fails.

## Context — what was measured, still true

The premise is a protagonist who meditates across spans that dwarf playtime: a sect that rises
and falls, a war lasting a generation, a world whose fiction runs to ~10^6 years. The naive
representation — one tick per day — is `10^6 × 365 ≈ 3.65e8` steps, which is not a slow game, it
is a hang. **We must never tick a day.**

The repo has already solved this at exactly one tier, in one line. `app/world_pulse.gd:194-211`
`pull(delta_seconds)` computes `int(_elapsed / PERIOD_SECONDS)` — a period count is a division.
The comment at `:201-204` says it outright: *"Arithmetic, not a loop: a period count is a
division, and a `while` that counted periods up one at a time is the unbounded-wait shape this
repo fails the build on."* This ADR inherits that rule and generalises it upward, because the
shape is not about periods.

Three measurements bound what a coarse tier may cost, and what it may not do.

- **The surplus is already dropped, not banked.** `MAX_PERIODS_PER_PULL := 8`
  (`app/world_pulse.gd:95`), and `:206-209` discards the remainder rather than carrying it:
  *"a banked surplus is a backlog that pays out later at a rate nobody chose"* (`:90-94`).
- **A coarse tier that folds already ships.** `InstitutionResolver._every(total, step)`
  (`app/institution_resolver.gd:159`) is integer division — `step < 2` returns the whole count —
  serving cadences `NEAR/DISTANT/STRATEGIC = 1/4/16` (`:48-50`). Three elapsed over a cadence
  of four is one action. The rule, in production, at a coarser tier than period. Reused, not
  reimplemented.
- **The shipped schema has no unit finer than a period.** `EventStageDef.duration_periods`
  (`:31`) is documented at `:19-20` as *"a count, never a duration in seconds: there is no clock
  (DEF-0111)"*; `EventApi.advance` (`modules/event/api.gd:238`) walks at most one stage per
  period (`:253-275`). The 22 authored values in `game/data/event/events/*.tres` are 0, 1, 2
  and 3 — **one period is the finest authored granularity anywhere in the event schema**, and
  there is no seconds, days or months field on `EventDef` or `EventStageDef`. A day tier does
  not contradict the authored data; it is the first tier finer than anything authored, so it
  must be folded, not walked.

The shape that must **not** replicate upward is in the same file. `app/world_pulse.gd:353-356`
runs `for index in periods:` and offers one `PERIOD_FACT` beat per period. That is legitimate
only because a pull is clamped to 8, against `MAX_OPENS_PER_PULL := 1` (`:100`) and the
`WorldAmbient.ROSTER` stagger at `at_period` 1, 2, 3, 4 (`app/world_ambient.gd:60-65`, whose
comment at `:44-46` names the cap as the reason). **One period = one beat is a consequence of
the clamp, not a permission.** A year must not emit 365 day beats, and an era must not emit 1000
year beats.

And the guard cannot help with the worst version. `tests/arch_rules/test_no_unbounded_wait.gd`
fails the build on any `while` in `res://src` or `res://tests` it cannot show terminating
(`:16-32`), and it is good — but **it cannot see recursion**. `AGENTS.md:54`: *"A recursive walk
needs a depth cap, and `while` scanning cannot see it. A recursive call is not a `while`, so
`test_no_unbounded_wait.gd` passes a `_scan` that recurses without limit; a junction pointing at
an ancestor never returns."* A ladder implemented as recursive tier-descent would be invisible
to it and could hang on a malformed table — which is why this ADR decides a depth guard here
rather than leaving it to the arch rules.

## Decision

- **[inherited] A fold rule, stated so it cannot be misread: an elapsed interval is a COUNT
  handed down, never a sequence of steps replayed.** One bucket, one integer, no replay. Each
  tier folds at most once per crossing and may call the tier below at most once; the count is
  divided, never re-expanded — `_every`'s shape generalised.
- **[inherited] A consumer decides arithmetically what a bucket means to it**, in the unit it
  already speaks. A period-taking verb (`MarketApi.settle(…, periods)`, `market/api.gd:265`;
  `AnchorApi.repair(actor, periods)`, `anchor/api.gd:138`) is **never** handed coarser units
  multiplied out. The caller may divide and must never multiply (`institution_resolver.gd:84-95`).
- **[inherited] Ratios are authored, whole, and never derived from each other or from a tier
  index**, in exactly one file beside `RealmRate` and `InstitutionBudget` (`core/` is a layer,
  not a module — `tools/arch/rules.py:29`). The table is deliberately not self-consistent — a
  30-day month inside a 365-day year is what a calendar *is* — which is exactly why `365` cannot
  be computed from `30` and `12`: that is ADR 0050 in reverse. Precedents: `RATE_STEP := 1.02`
  in one place (`core/realm_rate.gd:76`); `core/realm_power_table.tres` keyed per realm id,
  never by ladder position.
- **[inherited] Surplus is DROPPED at every tier, never banked**, applied before the hand-down
  exactly as `:206-209` does today.
- **[inherited] A test walks the table and fails if a second file declares a tier ratio**,
  reading source the way `tests/core/test_realm_rate.gd:208-224` does. `tools arch` cannot see
  this — `BARE_REF_UNITS` excludes `modules/*` (`AGENTS.md:143`) — so a numerically-identical
  private copy would stay green under every value assertion.
- **[inherited] An explicit, machine-checked depth guard, iterative over an explicit worklist**,
  because `test_no_unbounded_wait.gd` cannot see recursion (`AGENTS.md:54`); the precedent is
  `core/content_scan.gd:22` `MAX_DEPTH := 32` (`content_scan.gd:7-11`).
- **[superseded] The ladder is six tiers.** The table below was the proposal, and it is replaced
  by ADR 0173's named magnitudes — along with the `O(6 × C)` claim beneath it and the migration
  of `PERIOD_SECONDS` into this file, which now goes to 0173's clock instead.

| tier (superseded) | span (authored, in the tier below) | what moves at this tier |
| --- | --- | --- |
| `turn` | the engine's frame delta | the actor acts, and the action costs world time (ADR 0167) |
| `period` | `PERIOD_SECONDS := 120.0`, one sitting's worth | `WorldPulse.offer(PERIOD_FACT)`; one `EventApi` stage; `InstitutionResolver.settle` near/distant/strategic; `QuestApi.advance`; market floor decay — **shipped** |
| `day` | 12 periods (24 min of play) | `ForageApi.harvest(…, periods)`; `HoldingsApi.settle` upkeep; `AnchorApi.repair`; `NpcApi.advance_stage`; NPC presence |
| `month` | 30 days | market stock and price spread, `MarketApi.settle_lot`; `FertilityApi.advance`; `CustodyApi.settle_term`; the price of training |
| `year` | 365 days | `SectApi.advance_succession`; `NationApi.accrue_territory`; institution standing; war resolved to a verdict; a sect's eligibility to found |
| `era` | 1000 years | sect founding and destruction; bloodline drift across generations; era-gated content; what survives |

### This inherits, and does not reopen

No `Time.get_ticks*` outside `app/` (ADR 0089, DEF-0111) — every tier is a caller-supplied
count, and `sect`/`nation` may not own a clock (`AGENTS.md:157`). **Zero new frame drivers**
(`tests/app/test_status_clock.gd:222-230` pins exactly three). **`app/` holds no ledger, and
`WorldPulse.offer` stays the one beat offer point** — buckets reach sinks through the director
(ADR 0117). **`WorldFact` is monotone** (ADR 0113): a tier may accrue a fact, never withdraw one.

## Consequences

- **Survives unchanged:** the event schema is not extended, and no tier finer than a period is
  added to it. `duration_periods` is a count of periods and stays one; a consumer needing a
  coarse interval divides a bucket, and `EventApi.advance` keeps its at-most-one-stage-per-
  period contract. Adding a magnitude is authoring a row, not writing a fold — one row, one
  integer, and a test that the ratio appears nowhere else.
- **Dead with the ladder:** the cost claim. `O(tiers crossed × C) = O(6 × C)` no longer bounds a
  long skip; ADR 0173 prices it. What this file got right is the reason 0173 needed no new
  argument — a period count is a division, and the shape that must never replicate upward is a
  loop bounded by elapsed time.
- **Still deferred, still owed:** where a coarse count persists (the save envelope owns world
  time today, ADR 0128), and whether a calendar exists at all as authored data. ADR 0173 decides
  the clock's shape; neither it nor this record picks the persistence home.