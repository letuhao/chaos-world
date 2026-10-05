# 0196 The codex quotes the price and the shortfall, and a preview is not a second door to a learned technique

- Status: Accepted
- Date: 2026-10-04
- Depends on: ADR 0053 (three states, the item delivers), ADR 0055 (the price ladder), ADR 0160 (the payer is `PathState.progress`), ADR 0188 (a verb is kept by a caller that is not a test)
- Closes: the `ui/` half of DEF-0244. The module and workbench halves are NOT closed — see "What this does not close".

## Context

DEF-0244 recorded the finding precisely, and it is worth repeating because the
finding is narrower than "the price is not shown":

> `TechniquesApi.inspect` publishes `learn_price` and an empty `learn_unmet` as the
> study preview, and `technique_codex.gd` `_entry_view` consumes it, yet the codex
> screen is deliberately read-only and the loadout screen only ever offers techniques
> ALREADY learned. So the price is computed, returned in the learn outcome, and
> asserted in tests, and no human sees it before committing a manual.

Reading the tree for the fix produced three facts, each of which removes an option:

**1. The codex cannot show an unlearned technique at all.**
`TechniquesApi.summary` publishes `entries` = `codex.entries()` — LEARNED only
(`technique_read_model.gd:30`). `technique_codex.gd:149` feeds exactly that list. So
`_price_text`'s `if known_entry(): return KNOWN_TEXT` branch is the only one a
shipped feed can reach, and the `Not learned — 120` branch is dead code.

**2. Listing an unlearned technique needs a non-facade module type.**
`TechniqueCatalog` is not `api.gd`, and `tools/arch/enforce.py:158` turns that into
a violation: *"'ui/' may reference 'techniques' only through modules/techniques/api.gd"*.
No facade method enumerates learnable techniques, and ADR 0160 records the cap as
binding. Enumerating would therefore require the 13th method.

**3. Affordability is not published anywhere.**
`grep can_pay` over `modules/techniques/` finds nothing. `TechniquesApi._short`
(`api.gd:381`) is private and its `{resource, required, current}` list appears only
in the `learn` OUTCOME — i.e. after the press. `PathState` is `contracts/`, so `ui/`
*could* re-derive the answer by hand, and `character_screen.gd:81` already reads
path progress. It does not, because the derivation IS ADR 0160's rule: which pool a
study charges is `def.path_ids()[0]`, and `shared` is deliberately not a pool.

## Decision

### The price and the shortfall are rendered together, and the shortfall is shown

A price a hero cannot compare against their own progress is half a feature. The row
renders the module's three answers as one unit, each printed **only when the module
published it**: the gate (`learn_unmet`), the price (`learn_price`), and the shortfall
(`learn_short`, as path + owed + held, in words rather than as `qi_cultivation`).

Silence is a legitimate state. An unlearned technique with no shortfall and no gate
prints no verdict, because the module has not been asked and the row will not invent
one. This is the same stance `anchor_construction_row.gd` takes: `missing` arrives
from `AnchorApi.summary`, and the row never counts the bag.

**The shortfall is styled as a refusal** (`WarnLabel`) while a plain price is not.
A hero who cannot pay must not read it in the same ink as an ordinary price — the
difference between rendering a refusal and hiding a control.

### Affordability is RELAYED, never derived

The screen copies `learn_short` and `can_pay` out of `inspect` when present and
publishes `can_pay_known` when it can tell the difference between "false" and "not
answered". It does **not** compute either.

The module must publish these for a hero to see them. The change here costs the
facade **zero** methods — it is the same trick ADR 0056 already documents for
`CASTING_COMPONENT`, `DELIVERY` and `CAST_VIEW`: a read-model key on `inspect`, not a
new verb. The relay is tested today so a future extension lands on a tested seam
rather than a second one.

### A learned technique publishes `0.0`, deliberately

`inspect().learn_price` is the price of a DUPLICATE manual and is published for
learned techniques too. The row passed it straight through, so a consumer reading
`summary()` concluded that holding a technique costs money — the same
published-but-misleading shape as DEF-0244 itself, one layer down. A known entry now
publishes `0.0`, and neither a shortfall nor a gate is printed for it.

### A preview is not a second door to one state

ADR 0053:31 — *"An `ItemDef` delivers a technique, is consumed, and is gone."*
ADR 0053:73 — *"The item is purely an acquisition vector."* DEF-0244's own `next`
forbids the page that would have been easy: *"Do not add it to the read-only codex
page; a codex that offers to buy breaks the ADR 0053 separation."*

So this change adds **no verb**. `on_stack_input` still returns `false`, the screen
still publishes no `act_*`, and `technique_equip_picker.gd:50` records the same
boundary for equipping: *"no pick here can ever become a learn"*. A preview is a
*read*: it writes nothing, and the only way to spend the price is still to use the
manual. That is asserted as behaviour, not as an absence of code — a test reads the
page and checks the hero's progress is unchanged.

## What this does not close

Two pieces of DEF-0244 remain open, and both are outside `ui/`. They are recorded
here rather than in the ADR's own Consequences because they are the same finding seen
from the module side:

- **The module publishes no affordability.** `TechniquesApi.inspect` needs
  `learn_short` + `can_pay` (or a `shortfall` block) computed from `_short` /
  `_study_charge`, which are already written and already tested. **No facade method
  needed** — this is a read-model key, the ADR 0056 pattern. Until it lands, the
  shortfall line never populates from a production feed, though the code path and
  the test are in place.
- **The workbench drops the price.** `item_workbench.gd:166-168` reduces
  `ItemsApi.use_item`'s outcome to `String(result.get("reason"))`, discarding
  `learn_price` and `short` from a study outcome. This is the surface DEF-0244 names
  literally, and it lives in `ui/screens/item_workbench.gd` — not owned here, and
  currently unparseable behind the loot breakage.

## Consequences

- A hero reading a codex entry is told what a study costs, in the module's own
  figures, before committing a manual.
- A hero who cannot pay is told **which pool**, what it owed and what it held — the
  three numbers `_short` already published and nobody rendered.
- A hero holding a technique is no longer told they owe for it.
- The facade is still at exactly 12 public methods, asserted in the suite.
- A preview provably cannot become a learn: it writes nothing, and the gate on
  spending a price remains `use_item`.

## Mutation evidence

The suite is worth its assertions only if it can go red. Three mutations were applied
to `technique_entry_row.gd` and each was caught by named assertions:

| Mutation | Result | Caught by |
|---|---|---|
| `"learn_price": 0.0` (blank the price) | RED, 63/2 | "published at the module's own price", "the price is still published" |
| `"can_pay": true` (always payable) | RED, 63/2 | "so this actor cannot pay", "nothing was claimed" |
| drop the shortfall branch of `_note_text` | RED, 62/3 | "names the pool in words", "and what is owed", "and what is held" |

The third is the load-bearing one: it keeps the relay intact and breaks only the
RENDERING, which is what proves the assertions test a value a player could see rather
than a value a screen happened to publish.