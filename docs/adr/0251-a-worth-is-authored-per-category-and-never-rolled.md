# 0251 A worth is authored per category and never rolled

- Status: Accepted
- Date: 2026-10-05

Closes DEF-0128. Builds on ADR 0094 (the price function), ADR 0026 (fixed and
rolled are separate channels), ADR 0028 (an option has a real consumer) and
ADR 0050 (one magnitude ladder per quantity, never two).

## Context

ADR 0094 fixes the only price function in the game:

```
unit_price = maxi(1, roundi(base_worth * RARITY_WEIGHT[rarity] * RealmRate.factor(realm)))
```

and defines `base_worth` as read from the item's **fixed** `trade_value`
modifier. The formula is fine and is not touched by this ADR. What was missing
was the corpus of authored inputs: an unauthored worth floors the whole product
at 1, so the floor is reached by every item that has no worth, rarity and realm
are multiplied into a constant, and a rare axe trades like a twig.

DEF-0128 recorded this as "221 of 7945 items carry a worth". **That number is
stale and was not used.** Measured against the tree as it stood when this ADR
was written, over the 8023 `game/data/items/**/*.tres` defs:

| before | defs |
| --- | --- |
| carry a `trade_value` in any channel | **680** |
| — `currency` | 221 |
| — `key` | 228 |
| — `misc` | 231 |
| — `quest` | **0 of 233** |
| — `material` / `consumable` / `equipment` / `technique` | 0 of ~6940 |

Three earlier waves had already closed most of the gap; the last honest slice is
`quest`, plus two stragglers in `key`.

A second measurement decides what may be authored at all. `trade_value`'s
catalog record in `game/data/item_options/master_option_pool.jsonl` declares
`categories: ["currency"]`, and `activations_for` derives the only channel it may
be authored on as `{"property"}`. `CATEGORY_ACTIVATION` maps `key`, `currency`,
`quest` and `misc` to `property`, and maps `material`, `consumable`,
`technique` and `equipment` to `crafted` / `consumed` / `equipped` / `learned`.
So authoring `trade_value` on a material — the obvious slice, and by far the
largest — is a **misactivated row** that `tools data items` rejects on sight.
Those ~6940 defs are not authorable, and pretending otherwise would be fiction.

## The rolled-vs-fixed rule, and the `option_id` detail

`trade_value` is **ROLLABLE**. It belongs to the option contexts `base`,
`prefix` and `postfix`, so on a def whose own `roll_spec` names a context the
rarity policy actually chooses, the generator can realize a **rolled** worth.

The rule this ADR commits to, matching `EconomyValuation` exactly:

- `EconomyValuation.base_worth_of` reads **only `def.fixed_modifiers`**. It
  deliberately does not call `ItemDef.property_total`, because that funnels
  fixed and rolled together (ADR 0026).
- `EconomyValuation.has_rolled_worth` refuses any instance whose `rolled` array
  holds an effect with **`option_id == OptionTarget.TRADE_VALUE`**. It matches
  **`option_id`**, never `target_id`. A realized effect carries both keys, so a
  guard that matched the wrong one would never fire — the check exists precisely
  to catch a rolled price, and matching the wrong key would silently never fire.
- An instance that rolled a price input is **refused, not priced**: `EconomyExchange`
  and `MarketApi` will not settle it.

Therefore: **a worth is authored only into `fixed_modifiers`, and only onto a
def on which no seed can realize a rolled one.** A def that can roll a worth gets
**no worth at all** — not a price that later makes it unsettleable. A price
nobody can pay is not a price.

The test for "can roll" is `worth_rewrite.can_roll_a_worth`. `ItemGenerator.roll`
intersects the rarity policy's contexts with the def's own:

```
chosen = ItemRarity.contexts(def.rarity) & def.roll_spec.contexts
```

`ItemRarity.POLICY` names only `prefix` (common) and `prefix`/`postfix`
(magic, rare, legendary). **`base` is never chosen.** A def whose `roll_spec`
names only `base` chooses nothing, `roll()` returns early, and no seed can reach
the `rolled` channel. A def naming `prefix` or `postfix` has `trade_value` live
in its `property:<context>` pool at weight 3.0 of 15.0 — a real candidate.

Measured consequence: every already-priced `misc` def (`roll_spec` = `{base, prefix}`)
**can** roll a worth and is refused; no `currency` or `key` def (`roll_spec` =
`{base}`) ever can. The remaining honest slice, `quest`, declares
`roll_spec.contexts == ["base"]` throughout and is safe on both counts.

## Decision

### The grouping rule, in one line

**A def's worth is a pure function of its own `(category, grade)` — its directory
under `game/data/items/` and the tier rung that directory's own items already
occupy — and of nothing else.**

Both inputs are read off the def itself. Neither is a lookup into another table,
which is what keeps the wave clear of ADR 0050's failure (a second magnitude
ladder). Two axes are deliberately absent because ADR 0094's formula already owns
them as multipliers:

- **rarity** → `RARITY_WEIGHT` (1.0 / 1.6 / 2.6 / 4.0). Folding it in would
  decide a legendary item's price by rarity twice.
- **realm** → `RealmRate.factor` (`1.02^ordinal`, bounded at 1.776). A per-realm
  worth would be a second per-realm ladder on the same quantity, and would meter
  the 551x actor ladder by price as well as by power — ADR 0050's open debt.

`worth_rewrite.no_realm_term_in_the_ladder` is the machine check that the rung
table stays built from two constants that name neither.

### Category floors — "what does obtaining this cost", never "how strong is it"

A price is a cost, not a magnitude.

| category | floor (`mortal`) | why |
| --- | --- | --- |
| `currency` | 2 | a note or a token; the cheapest thing that exists, and the reason every other category sits above it |
| `key` | 5 | a document that opens something; priced for what it admits, not for the door |
| `misc` | 8 | no use of its own, carried because someone wanted it; deliberately above `currency` |
| `quest` | 10 | a delivered consequence; never sold back (a shop's `buys` list expresses that refusal, ADR 0100) |

### Grade rungs — one shared shape, so a designer retunes by moving one number

`mortal → spirit → earth → heaven → immortal → divine` at
`1.0 / 1.6 / 2.1 / 2.7 / 3.4 / 4.2` of the category floor. Every category uses the
same shape, and every multiplier sits at or under the formula's own 4x rarity span,
so the grade axis never out-shouts rarity. The whole ladder spans about 21x, of
which the formula supplies about 7x from rarity and realm together: the category
term is a *distinguishing* term, not a dominant one, and no category's worth reads
as a power statement.

### The writer's three guarantees

1. **Never overwrite.** A file that already carries a `trade_value` in
   `fixed_modifiers` is skipped and counted as "already carry an authored worth".
   A re-run is therefore a no-op by construction, with no marker needed.
2. **Never emit a rolled worth.** The write path opens
   `fixed_modifiers = Array[Dictionary]([...])` and appends one row inside it.
   There is no code path from the writer to `rolled_modifiers`, and every def
   that `can_roll_a_worth` is **refused and reported by name**, never written.
3. **Never leave an item unreachable.** The writer touches one line inside one
   existing array in an existing file. No `sources`, no `id`, no realm, rarity,
   category or subcategory is parsed into a write path. `gather_route` and
   `forage_surface` (114/0 and 141/0) are the proof, and they must stay green.

### A count is not a goal

Nothing here exists to move a coverage number. The wave's honest measure is
"was every **authorable, non-rollable, in-scope** def priced, and nothing else
touched" — and the ladder's quality is judged per category, by asking whether the
`quest` rung for a low-tier consequence and the `currency` rung for a token both
read as defensible numbers. A worthless item priced at 1 is honest; a healing herb
priced like a celestial pill is the defect this ADR exists to prevent. An item
that cannot legally carry a worth carries none.

## Consequences

- `quest` goes from 0 of 233 to all 233, and the tree from **680 of 8023** to
  **915 of 8023** defs carrying an authored worth.
- `misc` stays at 231 and gains nothing: every one of its defs names a rollable
  context, so a fixed worth there would convert a priced item into an unsettleable
  one. That is a recorded refusal, not an oversight.
- `material`, `consumable`, `equipment` and `technique` stay unpriced: authoring
  `trade_value` on them is a misactivated option row by ADR 0028.
- ~7108 defs still floor at 1. That is the correct reading of "no authored worth",
  and it is the honest state of a corpus whose option catalog has no
  `property`-channel price input for those categories yet. Widening it means
  changing `trade_value`'s declared categories in the master option pool — a
  catalog decision for a later wave, deliberately not smuggled into this one.
- The writer is `tools/worth_rewrite.py`, dry-run by default, deterministic, and
  scoped by explicit `--roots` / `--categories`.