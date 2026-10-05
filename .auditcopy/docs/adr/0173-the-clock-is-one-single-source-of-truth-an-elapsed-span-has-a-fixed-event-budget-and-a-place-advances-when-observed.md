# 0173 The clock is one single source of truth, an elapsed span has a fixed event budget, and a place advances when observed

- Status: Proposed
- Date: 2026-10-04
- Supersedes: **ADR 0168** (a coarse tick is a bucket the consumer folds)
- Depends on: ADR 0167 (an action costs world time), ADR 0169 (a lifespan is a magnitude, a world time-flow is a rate), ADR 0170 (a place reconciles when observed), ADR 0117 (one director, one beat), ADR 0113 (one monotone ledger), ADR 0066 (one authored constant, one file), ADR 0050 (authored data, keyed by name), ADR 0089 / DEF-0111 (the caller owns time)

The number is 0173 and not 0168 because peers took 0168's slot while it was being written.

## Context

**ADR 0168's cost claim is wrong, and the shipped code has the same defect.** 0168 priced an elapsed span as `O(tiers crossed x consumers)` against a fixed six-row ladder and called that independent of elapsed time. It is not: 10^9 years does not **cross** six tiers — it sits **inside** the era tier, so the era row is crossed once and the consumer is handed one bucket of 10^9 to answer from. 0168's own remedy is what makes a consumer's answer proportional to 10^9. The claim is void for the one span this clock exists to represent.

The shipped line is the same shape: `app/world_pulse.gd:353-354` runs `for index in periods: offer(PERIOD_FACT, 1, PERIOD_SOURCE)` — one beat per period. A 10^12-period meditation is 10^12 iterations, and `MAX_PERIODS_PER_PULL := 8` (`:95`) clamps **per call**, so chunking spreads that loop across more calls instead of bounding it. `periods` is data-derived and the loop tests it — `AGENTS.md:52` verbatim, *"a data-derived row count is not a fixed count either"* — and the shape of the recorded memory incident (67 GB resident, two power-cycles, `AGENTS.md:48`).

Two more things are wrong. There is a **real-time clock for the world**: `pull(delta_seconds)` (`world_pulse.gd:194-211`) turns a frame delta into periods, so a player who does nothing still ages the world and a hitch is a world event. And the clock, the ladder and the lifespan table are three authors of the same kind of number.

## Decision

**This supersedes ADR 0168. What survives:** an elapsed interval is a COUNT handed down, never steps replayed; ratios authored as whole numbers in one file, `core/time_ladder.gd`; surplus dropped, never banked; iterative descent with an explicit depth cap; the source-reading guard. **What dies:** the fixed six-row ladder, `MAX_TIER_DEPTH := 6` as a cost argument, and the `O(tiers crossed x consumers)` claim, which held only while a span happened to cross the ladder. Three mechanisms replace it, and each alone is insufficient.

### (a) NAMED MAGNITUDES, not a fixed tier ladder

- **Time is a set of authored, named magnitudes with authored whole-number ratios, in ONE file** — `core/time_ladder.gd` (`class_name TimeLadder`), beside `RealmRate` and `InstitutionBudget`. `core/` is a layer, not a module (`tools/arch/rules.py:29`), so this costs zero new arch edges: ADR 0066's argument for `core/realm_rate.gd`.
- **A span converts by DIVISION into however many of each magnitude it crosses** — never by walking a row index, never by stepping the magnitude below. **Adding a magnitude is one row:** no new fold, no new branch.
- **Ratios are authored, never derived from each other or from a row index** — the ADR 0050 rule. Precedents: `RATE_STEP := 1.02` lives in one place (`core/realm_rate.gd:76`); `core/realm_power_table.tres` is keyed per realm id, never by ladder position. The ladder is deliberately not self-consistent — a 30-day month inside a 365-day year is what a calendar *is* — which is exactly why one ratio cannot be computed from another. Decided here: the **rule** and that the set is authored data; which names ship is what a playtest moves.

### (b) A FIXED EVENT BUDGET

- **An elapsed span of ANY length declares a budget `C` of world events. `C` does not scale with elapsed time, and it is a CONSTANT** — not a formula, not a function of the magnitudes crossed — authored in `TimeLadder` beside the ratios. It is the single number a reviewer tunes. A budget computed from the span is the span's cost wearing a different name.
- **The span says what became POSSIBLE; the budget says how much of it happens.** A billion years means a sect could have been founded and died, a dynasty could have risen and fallen; `C` events are drawn from that possibility space as a function of the span and the ledger, not replayed from the span. **Cost is `O(magnitudes + C)`** — independent of elapsed time, and the claim 0168 could not make.
- **Precedent already in production:** `MAX_OPENS_PER_PULL := 1` (`world_pulse.gd:100`) is this instinct at the smallest scale — one event per pull however many are eligible. `WorldAmbient.ROSTER` (`app/world_ambient.gd:60-65`) staggers four facts at periods 1, 2, 3, 4 **deliberately**, so one pull cannot open four events (`:44-46` names the cap as the reason).
- **Exceeding the budget FAILS LOUDLY** — `push_error` naming place, span and count, and the pass returns refused. **It never truncates** (`AGENTS.md:56`, `:75`: *"If the exit condition cannot be met, make the feature fail loudly"*). `RowBudget` truncates a *screen* and says "N of M" (`core/row_budget.gd:14-16`), the right trade there; world history has no "N of M", and a silently truncated history is worse than a refusal — the player cannot see it and the ledger cannot un-record it.
- **The per-period beat loop (`:353-354`) does not survive a long skip.** A skip hands down `C` offers, not one per period: a period is a conversion unit, an event is what the world does.

### (c) LAZY, OBSERVATION-DRIVEN ADVANCE

- **A place's clock advances when someone LOOKS at it** — actor entry, a content read, or a coarse consumer asking. The advance is **O(1)**: one division against a stored `last_synced` stamp. **Nothing ticks while nobody is there.** This is ADR 0170's reconcile, summarised; 0170 owns the mechanism and is not restated here.
- **The hazard, named because it is the trap an implementer walks into: an observation-driven clock DEADLOCKS if every advance source is itself gated on someone being present.** The world freezes forever, every elapsed calculation returns zero, and the failure is silent — nothing errors, everything is simply always zero. **The fix: ANY observation advances FIRST, then reads.** A reader is a trigger, never a precondition of the trigger; no `if someone_is_here: advance()`.

### The clock is the SSOT; time-shaped constants migrate to it

`TimeLadder` owns the base ratio — `PERIOD_SECONDS := 120.0` moves out of `app/world_pulse.gd:88`.

| file:line | constant | note |
|---|---|---|
| `app/world_pulse.gd:88` | `PERIOD_SECONDS := 120.0` | the **base ratio**; moves into `TimeLadder` |
| `app/status_loop.gd:52` | `SECONDS_PER_GESTATION_DAY` | frame delta converted where a frame has seconds |
| `app/status_loop.gd:60` | `MAX_COLLAPSE_HELD` | a held window in seconds |
| `modules/techniques/technique_upkeep.gd:19` | `MIN_INTERVAL` | shortest authorable interval |
| `modules/domain/environment_field.gd:296` | `TICK_INTERVAL` | hazard re-application cadence |
| `modules/save/save_clock.gd:22` | `AUTOSAVE_PERIODS` | whole periods between writes |
| `modules/save/save_clock.gd:34` | `PERIOD_SECONDS` | **already a second copy**, declared locally "until the clock migration moves it" |

`SaveClock.pull` was fixed this session: it counted **calls**, not periods, autosaving ~12x/second at 60fps while its docstring promised whole periods. Its `PERIOD_SECONDS` is the pending half of that fix and dies with this migration.

- **One allowed exception, permitted BY NAME by the guard: `app/socket_forge_program.gd:85` uses `Time.get_ticks_usec()` as an idempotency stamp.** It is not elapsed time — it is a **uniqueness token** making two enchantments in one tick two requests. A guard refusing it would push a wall-clock stamp back in, or make the request id derive from the clock it exists to prove independence from.
- **The guard READS SOURCE** and fails if any other file declares its own period/seconds ratio, naming file and line. `tools arch` cannot see this — `BARE_REF_UNITS` excludes `modules/*` (`AGENTS.md:143`) — so a numerically identical private copy stays green under every value assertion. Precedent `tests/core/test_realm_rate.gd:208-224`; the mutation is ADR 0116's, where the copy stayed green and only structural pins fired (**403 passed / 3 failed**).

### Where combat's real seconds enter

- **There is NO real-time clock for the world. The world moves ONLY when the player acts. Idle is frozen.**
- **Combat stays real-time and is UNAFFECTED** — it resolves on turns inside one period, and the world does not move while it does.
- **After the fight, elapsed real seconds x the authored periods-per-second rate = periods consumed**, handed to the same explicit-verb path everything else uses. Combat is therefore **the only thing that consumes real time**, and it does so through the same single owner rather than its own conversion.
- **The rate is PERIODS-PER-SECOND, authored per realm tier**, keyed by `RealmDef.tier` and never by ladder position (ADR 0169's rule). The shape is roughly x1 / x4 / x16 / x64: **the rule is decided here, the table is authored, and those numbers are illustrative, not the decision.**

### Chunking and interruption are bounded

- **A long skip is CHUNKED and INTERRUPTIBLE.** An event targeting the PC holds the remaining steps and the player chooses resume-or-take-partial; a partial skip pays its partial price (ADR 0167's per-period pricing).
- **The chunk size GROWS with the elapsed span**, so the chunk count stays small and fixed-ish rather than proportional: `chunks = clampi(ceil(target / chunk_periods), 1, MAX_CHUNKS)`, `MAX_CHUNKS := 64`, **pinned by a test**. One chunk is one budget spend, so a 10^9-year skip is a handful of spends, not 10^9. **Exceeding `MAX_CHUNKS` fails loudly, never truncates.**
- **The depth/iteration guard is explicit and machine-checked, because `test_no_unbounded_wait.gd` cannot see recursion** (`AGENTS.md:54`). Descent is iterative over an explicit worklist, capped as `core/content_scan.gd:22` `MAX_DEPTH := 32` is.

### Refused, with the trigger that would justify each

- **A real-time world tick** (`pull(delta_seconds)` accruing world time) — trigger: never, idle must freeze.
- **A budget computed from elapsed time** — trigger: never, it is the span's cost under another name.
- **Truncating a skip to fit the budget** — trigger: never (`AGENTS.md:56`).
- **A ladder derived from an index, or a ratio derived from a ratio** — trigger: never (ADR 0050).
- **Refusing `socket_forge_program.gd:85` in the guard** — trigger: never; naming it costs one line.

### This inherits, and does not reopen

No `Time.get_ticks*` outside `app/` except the named idempotency exception (ADR 0089, DEF-0111; `AGENTS.md:157`). **Zero new frame drivers** — `tests/app/test_status_clock.gd:222-230` pins exactly three (`item_workbench_app`, `nav_probe`, `player_adapter`), and an observation is not a driver. `app/` holds no ledger; `WorldPulse.offer` (`:232`) stays the one beat offer point. `WorldFact` stays monotone (ADR 0113). Cultivation facades gain **no** time parameter (ADR 0167). History is rewritten by an **epoch overlay** (ADR 0170), never by un-recording a fact. The **ladder and the lifespan table stay separate tables, never derived from each other** (ADR 0169). **This is the ADR for the `core/` change** — a `core/` addition requires one, and the table is the substance of it.

## Consequences

- **A billion-year meditation costs `O(magnitudes + C)`** — the same handful of divisions and `C` offers a single period costs. That is the claim, now true for the span 0168 got wrong.
- **`for index in periods` is retired as the executor of a long skip**, and `MAX_PERIODS_PER_PULL := 8` stays what it always was: a ceiling on **one call**, which a budget is not.
- **Retuning pacing is three one-line edits** — base ratio, magnitudes, budget — and moving one never requires touching another.
- **A place nobody visits stays stale forever.** Accepted: nothing is owed to a place nothing reads (ADR 0170).
- **The magnitudes, the ratios and the budget are unnumbered proposals.** No subsystem has been balanced against them; the invariants are what is decided here.
- **Open, deferred:** the persistence home for coarse world time and the save envelope (ADR 0128, and 0168's own consequence); whether a magnitude is stored by name or by index; whether an epoch overlay's replacement window needs its own budget; and the calendar schema — 365 d/y is a reading convention, not a decided calendar.