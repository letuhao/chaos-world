# 0212 The four levers are four budgets not four magnitudes and each is spent in its own currency

- Status: Accepted
- Date: 2026-10-05
- Closes: BL-0844, BL-0845
- Depends on: ADR 0075 (accepted), ADR 0086, 0200 (mitigation is a ratio, not an authored percent)

## Context

Two measured facts, and the second is the one that should have been caught at authoring time.

**1. The levers are wired and now spend.** The chain closes: a zone resolves a residual for
*this* actor (`environment_field.gd:637 _amount`) → the status carries that residual as
`magnitude` (`environment_field.gd:574 _hazard`) → `StatusApi.resolve` registers a runtime
(`status/api.gd:391`) → `tick_statuses` pulses it → `_pulse` spends `magnitude *
share_per_pulse` off health (`status/api.gd:697-700`). Health moves. The tag lists are
populated by `DomainBoot.publish_ward_tags` on entry and on every room visit
(`domain_boot.gd:295`, `:367`), so `GEAR_CAP` / `TECHNIQUE_CAP` / `PILL_CAP` gate real lists.
So the residual BL-0844 describes as "a magnitude nothing spends" is now spent — what is
missing is not the plumbing but the *shape*, because the four levers are currently four
magnitudes of one thing.

**2. Affinity is structurally dead on every trap.** `DomainFixtures._holds` returns `false`
for `LEVER_AFFINITY` unconditionally (`domain_fixtures.gd:610-616`). The stated reason is
that a trap authors no element. But every shipped trap carries a **status id that does**:
`ash_chamber_vein` → `fire_immolation` (`ash_chamber.tres:17`),
`storm_gallery_arc` → `lightning_arc` (`storm_gallery.tres:29`),
`storm_gallery_vent` → `wind_gust` (`storm_gallery.tres:30`) — and each of those defs names
its element (`fire_immolation.tres:8 element = &"fire"`). Two of the three traps also author
`affinity` in their own `mitigation_tags` (`ash_chamber.tres:17`,
`storm_gallery.tres:30`). So a fire-rooted cultivator is published a lever on a fire trap that
can never fire: the read model advertises counterplay the game cannot deliver, which is the
exact defect ADR 0075's `mitigation_tags` rule exists to prevent.

## Decision

**Each lever is a budget in its own currency. They are not four magnitudes of one percent, and
they are never summed.**

- **The four currencies, and what each costs the player:**

  | Lever | Currency | What it costs | Answers |
  | --- | --- | --- | --- |
  | `affinity` | **identity** | nothing — it cannot be lost, sold or consumed | "this body was made for this place" |
  | `gear` | **loadout** | the slot, the weight, the realm floor — permanently, before the run | "I chose to come prepared" |
  | `technique` | **attention** | a codex entry and the qi to keep it running | "I spent my training on this" |
  | `pill` | **a consumable, now** | the item, on the spot, once | "I have one answer and then I have none" |

  Two structural facts make these four answers rather than four magnitudes:
  - **They resolve on different clocks.** `affinity` and `gear` are resolved *before* entry and
    are known for the whole stay; `technique` is resolved *on* entry; `pill` is resolved *after*
    the first pulse. A player with four identical caps and a pill in hand does not have four
    options — they have one commitment, one preparation and one emergency.
  - **Only `pill` is finite.** Three of the four are a state the player holds; one is an object
    they can run out of. That asymmetry is what makes a hazard a resource decision instead of
    a stat check, and it is why `affinity`'s cap is the highest (0.50,
    `environment_field.gd:208`): the lever you cannot lose is the one allowed to be strongest,
    and it is strongest only for a root that was authored for that element.
- **`affinity` is live on a trap, and it reads the STATUS's element, not the fixture's tags.**
  The fixture's `tags` (`ember`, `stone`, `ruined`) are room vocabulary and belong to no
  `HOSTILE_ELEMENTS` row; the status it lands is element-riding and does. So `_holds` resolves
  through the same `_affinity_weight` the field uses (`environment_field.gd:693`), against the
  trap's authored `status_id`. A fire root now answers a fire trap, which is the whole point of
  ADR 0075's claim that affinity is "the first consumer giving `race` a reason to matter in
  traversal".
- **Caps stop being a ladder of magnitudes and become a ceiling on one lever's share.** The
  existing 0.50 / 0.40 / 0.30 / 0.35 (`environment_field.gd:208-211`) are kept as authored
  ceilings, but **at most one lever is ever credited for a single hazard instance.** The
  current `_lever_for` already returns on first match (`environment_field.gd:620-636`,
  `domain_fixtures.gd:589-602`); this ADR makes that a rule rather than a coincidence, because
  a player who is handed a summed 0.95 has been handed a hazard that stopped being a hazard.
  Identity-first ordering (`affinity`, `gear`, `technique`, `pill`) is preserved: the lever you
  cannot lose is consulted first, so the answer is stable.
- **A lever is credited only if it is structurally inert-free on the substrate.** Already true
  and load-bearing: `LEVER_SUBSTRATES` (`environment_field.gd:213`) plus the `pressure` row of
  `HOSTILE_ELEMENTS` (`environment_field.gd:262`) is why a spirit root cannot blunt a
  pressure zone. `has_non_affinity_mitigation` (`environment_zone_def.gd:111`) keeps the
  authored guarantee that a wrong root is never left with no answer.
- **The number each lever resolves is a SHARE OF A HAZARD, never a stat.** No lever writes a
  `StatModifier` and no lever is a defense stat. This is what ADR 0200 decided for combat and
  this ADR extends it to the place: a mitigation percent authored per lever is exactly the
  "cap on an input" shape ADR 0200 deletes.

### The test that ends this class of finding

A lever is real only when **a headless run can show health falling by one number and by a
different, smaller number with the lever equipped** — not that `residual_share` returns a
smaller value. The read-model functions (`residual_share`, `residual_amount`, `mitigated_by`)
stay for previewing; the *proof* is the same two tick loops.

## Consequences

- **`DomainFixtures._holds`'s unconditional `false` is deleted.** No affinity branch is left
  special-cased, so the file stops carrying a comment that contradicts its own module
  rationale.
- **A fire root stops being a worse pilot than a neutral one in an ash chamber** — the identity
  payoff ADR 0075 promised and the game did not deliver.
- **`BODY_GEAR_FACTOR := 0.75`** (`environment_field.gd:283`) stays: the one place two levers
  interact, encoding a real truth (plate buys less against a deadline than against a blow). It
  is not a fifth lever.
- **The four caps are no longer comparable** and must not be read as a ranking. An author who
  sorts them and tunes the order re-introduces the "four magnitudes of one number" failure.