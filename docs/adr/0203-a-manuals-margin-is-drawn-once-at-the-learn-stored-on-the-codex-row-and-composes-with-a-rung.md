# 0203 a manual's margin is drawn once at the learn, stored on the codex row, and composes with a rung

- Status: Accepted
- Date: 2026-10-05
- Amends: ADR 0055 (its cost-block refusals, named as the reason `qi_cost` / `cooldown` may not be banded)
- Amends: ADR 0160 (its capacity refusal, extended: the same quantity is refused a band from the roll side)
- Relates: ADR 0053 (learning vs equipping — the margin belongs to the learned copy, not the binding)
- Relates: ADR 0191 (one seed drawn at commit and replayed from the record — the shape `learn`'s `rng` follows)
- Relates: ADR 0196 (the codex quotes the price; this ruling puts the ANNOTATION beside it)

## Context

A technique's `.tres` holds what the manual **says**. What varies per copy is what
that copy picked up in transmission — the corrections in a margin, the fuller
breathing counts. `technique_marginalia.gd` is the roll, and it was shipped with
three defects that a green suite did not catch, each of which is the same defect
class this program has already paid for four times (`delivers`, `bind_target`,
`TechniqueCastView`, `learn_price`): **a verb that is built and tested and does
nothing in production.**

- The gate that decided whether to roll read `row.has("realized")`. `record`
  writes that key on *every* row, including one recorded directly and including a
  v1 row `migrate` gave an empty `[]`, so the key was always present and the roll
  was unreachable for anything not learned through the facade.
- `draw(def, rng)` returned the AUTHORED value when `rng` was null. Production
  passes no generator — `bind_learner` has no seed — so **production was the one
  caller that rolled nothing**. Every copy a real player received was exactly the
  printed sheet. The band existed only in the suites that seeded one.
- Nothing asserted the roll through the real learn path, so both defects sat under
  340 passing assertions.

## Decision

**The roll is made once per LEARNED technique, in `TechniquesApi.learn`, and stored
in the codex row's `realized` array — not in a seed and not in the def.**

### Q1 — When, and where does it live?

`realized`, on the `CodexEntry`, under `TechniqueCodex.VERSION = 2`'s row. The
alternative was to store the **seed** and replay the draw on read.

A seed is the smaller payload and is exactly ADR 0191's shape. It is refused
here for one reason: **the draw must not be re-derivable by anything that changes
under it.** `OptionCatalog.roll_value`, `clamp_to_bounds` and the option's
`precision` are all authored data, and all three are things a designer edits
between two saves of the same character. A stored seed replayed at read time means
a balance retune silently re-rolls every existing player's investment — the same
class of defect ADR 0056 forbids when it refuses to serialize a `TechniqueDef`, for
the same reason: *a fact about the actor, not a copy of the content.* Storing the
realized values makes the annotation a fact the same way the rung is a fact, and
means a retune cannot reach it.

It is drawn at `learn` and nowhere else — not at craft, not at `rebuild`, not at
`inspect`. `TechniqueCodex.entry` builds its `CodexEntry` from the **stored**
margin, never from a fresh draw, because `rebuild` reaches it and a draw there
would make the contribution of an equipped technique depend on how many times it
had been rebuilt. `TechniqueCodex.record` is the one writer and never lets a
caller empty a margin that is already there.

### Q2 — How is it kept deterministic in tests?

By the repo's existing idiom, which this file's header already named: an **optional
seeded `RandomNumberGenerator` passed in as an argument**, exactly as
`ItemGenerator.generate` and `BodyAttemptRoll.replay` take one. No global seeding,
no `randomize()`, no time source.

`draw(def, rng)` takes one draw per rollable option **in authored order**, so a
given seed produces a given margin regardless of how the catalog is built. A
**null** generator now means *the engine's own entropy* — the ambient stream — and
**not** an identity band. That distinction was the production bug: a missing
generator is a missing seed, not a request for the authored value.

### Q3 — Does a band compose with a rung multiplier?

**Yes, they compose — and the composition is asserted, not assumed.**

ADR 0140 scales a passive's stat values by `1.15^rung` (`1.749` at rung 4). A
banded stat value and a rung multiplier therefore meet on the same number. The
argument for allowing it is the ORDER of the two facts, not their count:

- The band is a property of the **manual**, applied **once**, at **one moment**,
  to **one number**. It is then immutable — that is what the payload above buys.
- The rung is applied **once per rebuild**, to *whatever that number now is*.

So the effective contribution is `authored × span × power`, which is one
multiplier applied to the authored figure and one subsequent re-scaling of the
result. It is not two multipliers stacked on an authored value, and the order is
fixed: `roll * rung` and `rung * roll` are the same float, and nothing in the
pipeline evaluates them the other way round.

Refusing to band anything a rung scales was considered and rejected: a passive's
option values are the **only** thing a margin could ever annotate, so the refusal
would be total and the component would become dead content rather than a design
decision.

**What IS refused, and why that is a different question.** The **capacity**
channel (`cult_dantian_capacity`, anything `max_*`) is carried at its authored
value — from both sides now. ADR 0160 refuses a *rung* on it because
`RealmScaling` already MULTs `MAX_QI` / `MAX_STAMINA` by the realm's own
1.0x-551.46x power and the authored dantian capacity re-seals the pool on top. A
*band* there is the same second multiplier from a different mechanism, so the
refusal is symmetric. That is a **triple-multiplier** argument about a pool
maximum, and it does not transfer to a stat: a stat option composes with
everything else on the actor, is bounded by its own `bounds`, and is applied under
one `technique:<id>` tag by a remove-all-then-re-add rebuild (ADR 0054).

The two predicates are written once each (`TechniqueMarginalia.is_capacity_effect`,
twin `CodexEntry._is_capacity`) and tied by a test that walks every `cult_*` option
in the shipped catalog and asserts both agree — a comment is not a tie.

## Consequences

- **`TechniquesApi.learn` gates on the ARRAY, not the key** (`row.get("realized",
  []).is_empty()`). A v1 row with no seed to replay is now eligible for a roll on a
  re-learn; a row that carries a margin never re-rolls.
- **`draw` no longer has a no-roll path.** Production rolls from engine entropy at
  the learn that stores the result; a test passes a seed.
- **Four values stay authored and refuse a band, each for a named reason:**
  `magnitude` (ADR 0055's ladder coefficient, read off the SHARED catalog resource
  by `CombatSpine.base_damage` — a per-actor copy would be on for one route and off
  for the next hit, and would double-multiply a base already scaled by the realm
  rate); `qi_cost` and `cooldown` (exactly the two quantities ADR 0055 publishes rung
  multipliers on — a band is a second multiplier, the shape ADR 0160 refuses); and
  `stamina_cost` (ADR 0055 publishes no stamina column, so there is no rung
  multiplier to pair with and a band would be the only multiplier on it — a
  different balance question, not this one).
- **The window is this file's, not the catalog's.** Every one of the 29 `cult_*`
  options in `master_option_pool.jsonl` declares `bounds {min: 0.0, max: 9999.0}` —
  a sanity ceiling, not a balance window — so the band cannot be delegated and is
  authored here. `OptionCatalog.clamp_to_bounds` is still applied AFTER the band, so
  an option's own bounds are the last word.
- **The band is both-sided** (`0.75` / `1.25`), so a copied manual is on average the
  manual it was copied from; a one-sided band would make the printed value a number
  no player ever gets. The floor cannot take a positive stat negative and the
  ceiling is bounded by construction, never by arithmetic.
- **No engine nodes, no `Time.get_ticks*`, no `_process`.** `TechniqueMarginalia`
  stays `RefCounted`, and a copy's annotations are a pure function of
  (authored text, seed source).
- **`tools technique_power check` still passes**: a roll never touches `magnitude`,
  so it cannot move the authored ladder the tool walks.
- **Reachability is asserted through the real path**, not the component: the new
  case drives `ItemsApi.use_item` → `ItemUse._study_technique` → the installed
  `TechniqueDelivery.study` → `bind_learner` → `TechniquesApi.learn` → `draw`, the
  same chain a player drives, and reads the result off the **stored codex row** so a
  roll that was drawn and then dropped fails there.
- **Facade:** `TechniquesApi` stays at exactly **12** public methods against
  `MAX_FACADE_PUBLIC_METHODS`. The roll is reached the way `CASTING_COMPONENT`,
  `DELIVERY` and `CAST_VIEW` are — from inside `learn`, which was already a facade
  method. This ruling adds none.