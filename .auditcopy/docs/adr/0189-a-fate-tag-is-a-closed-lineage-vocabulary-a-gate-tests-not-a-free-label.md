# 0189 A fate tag is a closed lineage vocabulary a gate tests, not a free label

- Status: Proposed
- Date: 2026-10-04
- Depends on: ADR 0065 (a fate is earned, never chosen, never removed), ADR 0113 (a gate reading a fact is a new verb in one evaluator), ADR 0134 (destiny is a hub)

## Context

`FateDef.tags` was authored, published into `summary()`, and read by nothing. Eleven of seventeen fates carried tokens, and three shipped gates named a specific fate where the author clearly wanted a KIND (`the_severed_calling` gated `oath_breaker`, two more gated `first_blood_duel`) — so the author wrote a tag and got no behaviour, and worked around it by naming the instance.

The authored tokens were three kinds of thing at once: lineage (`oath`, `duel`, `mercy`), stat language (`aggressive`, `defensive`, `heavy`, `resilient`, `fast_path`, `killcount`, `marked`), and position words (`first`, `solitary`). All three cannot be gated the same way, and only the first is a lineage.

## Decision

**Tags are the closed lineage vocabulary of one gate verb, `{verb: "tagged", id: <tag>}`.**

- **`FateDef.TAGS` is the whole vocabulary: `oath, blood, mercy, severance, desertion, rebirth, duel`.** All seven were already authored on shipped fates. An author may NOT coin a tag. Engine-shaped tokens are excluded because they restate `flat_modifiers`/`percent_modifiers` — a gate on "heavy" is stat language leaking into a gate, and two fates whose bonuses were retuned together would silently start agreeing on a lineage. `heaven` duplicates `category`; `first`/`solitary` are position words the existing `counter` verb answers better.
- **OR across fates.** `{verb:"tagged", id:"oath"}` is satisfied by holding ANY ONE fate carrying `oath`. Tags are unordered with no primary, so a per-fate variant is the only other reading and `has_fate` already is exactly that.
- **Three refusals, kept apart.** A tag the actor's fates do not carry is `_fail`, `reason == "unmet"`, entry `kind:"tag"`, `id` = THE TAG THE AUTHOR WROTE (never a resolved fate id — the `unmet_prerequisites` rule at `destiny_gate.gd:107`). A tag outside `FateDef.TAGS` is `reason == "unknown_tag"` naming itself, mirroring `unknown_verb`; it NEVER degrades to `unmet`, because nothing in the tree carries a coined tag and `unmet` would be a permanent lie with no actionable cause. `{verb:"tagged"}` with no `id` is `reason == "malformed"` and NEVER defaults to "any tagged fate satisfies this".
- **`unknown_tag` POISONS a composite.** It joins `POISON_REASONS` beside `malformed` and `unknown_verb`. Without it a bad tag degrades to a plain unmet the instant it is nested, and `all_of:[{tagged:"oath"},{tagged:"not_a_tag"}]` reports a false, actionable cause.
- **`EventGate` names `tagged` in BOTH `DELEGATED_VERBS` and `KNOWN_VERBS`.** One without the other is a tool/runtime disagreement: the runtime opens the event while `EventReadModel` reports the row a typo.
- **Earn-only preserved.** A `tagged` gate READS the ledger. It never writes, and a tag is consulted rather than consumed, so no gate can remove a fate.
- **`tags` is NOT `DestinyDef.group` and the two must never be unified.** A group closes its members against each other permanently — earn one and the rest are forfeit. A tag is the opposite: one question several fates may answer. Same vocabulary, opposite semantics; unifying them would make every lineage gate an exclusivity rule.
- **`_fate_view` now gates `tags` on `reveal`.** An unheld fate whose `visibility == hidden` publishes `[]`. This is a published-key contract change and is deliberate: once a `tagged` gate exists, an unconditional `tags` is a spoiler channel — a gate can display "you need a duel-marked fate" and leak that a hidden fate exists and carries `duel`. `the_third_man_spared` is `hidden` and carries `[mercy, duel]`.

## Consequences

- **A fate earns nothing by carrying a tag** (ADR 0065). No stat, no reward, no unlock; the verb is a read. A future agent who finds an unused tag is looking at a gate that has not been authored yet, not at dead content.
- **Empty `tags` is legal** and means "answers to no lineage question". Six of seventeen shipped fates have none, and `heaven_s_chosen_instrument` and `one_hundredth_slain` joined them when their tokens were dropped as stat language. Not an error, and no gate may infer anything from an empty list.
- **Tags are never exclusive, never ordered, never consumed.** A `tagged` gate is monotone in the ledger: reading it leaves the ledger byte-identical.
- **`tools/data.py` OWES a hard-FAIL check** (not a warn): every authored `tags` entry inside `FateDef.TAGS`, and a whole-tree walk for `{verb:"tagged"}` rows naming an out-of-vocabulary tag, mirroring `_authored_counter_gates`/`_counter_findings`. A gate nothing can open is a permanent lie, and unlike an unwired `FateDef.counters` id it does cost a player a door.
- **Adding a tag is not a content edit.** It is a change to a closed vocabulary, which is why the vocabulary is one constant on one class rather than a set discovered by scanning what content happened to author.